// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title WebAI3 Presale Contract
/// @notice Manages a 7-phase presale raising $7M USDC for AIC token allocation.
///         Phases advance automatically when cumulative funding caps are reached.
///         Tokens are claimable after presale finalization and TGE delay.
contract WebAI3Presale is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────

    struct Phase {
        uint256 phaseCap; // Cumulative USDC cap (6 decimals)
        uint256 pricePerToken; // USDC per AIC token (6 decimals)
        uint256 maxTokens; // Max AIC tokens for this phase (18 decimals)
        uint256 startTime; // Unix timestamp phase begins
        uint256 endTime; // Unix timestamp phase ends (time-based fallback)
        uint256 soldTokens; // Running total sold in this phase
    }

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    event PresaleInitialized(uint256 phaseCount, uint256 tgeTime);
    event TokensPurchased(
        address indexed buyer, uint256 usdcAmount, uint256 aicAmount, uint256 indexed phaseIndex
    );
    event PhaseAdvanced(uint256 indexed newPhase, uint256 price);
    event PresaleEnded(uint256 totalRaisedUSDC, uint256 totalTokensSold);
    event PresaleFinalized(uint256 totalRaisedUSDC, uint256 totalTokensSold);
    event TokensClaimed(address indexed user, uint256 amount);

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error PresaleNotActive();
    error PresaleAlreadyInitialized();
    error ZeroAmount();
    error NoActivePhase();
    error PhaseTokenCapExceeded();
    error HardCapExceeded();
    error PresaleNotFinalized();
    error TGENotReached();
    error NothingToClaim();
    error AlreadyClaimed();
    error InvalidAddress();
    error InvalidPhaseConfig();
    error PhasesNotOrdered();
    error PresaleStillActive();

    // ──────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────

    uint256 public constant HARD_CAP = 7_000_000e6; // $7M in USDC (6 decimals)
    uint256 public constant PRESALE_ALLOCATION = 500_000_000 ether; // 500M AIC
    uint256 public constant TGE_DELAY = 7 days;

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    IERC20 public immutable usdc;
    IERC20 public immutable aicToken;
    address public immutable treasury;

    // ──────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────

    Phase[] public phases;
    uint256 public totalRaisedUSDC;
    uint256 public totalTokensSold;
    bool public presaleActive;
    bool public presaleFinalized;
    uint256 public tgeTime;

    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAllocations;
    mapping(address => bool) public hasClaimed;

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(address _usdc, address _aicToken, address _treasury) Ownable(msg.sender) {
        if (_usdc == address(0) || _aicToken == address(0) || _treasury == address(0)) {
            revert InvalidAddress();
        }
        usdc = IERC20(_usdc);
        aicToken = IERC20(_aicToken);
        treasury = _treasury;
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────

    /// @notice Initialize presale with phase configuration.
    /// @param _phases Array of Phase structs. Must be ordered by ascending phaseCap.
    function initializePresale(Phase[] memory _phases) external onlyOwner {
        if (phases.length > 0) revert PresaleAlreadyInitialized();
        if (_phases.length == 0) revert InvalidPhaseConfig();

        for (uint256 i = 0; i < _phases.length; i++) {
            Phase memory p = _phases[i];

            if (p.startTime >= p.endTime) revert InvalidPhaseConfig();
            if (p.pricePerToken == 0) revert InvalidPhaseConfig();
            if (p.maxTokens == 0) revert InvalidPhaseConfig();
            if (p.phaseCap == 0) revert InvalidPhaseConfig();
            if (p.soldTokens != 0) revert InvalidPhaseConfig();

            if (i > 0) {
                if (p.phaseCap <= _phases[i - 1].phaseCap) revert PhasesNotOrdered();
            }

            phases.push(p);
        }

        tgeTime = _phases[_phases.length - 1].endTime + TGE_DELAY;
        presaleActive = true;

        emit PresaleInitialized(_phases.length, tgeTime);
    }

    /// @notice Finalize the presale — transfers USDC to treasury, enables claims.
    function finalizePresale() external onlyOwner {
        if (!presaleActive) revert PresaleNotActive();

        presaleActive = false;
        presaleFinalized = true;

        uint256 balance = usdc.balanceOf(address(this));
        if (balance > 0) {
            usdc.safeTransfer(treasury, balance);
        }

        emit PresaleFinalized(totalRaisedUSDC, totalTokensSold);
    }

    /// @notice Pause presale (emergency).
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause presale.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ──────────────────────────────────────────────
    // User — Buy
    // ──────────────────────────────────────────────

    /// @notice Purchase AIC tokens with USDC during the active phase.
    /// @param usdcAmount USDC to spend (6 decimals).
    /// @return aicAmount AIC tokens allocated (18 decimals).
    function buyTokens(uint256 usdcAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 aicAmount)
    {
        if (!presaleActive) revert PresaleNotActive();
        if (usdcAmount == 0) revert ZeroAmount();

        uint256 phaseIdx = getActivePhase();
        if (phaseIdx == type(uint256).max) revert NoActivePhase();

        Phase storage phase = phases[phaseIdx];

        // Calculate AIC: (usdcAmount * 1e18) / pricePerToken
        aicAmount = (usdcAmount * 1e18) / phase.pricePerToken;

        if (phase.soldTokens + aicAmount > phase.maxTokens) revert PhaseTokenCapExceeded();
        if (totalRaisedUSDC + usdcAmount > HARD_CAP) revert HardCapExceeded();

        // Interaction: pull USDC
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Effects
        contributions[msg.sender] += usdcAmount;
        tokenAllocations[msg.sender] += aicAmount;
        totalRaisedUSDC += usdcAmount;
        totalTokensSold += aicAmount;
        phase.soldTokens += aicAmount;

        // Auto-advance event
        if (totalRaisedUSDC >= phase.phaseCap && phaseIdx < phases.length - 1) {
            emit PhaseAdvanced(phaseIdx + 1, phases[phaseIdx + 1].pricePerToken);
        }

        // Hard cap reached → end presale
        if (totalRaisedUSDC >= HARD_CAP) {
            presaleActive = false;
            emit PresaleEnded(totalRaisedUSDC, totalTokensSold);
        }

        emit TokensPurchased(msg.sender, usdcAmount, aicAmount, phaseIdx);
    }

    // ──────────────────────────────────────────────
    // User — Claim
    // ──────────────────────────────────────────────

    /// @notice Claim allocated AIC tokens after presale finalization and TGE.
    function claimTokens() external nonReentrant returns (uint256 aicAmount) {
        if (!presaleFinalized) revert PresaleNotFinalized();
        if (block.timestamp < tgeTime) revert TGENotReached();
        if (tokenAllocations[msg.sender] == 0) revert NothingToClaim();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        aicAmount = tokenAllocations[msg.sender];
        hasClaimed[msg.sender] = true;

        aicToken.safeTransfer(msg.sender, aicAmount);

        emit TokensClaimed(msg.sender, aicAmount);
    }

    // ──────────────────────────────────────────────
    // View
    // ──────────────────────────────────────────────

    /// @notice Returns the index of the currently active phase, or type(uint256).max if none.
    ///         Phase selection is fund-driven: the first phase whose cumulative cap has not been
    ///         reached is the active phase. Time checks ensure we are past presale start and
    ///         before the active phase's end deadline.
    function getActivePhase() public view returns (uint256) {
        for (uint256 i = 0; i < phases.length; i++) {
            if (totalRaisedUSDC < phases[i].phaseCap) {
                // Presale must have started (Phase 0 start time)
                if (block.timestamp < phases[0].startTime) return type(uint256).max;
                // Phase must not have expired
                if (block.timestamp >= phases[i].endTime) return type(uint256).max;
                return i;
            }
        }
        return type(uint256).max; // All phases fully funded
    }

    /// @notice Overall presale status.
    function getPresaleStatus()
        external
        view
        returns (
            uint256 activePhase,
            uint256 totalRaised,
            uint256 totalTokens,
            uint256 percentToHardCap,
            bool active
        )
    {
        activePhase = getActivePhase();
        totalRaised = totalRaisedUSDC;
        totalTokens = totalTokensSold;
        percentToHardCap = HARD_CAP > 0 ? (totalRaisedUSDC * 100) / HARD_CAP : 0;
        active = presaleActive;
    }

    /// @notice Get phase info by index.
    function getPhaseInfo(uint256 idx) external view returns (Phase memory) {
        return phases[idx];
    }

    /// @notice Get user info.
    function getUserInfo(address user)
        external
        view
        returns (uint256 contributed, uint256 allocated, bool claimed_)
    {
        contributed = contributions[user];
        allocated = tokenAllocations[user];
        claimed_ = hasClaimed[user];
    }

    /// @notice Number of configured phases.
    function getPhaseCount() external view returns (uint256) {
        return phases.length;
    }
}
