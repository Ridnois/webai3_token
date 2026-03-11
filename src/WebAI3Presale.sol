// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./presale/PresaleErrors.sol";
import { IPresaleVault } from "./presale/interfaces/IPresaleVault.sol";
import { IClaimModule } from "./presale/interfaces/IClaimModule.sol";
import { IWebAI3PresaleState } from "./presale/interfaces/IWebAI3PresaleState.sol";

/// @title WebAI3Presale
/// @notice Main presale entrypoint for AIC allocations against USDC contributions.
/// @dev Deployment assumptions:
/// 1) PresaleVault and ClaimModule are deployed first.
/// 2) `setPresale` is called once on both modules.
/// 3) Presale claim tokens are pre-funded in ClaimModule.
contract WebAI3Presale is AccessControl, ReentrancyGuard, IWebAI3PresaleState {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant HARD_CAP = 7_000_000e6;
    uint256 public constant PRESALE_TOKEN_CAP = 500_000_000 ether;

    uint256 public constant MAX_SINGLE_PAUSE = 72 hours;
    uint256 public constant MAX_CUMULATIVE_PAUSE = 14 days;

    uint8 public constant PHASE_COUNT = 7;

    struct Phase {
        uint256 cumulativeRaiseCapUSDC;
        uint256 pricePerTokenUSDC6;
        uint256 tokenCap;
        uint256 soldTokens;
    }

    enum Lifecycle {
        Pending,
        Active,
        Paused,
        Ended,
        Finalized
    }

    IERC20 public immutable usdc;
    IPresaleVault public immutable presaleVault;
    IClaimModule public immutable claimModule;

    uint64 public immutable PRESALE_START_TIMESTAMP;
    uint64 public immutable PRESALE_END_TIMESTAMP;

    bool public override presaleFinalized;

    bool internal _pauseActive;
    uint64 public currentPauseStartedAt;
    uint256 public cumulativePausedDuration;

    uint256 public totalRaisedUSDC;
    uint256 public totalAllocatedTokens;

    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAllocations;

    Phase[PHASE_COUNT] internal _phases;

    event TokensPurchased(
        address indexed buyer,
        uint256 usdcAmount,
        uint256 aicAmount,
        uint8 indexed phaseIndex,
        uint256 totalRaisedAfter
    );
    event PhaseAdvanced(
        uint8 indexed previousPhase, uint8 indexed nextPhase, uint256 nextPriceUSDC6
    );
    event PresaleFinalized(
        uint64 indexed finalizedAt, uint256 totalRaisedUSDC, uint256 totalAllocatedTokens
    );
    event PauseActivated(
        address indexed by, uint64 indexed startedAt, uint256 cumulativePausedDuration
    );
    event PauseLifted(
        address indexed by,
        uint64 indexed endedAt,
        uint256 elapsed,
        uint256 cumulativePausedDuration,
        bool forced
    );

    constructor(
        address admin,
        address usdc_,
        address presaleVault_,
        address claimModule_,
        uint64 presaleStartTimestamp_,
        uint64 presaleEndTimestamp_
    ) {
        if (
            admin == address(0) || usdc_ == address(0) || presaleVault_ == address(0)
                || claimModule_ == address(0)
        ) {
            revert InvalidAddress();
        }

        if (presaleEndTimestamp_ <= presaleStartTimestamp_) {
            revert InvalidTimestamp();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        usdc = IERC20(usdc_);
        presaleVault = IPresaleVault(presaleVault_);
        claimModule = IClaimModule(claimModule_);

        PRESALE_START_TIMESTAMP = presaleStartTimestamp_;
        PRESALE_END_TIMESTAMP = presaleEndTimestamp_;

        _initializePhases();
    }

    /// @notice Buy AIC allocation using USDC.
    /// @dev Purchase overflow policy: revert on phase/hard-cap overflow; no partial fill or refund path.
    ///      Rounding policy: token amount rounds down for safety.
    function buyTokens(uint256 usdcAmount) external nonReentrant returns (uint256 aicAmount) {
        if (usdcAmount == 0) revert ZeroAmount();
        if (presaleFinalized) revert PresaleAlreadyFinalized();
        if (block.timestamp < PRESALE_START_TIMESTAMP) revert PresaleNotStarted();
        if (block.timestamp >= PRESALE_END_TIMESTAMP) revert PresaleEnded();
        if (_pauseActive) revert PresaleNotActive();

        uint8 phaseIdx = getActivePhase();
        if (phaseIdx == type(uint8).max) revert NoActivePhase();

        Phase storage phase = _phases[phaseIdx];

        if (totalRaisedUSDC + usdcAmount > HARD_CAP) revert HardCapExceeded();

        aicAmount = (usdcAmount * 1e18) / phase.pricePerTokenUSDC6;
        if (phase.soldTokens + aicAmount > phase.tokenCap) revert PhaseCapExceeded();

        uint8 previousPhase = phaseIdx;

        contributions[msg.sender] += usdcAmount;
        tokenAllocations[msg.sender] += aicAmount;
        totalRaisedUSDC += usdcAmount;
        totalAllocatedTokens += aicAmount;
        phase.soldTokens += aicAmount;

        if (totalAllocatedTokens > PRESALE_TOKEN_CAP) revert AllocationCapExceeded();

        usdc.safeTransferFrom(msg.sender, address(presaleVault), usdcAmount);
        presaleVault.routeDeposit(usdcAmount, totalRaisedUSDC);
        claimModule.recordAllocation(msg.sender, aicAmount);

        emit TokensPurchased(msg.sender, usdcAmount, aicAmount, previousPhase, totalRaisedUSDC);

        uint8 nextPhase = getActivePhase();
        if (nextPhase != type(uint8).max && nextPhase != previousPhase) {
            emit PhaseAdvanced(previousPhase, nextPhase, _phases[nextPhase].pricePerTokenUSDC6);
        }
    }

    /// @notice Permissionless finalization when objective end conditions are met.
    function finalizePresale() external nonReentrant {
        if (presaleFinalized) revert PresaleAlreadyFinalized();
        if (!isFinalizable()) revert PresaleNotFinalizable();

        presaleFinalized = true;

        if (_pauseActive) {
            _liftPause(true);
        }

        uint64 finalizedAt = uint64(block.timestamp);
        presaleVault.onPresaleFinalized(finalizedAt);

        emit PresaleFinalized(finalizedAt, totalRaisedUSDC, totalAllocatedTokens);
    }

    /// @notice Pause buys only, subject to bounded pause budgets.
    function pause() external onlyRole(PAUSER_ROLE) {
        if (presaleFinalized) revert PresaleAlreadyFinalized();
        if (_pauseActive) revert PauseAlreadyActive();
        if (block.timestamp >= PRESALE_END_TIMESTAMP) revert PresaleEnded();
        if (cumulativePausedDuration >= MAX_CUMULATIVE_PAUSE) revert PauseBudgetExceeded();

        _pauseActive = true;
        currentPauseStartedAt = uint64(block.timestamp);

        emit PauseActivated(msg.sender, currentPauseStartedAt, cumulativePausedDuration);
    }

    /// @notice Role-protected unpause.
    function unpause() external onlyRole(PAUSER_ROLE) {
        if (!_pauseActive) revert PauseNotActive();
        _liftPause(false);
    }

    /// @notice Permissionless unpause when single pause exceeds allowed window.
    function forceUnpause() external {
        if (!_pauseActive) revert PauseNotActive();
        if (block.timestamp < currentPauseStartedAt + MAX_SINGLE_PAUSE) {
            revert ForceUnpauseUnavailable();
        }

        _liftPause(true);
    }

    /// @notice Current presale lifecycle state.
    function lifecycle() public view returns (Lifecycle) {
        if (presaleFinalized) return Lifecycle.Finalized;
        if (block.timestamp < PRESALE_START_TIMESTAMP) return Lifecycle.Pending;
        if (_pauseActive) return Lifecycle.Paused;
        if (isFinalizable()) return Lifecycle.Ended;
        return Lifecycle.Active;
    }

    /// @notice Whether objective finalization conditions are met.
    function isFinalizable() public view returns (bool) {
        return totalRaisedUSDC >= HARD_CAP || block.timestamp >= PRESALE_END_TIMESTAMP;
    }

    /// @notice Whether buys are currently paused.
    function pauseActive() external view returns (bool) {
        return _pauseActive;
    }

    /// @notice Returns currently active phase index, or `type(uint8).max` if no active phase.
    function getActivePhase() public view returns (uint8) {
        if (presaleFinalized) {
            return type(uint8).max;
        }
        if (block.timestamp < PRESALE_START_TIMESTAMP || block.timestamp >= PRESALE_END_TIMESTAMP) {
            return type(uint8).max;
        }
        if (totalRaisedUSDC >= HARD_CAP) {
            return type(uint8).max;
        }

        for (uint8 i = 0; i < PHASE_COUNT; ++i) {
            if (totalRaisedUSDC < _phases[i].cumulativeRaiseCapUSDC) {
                return i;
            }
        }

        return type(uint8).max;
    }

    /// @notice Returns full phase information and remaining capacities.
    function getPhaseInfo(uint8 phaseIndex)
        external
        view
        returns (
            uint256 cumulativeRaiseCapUSDC,
            uint256 pricePerTokenUSDC6,
            uint256 tokenCap,
            uint256 soldTokens,
            uint256 remainingTokenCapacity
        )
    {
        if (phaseIndex >= PHASE_COUNT) revert InvalidConfiguration();

        Phase memory phase = _phases[phaseIndex];

        cumulativeRaiseCapUSDC = phase.cumulativeRaiseCapUSDC;
        pricePerTokenUSDC6 = phase.pricePerTokenUSDC6;
        tokenCap = phase.tokenCap;
        soldTokens = phase.soldTokens;
        remainingTokenCapacity = tokenCap - soldTokens;
    }

    /// @notice Remaining global hard-cap capacity.
    function remainingHardCapUSDC() external view returns (uint256) {
        if (totalRaisedUSDC >= HARD_CAP) {
            return 0;
        }

        return HARD_CAP - totalRaisedUSDC;
    }

    /// @inheritdoc IWebAI3PresaleState
    function liquidityProvisioned() public view returns (bool) {
        return presaleVault.liquidityProvisioned();
    }

    function _liftPause(bool forced) internal {
        uint256 elapsed = block.timestamp - currentPauseStartedAt;

        uint256 remainingBudget;
        if (cumulativePausedDuration >= MAX_CUMULATIVE_PAUSE) {
            remainingBudget = 0;
        } else {
            remainingBudget = MAX_CUMULATIVE_PAUSE - cumulativePausedDuration;
        }

        uint256 countedElapsed = elapsed;
        if (countedElapsed > remainingBudget) {
            countedElapsed = remainingBudget;
        }

        cumulativePausedDuration += countedElapsed;
        _pauseActive = false;
        currentPauseStartedAt = 0;

        emit PauseLifted(
            msg.sender, uint64(block.timestamp), elapsed, cumulativePausedDuration, forced
        );
    }

    function _initializePhases() internal {
        _phases[0] = Phase({
            cumulativeRaiseCapUSDC: 500_000e6,
            pricePerTokenUSDC6: 10_000,
            tokenCap: 50_000_000 ether,
            soldTokens: 0
        });
        _phases[1] = Phase({
            cumulativeRaiseCapUSDC: 1_000_000e6,
            pricePerTokenUSDC6: 13_000,
            tokenCap: 38_500_000 ether,
            soldTokens: 0
        });
        _phases[2] = Phase({
            cumulativeRaiseCapUSDC: 2_000_000e6,
            pricePerTokenUSDC6: 20_000,
            tokenCap: 50_000_000 ether,
            soldTokens: 0
        });
        _phases[3] = Phase({
            cumulativeRaiseCapUSDC: 3_500_000e6,
            pricePerTokenUSDC6: 28_000,
            tokenCap: 53_600_000 ether,
            soldTokens: 0
        });
        _phases[4] = Phase({
            cumulativeRaiseCapUSDC: 5_000_000e6,
            pricePerTokenUSDC6: 38_000,
            tokenCap: 39_500_000 ether,
            soldTokens: 0
        });
        _phases[5] = Phase({
            cumulativeRaiseCapUSDC: 6_000_000e6,
            pricePerTokenUSDC6: 53_000,
            tokenCap: 18_900_000 ether,
            soldTokens: 0
        });
        _phases[6] = Phase({
            cumulativeRaiseCapUSDC: 7_000_000e6,
            pricePerTokenUSDC6: 70_000,
            tokenCap: 249_500_000 ether,
            soldTokens: 0
        });

        uint256 aggregateTokenCap;
        for (uint8 i = 0; i < PHASE_COUNT; ++i) {
            aggregateTokenCap += _phases[i].tokenCap;
        }

        if (aggregateTokenCap != PRESALE_TOKEN_CAP) {
            revert InvalidConfiguration();
        }
    }
}
