// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { IMarketingVault } from "./interfaces/IMarketingVault.sol";

/// @title MarketingVault
/// @notice Marketing treasury vault with strict pre-finalization lock.
/// @dev Policy: no marketing spend is possible before presale finalization.
contract MarketingVault is AccessControl, ReentrancyGuard, IMarketingVault {
    using SafeERC20 for IERC20;

    bytes32 public constant MARKETING_OPERATOR_ROLE = keccak256("MARKETING_OPERATOR_ROLE");

    IERC20 public immutable usdc;
    address public immutable beneficiary;
    uint256 public immutable withdrawalDelay;

    address public presaleVault;

    bool public presaleFinalized;
    uint64 public finalizedAt;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    uint256 public pendingWithdrawalAmount;
    uint64 public pendingWithdrawalReadyAt;

    event PresaleVaultSet(address indexed vault);
    event MarketingDeposited(uint256 amount, uint256 totalDeposited);
    event MarketingFinalizationRegistered(uint64 finalizedAt);
    event MarketingWithdrawalQueued(
        address indexed caller, uint256 amount, uint64 readyAt, address indexed beneficiary
    );
    event MarketingWithdrawalExecuted(
        address indexed caller, uint256 amount, address indexed beneficiary
    );
    event MarketingWithdrawalCancelled(address indexed caller, uint256 previousAmount);

    modifier onlyPresaleVault() {
        if (msg.sender != presaleVault) revert NotAuthorized();
        _;
    }

    constructor(address admin, address usdc_, address beneficiary_, uint256 withdrawalDelay_) {
        if (
            admin == address(0) || usdc_ == address(0) || beneficiary_ == address(0)
                || withdrawalDelay_ == 0
        ) {
            revert InvalidConfiguration();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        beneficiary = beneficiary_;
        withdrawalDelay = withdrawalDelay_;
    }

    /// @notice One-time PresaleVault binding.
    function setPresaleVault(address presaleVault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (presaleVault_ == address(0)) revert InvalidAddress();
        if (presaleVault != address(0)) revert AlreadyConfigured();

        presaleVault = presaleVault_;
        emit PresaleVaultSet(presaleVault_);
    }

    /// @inheritdoc IMarketingVault
    function onDeposit(uint256 amount) external onlyPresaleVault {
        if (amount == 0) revert ZeroAmount();

        totalDeposited += amount;
        emit MarketingDeposited(amount, totalDeposited);
    }

    /// @inheritdoc IMarketingVault
    function onPresaleFinalized(uint64 finalizedAt_) external onlyPresaleVault {
        if (presaleFinalized) revert PresaleAlreadyFinalized();

        presaleFinalized = true;
        finalizedAt = finalizedAt_;

        emit MarketingFinalizationRegistered(finalizedAt_);
    }

    /// @notice Queue a timelocked post-finalization withdrawal.
    function queueWithdrawal(uint256 amount) external onlyRole(MARKETING_OPERATOR_ROLE) {
        if (!presaleFinalized) revert MarketingLocked();
        if (amount == 0) revert ZeroAmount();
        if (pendingWithdrawalAmount != 0) revert InvalidConfiguration();
        if (amount > availableBalance()) revert WithdrawalExceedsLimit();

        pendingWithdrawalAmount = amount;
        pendingWithdrawalReadyAt = uint64(block.timestamp + withdrawalDelay);

        emit MarketingWithdrawalQueued(msg.sender, amount, pendingWithdrawalReadyAt, beneficiary);
    }

    /// @notice Cancel queued withdrawal (role-protected safety valve).
    function cancelQueuedWithdrawal() external onlyRole(MARKETING_OPERATOR_ROLE) {
        uint256 queued = pendingWithdrawalAmount;
        if (queued == 0) revert NoQueuedWithdrawal();

        pendingWithdrawalAmount = 0;
        pendingWithdrawalReadyAt = 0;

        emit MarketingWithdrawalCancelled(msg.sender, queued);
    }

    /// @notice Execute a queued timelocked withdrawal.
    function executeWithdrawal() external onlyRole(MARKETING_OPERATOR_ROLE) nonReentrant {
        uint256 amount = pendingWithdrawalAmount;
        if (amount == 0) revert NoQueuedWithdrawal();
        if (block.timestamp < pendingWithdrawalReadyAt) revert TimelockNotReady();
        if (amount > availableBalance()) revert WithdrawalExceedsLimit();

        pendingWithdrawalAmount = 0;
        pendingWithdrawalReadyAt = 0;

        totalWithdrawn += amount;
        usdc.safeTransfer(beneficiary, amount);

        emit MarketingWithdrawalExecuted(msg.sender, amount, beneficiary);
    }

    /// @notice Available post-finalization marketing balance.
    function availableBalance() public view returns (uint256) {
        return totalDeposited - totalWithdrawn;
    }
}
