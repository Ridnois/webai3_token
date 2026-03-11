// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { ILiquidityExecutor } from "./interfaces/ILiquidityExecutor.sol";
import { ILiquidityVault } from "./interfaces/ILiquidityVault.sol";

/// @title LiquidityVault
/// @notice Holds liquidity funds and enforces primary + fallback provisioning paths.
/// @dev Deployment assumption: `setPresaleVault` is called once by admin after PresaleVault deployment.
contract LiquidityVault is AccessControl, ReentrancyGuard, ILiquidityVault {
    using SafeERC20 for IERC20;

    bytes32 public constant LIQUIDITY_EXECUTOR_ROLE = keccak256("LIQUIDITY_EXECUTOR_ROLE");

    uint256 public constant MAX_LIQUIDITY_DELAY = 7 days;

    IERC20 public immutable usdc;
    ILiquidityExecutor public immutable liquidityExecutor;
    bytes32 public immutable LIQUIDITY_PLAN_HASH;

    address public presaleVault;

    bool public presaleFinalized;
    bool public override liquidityProvisioned;

    uint64 public finalizedAt;

    uint256 public totalDeposited;
    uint256 public totalProvisionedUSDC;
    uint256 public lastLpTokensMinted;

    event PresaleVaultSet(address indexed vault);
    event LiquidityDeposited(uint256 amount, uint256 totalDeposited);
    event LiquidityFinalizationRegistered(uint64 finalizedAt);
    event LiquidityProvisionedEvent(
        address indexed caller, uint256 usdcAmount, uint256 lpTokensMinted, bool viaFallback
    );

    modifier onlyPresaleVault() {
        if (msg.sender != presaleVault) revert NotAuthorized();
        _;
    }

    constructor(
        address admin,
        address usdc_,
        address liquidityExecutor_,
        bytes32 liquidityPlanHash_
    ) {
        if (admin == address(0) || usdc_ == address(0) || liquidityExecutor_ == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        liquidityExecutor = ILiquidityExecutor(liquidityExecutor_);
        LIQUIDITY_PLAN_HASH = liquidityPlanHash_;
    }

    /// @notice One-time PresaleVault binding.
    function setPresaleVault(address presaleVault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (presaleVault_ == address(0)) revert InvalidAddress();
        if (presaleVault != address(0)) revert AlreadyConfigured();

        presaleVault = presaleVault_;
        emit PresaleVaultSet(presaleVault_);
    }

    /// @inheritdoc ILiquidityVault
    function onDeposit(uint256 amount) external onlyPresaleVault {
        if (amount == 0) revert ZeroAmount();

        totalDeposited += amount;
        emit LiquidityDeposited(amount, totalDeposited);
    }

    /// @inheritdoc ILiquidityVault
    function onPresaleFinalized(uint64 finalizedAt_) external onlyPresaleVault {
        if (presaleFinalized) revert PresaleAlreadyFinalized();

        presaleFinalized = true;
        finalizedAt = finalizedAt_;

        emit LiquidityFinalizationRegistered(finalizedAt_);
    }

    /// @notice Primary liquidity path callable by assigned role during the executor window.
    function provideLiquidity() external onlyRole(LIQUIDITY_EXECUTOR_ROLE) nonReentrant {
        if (!presaleFinalized) revert PresaleNotFinalized();
        if (liquidityProvisioned) revert LiquidityAlreadyProvisioned();
        if (block.timestamp > finalizedAt + MAX_LIQUIDITY_DELAY) revert LiquidityWindowExpired();

        _executeProvision(false);
    }

    /// @notice Permissionless fallback liquidity path after the executor window expires.
    function provideLiquidityFallback() external nonReentrant {
        if (!presaleFinalized) revert PresaleNotFinalized();
        if (liquidityProvisioned) revert LiquidityAlreadyProvisioned();
        if (block.timestamp <= finalizedAt + MAX_LIQUIDITY_DELAY) {
            revert LiquidityFallbackNotAvailable();
        }

        _executeProvision(true);
    }

    /// @notice Returns true when fallback provisioning is available.
    function fallbackAvailable() external view returns (bool) {
        return presaleFinalized && !liquidityProvisioned
            && block.timestamp > finalizedAt + MAX_LIQUIDITY_DELAY;
    }

    function _executeProvision(bool viaFallback) internal {
        uint256 usdcAmount = usdc.balanceOf(address(this));
        if (usdcAmount == 0) revert LiquidityExecutionFailed();

        // Executes against a pre-committed plan hash to avoid caller-controlled economics.
        usdc.forceApprove(address(liquidityExecutor), 0);
        usdc.forceApprove(address(liquidityExecutor), usdcAmount);

        uint256 lpTokensMinted = liquidityExecutor.executeLiquidityProvision(
            address(usdc), usdcAmount, LIQUIDITY_PLAN_HASH
        );

        usdc.forceApprove(address(liquidityExecutor), 0);

        if (lpTokensMinted == 0) revert LiquidityExecutionFailed();

        liquidityProvisioned = true;
        totalProvisionedUSDC += usdcAmount;
        lastLpTokensMinted = lpTokensMinted;

        emit LiquidityProvisionedEvent(msg.sender, usdcAmount, lpTokensMinted, viaFallback);
    }
}
