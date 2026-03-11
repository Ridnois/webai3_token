// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WebAI3Presale } from "../../src/WebAI3Presale.sol";
import { PresaleVault } from "../../src/presale/PresaleVault.sol";
import { LiquidityVault } from "../../src/presale/LiquidityVault.sol";
import { DevRunwayVault } from "../../src/presale/DevRunwayVault.sol";
import { TeamStreamVault } from "../../src/presale/TeamStreamVault.sol";
import { MarketingVault } from "../../src/presale/MarketingVault.sol";
import { ClaimModule } from "../../src/presale/ClaimModule.sol";
import { ILiquidityExecutor } from "../../src/presale/interfaces/ILiquidityExecutor.sol";

contract MockUSDC6 is ERC20 {
    constructor() ERC20("USD Coin", "USDC") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAIC is ERC20 {
    constructor() ERC20("WebAI3 Token", "AIC") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockLiquidityExecutor is ILiquidityExecutor {
    function executeLiquidityProvision(address usdc, uint256 usdcAmount, bytes32)
        external
        returns (uint256 lpTokensMinted)
    {
        IERC20(usdc).transferFrom(msg.sender, address(this), usdcAmount);
        return usdcAmount;
    }
}

abstract contract PresaleSystemTestBase is Test {
    MockUSDC6 internal usdc;
    MockAIC internal aic;
    MockLiquidityExecutor internal liquidityExecutor;

    WebAI3Presale internal presale;
    PresaleVault internal presaleVault;
    LiquidityVault internal liquidityVault;
    DevRunwayVault internal devRunwayVault;
    TeamStreamVault internal teamStreamVault;
    MarketingVault internal marketingVault;
    ClaimModule internal claimModule;

    address internal admin = address(this);
    address internal pauser = makeAddr("pauser");
    address internal liquidityOperator = makeAddr("liquidityOperator");
    address internal devOperator = makeAddr("devOperator");
    address internal teamOperator = makeAddr("teamOperator");
    address internal marketingOperator = makeAddr("marketingOperator");

    address internal devBeneficiary = makeAddr("devBeneficiary");
    address internal teamBeneficiary = makeAddr("teamBeneficiary");
    address internal marketingBeneficiary = makeAddr("marketingBeneficiary");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    uint64 internal presaleStart;
    uint64 internal presaleEnd;
    uint64 internal tge;

    bytes32 internal constant PLAN_HASH = keccak256("WEBAI3_LIQUIDITY_PLAN_V1");

    function setUp() public virtual {
        presaleStart = uint64(block.timestamp);
        presaleEnd = presaleStart + 120 days;
        tge = presaleEnd + 1 days;

        usdc = new MockUSDC6();
        aic = new MockAIC();
        liquidityExecutor = new MockLiquidityExecutor();

        liquidityVault =
            new LiquidityVault(admin, address(usdc), address(liquidityExecutor), PLAN_HASH);
        devRunwayVault = new DevRunwayVault(admin, address(usdc), devBeneficiary, presaleStart);
        teamStreamVault =
            new TeamStreamVault(admin, address(usdc), teamBeneficiary, presaleStart, 365 days);
        marketingVault = new MarketingVault(admin, address(usdc), marketingBeneficiary, 2 days);

        presaleVault = new PresaleVault(
            admin,
            address(usdc),
            address(liquidityVault),
            address(devRunwayVault),
            address(teamStreamVault),
            address(marketingVault)
        );

        claimModule = new ClaimModule(admin, address(aic), tge);

        presale = new WebAI3Presale(
            admin,
            address(usdc),
            address(presaleVault),
            address(claimModule),
            presaleStart,
            presaleEnd
        );

        liquidityVault.setPresaleVault(address(presaleVault));
        devRunwayVault.setPresaleVault(address(presaleVault));
        teamStreamVault.setPresaleVault(address(presaleVault));
        marketingVault.setPresaleVault(address(presaleVault));

        presaleVault.setPresale(address(presale));
        claimModule.setPresale(address(presale));

        presale.grantRole(presale.PAUSER_ROLE(), pauser);
        liquidityVault.grantRole(liquidityVault.LIQUIDITY_EXECUTOR_ROLE(), liquidityOperator);
        devRunwayVault.grantRole(devRunwayVault.DEV_OPERATOR_ROLE(), devOperator);
        teamStreamVault.grantRole(teamStreamVault.TEAM_OPERATOR_ROLE(), teamOperator);
        marketingVault.grantRole(marketingVault.MARKETING_OPERATOR_ROLE(), marketingOperator);

        aic.mint(address(claimModule), 500_000_000 ether);
    }

    function _fundAndApprove(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(presale), amount);
    }

    function _buy(address user, uint256 amount) internal returns (uint256) {
        _fundAndApprove(user, amount);
        vm.prank(user);
        return presale.buyTokens(amount);
    }

    function _fillToPhase6() internal {
        _buy(alice, 500_000e6);
        _buy(bob, 500_000e6);
        _buy(carol, 1_000_000e6);
        _buy(dave, 1_500_000e6);
        _buy(alice, 1_500_000e6);
        _buy(bob, 1_000_000e6);
    }

    function _fillHardCap() internal {
        _fillToPhase6();
        _buy(carol, 1_000_000e6);
    }

    function _finalizeByTimestamp() internal {
        vm.warp(presaleEnd);
        presale.finalizePresale();
    }
}
