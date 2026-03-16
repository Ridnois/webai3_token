// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { IDevRunwayVault } from "./interfaces/IDevRunwayVault.sol";

/// @title DevRunwayVault
/// @notice Development treasury with stream-only gating.
/// @dev Funds unlock linearly from presaleStartTimestamp over DEV_STREAM_DURATION,
///      capped by the amount actually deposited. No milestone gate — the team must
///      be able to fund R&D from day one regardless of presale performance.
///      Amounts are USDC 6-decimal units.
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

    event PresaleVaultSet(address indexed vault);
    event DevDeposited(uint256 amount, uint256 totalDeposited);
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
    function onDeposit(uint256 amount, uint256 /* totalRaisedAfter */) external onlyPresaleVault {
        if (amount == 0) revert ZeroAmount();

        totalDeposited += amount;
        emit DevDeposited(amount, totalDeposited);
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

    /// @notice Current withdrawable amount: stream progress capped to deposited funds, minus already withdrawn.
    function withdrawableDev() public view returns (uint256) {
        uint256 streamCap = streamedDevAmount();
        uint256 maxAllowed = streamCap < totalDeposited ? streamCap : totalDeposited;

        if (maxAllowed <= totalWithdrawn) {
            return 0;
        }

        return maxAllowed - totalWithdrawn;
    }
}
