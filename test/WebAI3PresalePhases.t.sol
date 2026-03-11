// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PresaleSystemTestBase } from "./helpers/PresaleSystemTestBase.sol";

contract WebAI3PresalePhaseModelTest is PresaleSystemTestBase {
    function test_PhaseConstantsMatchSpec() public view {
        (uint256 cap0, uint256 price0, uint256 tokenCap0,,) = presale.getPhaseInfo(0);
        assertEq(cap0, 500_000e6);
        assertEq(price0, 10_000);
        assertEq(tokenCap0, 50_000_000 ether);

        (uint256 cap6, uint256 price6, uint256 tokenCap6,,) = presale.getPhaseInfo(6);
        assertEq(cap6, 7_000_000e6);
        assertEq(price6, 70_000);
        assertEq(tokenCap6, 249_500_000 ether);
    }

    function test_PhaseProgressionByCumulativeRaise() public {
        assertEq(presale.getActivePhase(), 0);

        _buy(alice, 500_000e6);
        assertEq(presale.getActivePhase(), 1);

        _buy(bob, 500_000e6);
        assertEq(presale.getActivePhase(), 2);

        _buy(carol, 1_000_000e6);
        assertEq(presale.getActivePhase(), 3);

        _buy(dave, 1_500_000e6);
        assertEq(presale.getActivePhase(), 4);

        _buy(alice, 1_500_000e6);
        assertEq(presale.getActivePhase(), 5);

        _buy(bob, 1_000_000e6);
        assertEq(presale.getActivePhase(), 6);

        _buy(carol, 1_000_000e6);
        assertEq(presale.getActivePhase(), type(uint8).max);
    }

    function test_RemainingHardCapView() public {
        assertEq(presale.remainingHardCapUSDC(), 7_000_000e6);

        _buy(alice, 123_456e6);
        assertEq(presale.remainingHardCapUSDC(), 7_000_000e6 - 123_456e6);
    }

    function test_RoundingDownPolicy() public {
        _buy(alice, 500_000e6); // move to phase 2 with 0.013

        uint256 amount = 1e6; // $1 USDC
        uint256 expected = (amount * 1e18) / 13_000;

        uint256 minted = _buy(alice, amount);
        assertEq(minted, expected);
        assertEq(minted * 13_000 <= amount * 1e18, true);
    }
}
