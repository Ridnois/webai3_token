// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { IDevRunwayVault } from "./interfaces/IDevRunwayVault.sol";

/// @title DevRunwayVault
/// @notice Development treasury with dual gating (milestones + linear stream).
/// @dev Amounts are USDC 6-decimal units.
contract DevRunwayVault is AccessControl, ReentrancyGuard, IDevRunwayVault {
    using SafeERC20 for IERC20;

    bytes32 public constant DEV_OPERATOR_ROLE = keccak256("DEV_OPERATOR_ROLE");

    uint256 public constant DEV_STREAM_DURATION = 180 days;
    uint256 public constant DEV_MAX_BUDGET = 1_050_000e6; // 15% of 7M hard cap.

    IERC20 public immutable usdc;
    address public immutable beneficiary;
    uint64 public immutable presaleStartTimestamp;

    address public presaleVault;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalRaisedObserved;
    uint256 public lastMilestoneUnlocked;

    event PresaleVaultSet(address indexed vault);
    event DevDeposited(uint256 amount, uint256 totalDeposited, uint256 totalRaisedObserved);
    event MilestoneUnlockUpdated(uint256 indexed totalRaised, uint256 milestoneUnlockedAmount);
    event DevWithdrawn(address indexed caller, uint256 amount, address indexed beneficiary);

    modifier onlyPresaleVault() {
        if (msg.sender != presaleVault) revert NotAuthorized();
        _;
    }

    constructor(address admin, address usdc_, address beneficiary_, uint64 presaleStartTimestamp_) {
        if (admin == address(0) || usdc_ == address(0) || beneficiary_ == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        beneficiary = beneficiary_;
        presaleStartTimestamp = presaleStartTimestamp_;
    }

    /// @notice One-time PresaleVault binding.
    function setPresaleVault(address presaleVault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (presaleVault_ == address(0)) revert InvalidAddress();
        if (presaleVault != address(0)) revert AlreadyConfigured();

        presaleVault = presaleVault_;
        emit PresaleVaultSet(presaleVault_);
    }

    /// @inheritdoc IDevRunwayVault
    function onDeposit(uint256 amount, uint256 totalRaisedAfter) external onlyPresaleVault {
        if (amount == 0) revert ZeroAmount();

        totalDeposited += amount;
        totalRaisedObserved = totalRaisedAfter;

        uint256 unlocked = milestoneUnlocked(totalRaisedAfter);
        if (unlocked != lastMilestoneUnlocked) {
            lastMilestoneUnlocked = unlocked;
            emit MilestoneUnlockUpdated(totalRaisedAfter, unlocked);
        }

        emit DevDeposited(amount, totalDeposited, totalRaisedAfter);
    }

    /// @notice Withdraw available dev runway to the configured beneficiary.
    function withdraw(uint256 amount) external onlyRole(DEV_OPERATOR_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 available = withdrawableDev();
        if (amount > available) revert WithdrawalExceedsLimit();

        totalWithdrawn += amount;
        usdc.safeTransfer(beneficiary, amount);

        emit DevWithdrawn(msg.sender, amount, beneficiary);
    }

    /// @notice Maximum unlocked amount from milestone progression.
    function milestoneUnlocked(uint256 totalRaisedUSDC) public pure returns (uint256) {
        if (totalRaisedUSDC >= 7_000_000e6) return 1_050_000e6;
        if (totalRaisedUSDC >= 6_000_000e6) return 850_000e6;
        if (totalRaisedUSDC >= 5_000_000e6) return 650_000e6;
        if (totalRaisedUSDC >= 3_500_000e6) return 420_000e6;
        if (totalRaisedUSDC >= 2_000_000e6) return 250_000e6;
        if (totalRaisedUSDC >= 1_000_000e6) return 120_000e6;
        if (totalRaisedUSDC >= 500_000e6) return 50_000e6;
        return 0;
    }

    /// @notice Linearly streamed dev budget based on time since presale start.
    function streamedDevAmount() public view returns (uint256) {
        if (block.timestamp <= presaleStartTimestamp) {
            return 0;
        }

        uint256 elapsed = block.timestamp - presaleStartTimestamp;
        if (elapsed >= DEV_STREAM_DURATION) {
            return DEV_MAX_BUDGET;
        }

        return (DEV_MAX_BUDGET * elapsed) / DEV_STREAM_DURATION;
    }

    /// @notice Current withdrawable amount under dual-gated constraints.
    function withdrawableDev() public view returns (uint256) {
        uint256 milestoneCap = milestoneUnlocked(totalRaisedObserved);
        uint256 streamCap = streamedDevAmount();

        uint256 maxAllowed = milestoneCap < streamCap ? milestoneCap : streamCap;
        if (maxAllowed > totalDeposited) {
            maxAllowed = totalDeposited;
        }

        if (maxAllowed <= totalWithdrawn) {
            return 0;
        }

        return maxAllowed - totalWithdrawn;
    }
}
