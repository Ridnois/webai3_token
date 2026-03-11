// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { IClaimModule } from "./interfaces/IClaimModule.sol";
import { IWebAI3PresaleState } from "./interfaces/IWebAI3PresaleState.sol";

/// @title ClaimModule
/// @notice Buyer allocation and vesting claims module for AIC token distribution.
/// @dev Deployment assumption: allocate presale claim tokens to this contract before enabling claims.
contract ClaimModule is AccessControl, ReentrancyGuard, IClaimModule {
    using SafeERC20 for IERC20;

    uint256 public constant PRESALE_TOKEN_CAP = 500_000_000 ether;

    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant TGE_BPS = 3_000;
    uint256 internal constant TGE_PLUS_3M_BPS = 6_500;
    uint256 internal constant FULLY_VESTED_BPS = 10_000;

    IERC20 public immutable aicToken;
    uint64 public immutable tgeTimestamp;
    uint64 public immutable tgePlus3Months;
    uint64 public immutable tgePlus6Months;

    IWebAI3PresaleState public presale;

    bool public claimsEnabled;

    uint256 public totalRecordedAllocations;

    mapping(address => uint256) public totalAllocation;
    mapping(address => uint256) public totalClaimed;

    event PresaleSet(address indexed presale);
    event AllocationRecorded(address indexed buyer, uint256 amount, uint256 totalBuyerAllocation);
    event ClaimsEnabled(uint64 indexed enabledAt);
    event TokensClaimed(address indexed claimer, uint256 amount, uint256 totalClaimed);

    modifier onlyPresale() {
        if (msg.sender != address(presale)) revert NotAuthorized();
        _;
    }

    constructor(address admin, address aicToken_, uint64 tgeTimestamp_) {
        if (admin == address(0) || aicToken_ == address(0) || tgeTimestamp_ == 0) {
            revert InvalidConfiguration();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        aicToken = IERC20(aicToken_);
        tgeTimestamp = tgeTimestamp_;
        tgePlus3Months = tgeTimestamp_ + 90 days;
        tgePlus6Months = tgeTimestamp_ + 180 days;
    }

    /// @notice One-time presale binding.
    function setPresale(address presale_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (presale_ == address(0)) revert InvalidAddress();
        if (address(presale) != address(0)) revert AlreadyConfigured();

        presale = IWebAI3PresaleState(presale_);
        emit PresaleSet(presale_);
    }

    /// @inheritdoc IClaimModule
    function recordAllocation(address buyer, uint256 amount) external onlyPresale {
        if (buyer == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 newTotal = totalRecordedAllocations + amount;
        if (newTotal > PRESALE_TOKEN_CAP) revert AllocationCapExceeded();

        totalRecordedAllocations = newTotal;
        totalAllocation[buyer] += amount;

        emit AllocationRecorded(buyer, amount, totalAllocation[buyer]);
    }

    /// @notice Permissionless claims activation after finalization and liquidity provisioning.
    function enableClaims() external {
        if (claimsEnabled) revert AlreadyConfigured();
        if (address(presale) == address(0)) revert InvalidConfiguration();
        if (!presale.presaleFinalized()) revert PresaleNotFinalized();
        if (!presale.liquidityProvisioned()) revert LiquidityNotProvisioned();

        claimsEnabled = true;

        emit ClaimsEnabled(uint64(block.timestamp));
    }

    /// @notice Claim currently vested and unclaimed AIC.
    function claim() external nonReentrant returns (uint256 amount) {
        if (!claimsEnabled) revert ClaimsNotEnabled();
        if (!presale.presaleFinalized()) revert PresaleNotFinalized();
        if (!presale.liquidityProvisioned()) revert LiquidityNotProvisioned();

        amount = claimableAmount(msg.sender);
        if (amount == 0) revert NothingClaimable();

        totalClaimed[msg.sender] += amount;
        aicToken.safeTransfer(msg.sender, amount);

        emit TokensClaimed(msg.sender, amount, totalClaimed[msg.sender]);
    }

    /// @notice Amount a user can claim at current timestamp.
    function claimableAmount(address user) public view returns (uint256) {
        uint256 allocation = totalAllocation[user];
        if (allocation == 0) {
            return 0;
        }

        uint256 vested = (allocation * vestedBps()) / BPS_DENOMINATOR;
        uint256 alreadyClaimed = totalClaimed[user];

        if (vested <= alreadyClaimed) {
            return 0;
        }

        return vested - alreadyClaimed;
    }

    /// @notice Vesting BPS at current timestamp (30% / 65% / 100%).
    function vestedBps() public view returns (uint256) {
        if (block.timestamp < tgeTimestamp) {
            return 0;
        }
        if (block.timestamp < tgePlus3Months) {
            return TGE_BPS;
        }
        if (block.timestamp < tgePlus6Months) {
            return TGE_PLUS_3M_BPS;
        }
        return FULLY_VESTED_BPS;
    }

    /// @notice Returns vesting checkpoints.
    function vestingCheckpoints()
        external
        view
        returns (uint64 tge, uint64 plus3Months, uint64 plus6Months)
    {
        return (tgeTimestamp, tgePlus3Months, tgePlus6Months);
    }
}
