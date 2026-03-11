// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { ILiquidityVault } from "./interfaces/ILiquidityVault.sol";
import { IDevRunwayVault } from "./interfaces/IDevRunwayVault.sol";
import { ITeamStreamVault } from "./interfaces/ITeamStreamVault.sol";
import { IMarketingVault } from "./interfaces/IMarketingVault.sol";
import { IPresaleVault } from "./interfaces/IPresaleVault.sol";

/// @title PresaleVault
/// @notice Deterministic router for presale USDC funds.
/// @dev Deployment assumption: this contract is configured once with a presale address via `setPresale`.
contract PresaleVault is AccessControl, ReentrancyGuard, IPresaleVault {
    using SafeERC20 for IERC20;

    uint256 internal constant LIQUIDITY_BPS = 7000;
    uint256 internal constant DEV_BPS = 1500;
    uint256 internal constant TEAM_BPS = 1000;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    IERC20 public immutable usdc;
    ILiquidityVault public immutable liquidityVault;
    IDevRunwayVault public immutable devRunwayVault;
    ITeamStreamVault public immutable teamStreamVault;
    IMarketingVault public immutable marketingVault;

    address public presale;
    uint256 public totalRoutedUSDC;

    event PresaleSet(address indexed presale);
    event DepositRouted(
        uint256 amount,
        uint256 liquidityAmount,
        uint256 devAmount,
        uint256 teamAmount,
        uint256 marketingAmount,
        uint256 totalRaisedAfter
    );
    event PresaleFinalizedNotified(uint64 indexed finalizedAt);

    modifier onlyPresale() {
        if (msg.sender != presale) revert NotAuthorized();
        _;
    }

    constructor(
        address admin,
        address usdc_,
        address liquidityVault_,
        address devRunwayVault_,
        address teamStreamVault_,
        address marketingVault_
    ) {
        if (
            admin == address(0) || usdc_ == address(0) || liquidityVault_ == address(0)
                || devRunwayVault_ == address(0) || teamStreamVault_ == address(0)
                || marketingVault_ == address(0)
        ) {
            revert InvalidAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        liquidityVault = ILiquidityVault(liquidityVault_);
        devRunwayVault = IDevRunwayVault(devRunwayVault_);
        teamStreamVault = ITeamStreamVault(teamStreamVault_);
        marketingVault = IMarketingVault(marketingVault_);
    }

    /// @notice One-time presale binding.
    function setPresale(address presale_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (presale_ == address(0)) revert InvalidAddress();
        if (presale != address(0)) revert AlreadyConfigured();

        presale = presale_;
        emit PresaleSet(presale_);
    }

    /// @inheritdoc IPresaleVault
    function routeDeposit(uint256 usdcAmount, uint256 totalRaisedAfter)
        external
        onlyPresale
        nonReentrant
    {
        if (usdcAmount == 0) revert ZeroAmount();

        uint256 liquidityAmount = (usdcAmount * LIQUIDITY_BPS) / BPS_DENOMINATOR;
        uint256 devAmount = (usdcAmount * DEV_BPS) / BPS_DENOMINATOR;
        uint256 teamAmount = (usdcAmount * TEAM_BPS) / BPS_DENOMINATOR;
        uint256 marketingAmount = usdcAmount - liquidityAmount - devAmount - teamAmount;

        totalRoutedUSDC += usdcAmount;

        usdc.safeTransfer(address(liquidityVault), liquidityAmount);
        liquidityVault.onDeposit(liquidityAmount);

        usdc.safeTransfer(address(devRunwayVault), devAmount);
        devRunwayVault.onDeposit(devAmount, totalRaisedAfter);

        usdc.safeTransfer(address(teamStreamVault), teamAmount);
        teamStreamVault.onDeposit(teamAmount);

        usdc.safeTransfer(address(marketingVault), marketingAmount);
        marketingVault.onDeposit(marketingAmount);

        emit DepositRouted(
            usdcAmount, liquidityAmount, devAmount, teamAmount, marketingAmount, totalRaisedAfter
        );
    }

    /// @inheritdoc IPresaleVault
    function onPresaleFinalized(uint64 finalizedAt) external onlyPresale {
        liquidityVault.onPresaleFinalized(finalizedAt);
        marketingVault.onPresaleFinalized(finalizedAt);

        emit PresaleFinalizedNotified(finalizedAt);
    }

    /// @inheritdoc IPresaleVault
    function liquidityProvisioned() external view returns (bool) {
        return liquidityVault.liquidityProvisioned();
    }
}
