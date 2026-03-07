// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {WebAI3Token} from "../../src/WebAI3Token.sol";
import {WebAI3TokenHandler} from "./WebAI3TokenHandler.t.sol";

contract WebAI3TokenInvariants is StdInvariant, Test {
    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal community = makeAddr("community");
    address internal investors = makeAddr("investors");
    address internal team = makeAddr("team");
    address internal incentives = makeAddr("incentives");
    address internal liquidity = makeAddr("liquidity");

    WebAI3Token internal token;
    WebAI3TokenHandler internal handler;
    address[] internal actors;

    function setUp() public {
        token = new WebAI3Token(admin, _defaultAllocations());

        actors.push(treasury);
        actors.push(community);
        actors.push(investors);
        actors.push(team);
        actors.push(incentives);
        actors.push(liquidity);

        handler = new WebAI3TokenHandler(token, admin, actors);
        targetContract(address(handler));
    }

    function invariant_TotalSupplyAlwaysFixed() public view {
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
    }

    function invariant_TrackedBalancesAlwaysSumToSupply() public view {
        uint256 totalTracked;
        uint256 length = actors.length;

        for (uint256 i = 0; i < length; ++i) {
            totalTracked += token.balanceOf(actors[i]);
        }

        assertEq(totalTracked, token.totalSupply());
    }

    function _defaultAllocations() internal view returns (WebAI3Token.Allocation[] memory allocations) {
        allocations = new WebAI3Token.Allocation[](6);
        allocations[0] = WebAI3Token.Allocation({recipient: community, amount: 350_000_000 ether});
        allocations[1] = WebAI3Token.Allocation({recipient: team, amount: 200_000_000 ether});
        allocations[2] = WebAI3Token.Allocation({recipient: investors, amount: 150_000_000 ether});
        allocations[3] = WebAI3Token.Allocation({recipient: treasury, amount: 150_000_000 ether});
        allocations[4] = WebAI3Token.Allocation({recipient: incentives, amount: 100_000_000 ether});
        allocations[5] = WebAI3Token.Allocation({recipient: liquidity, amount: 50_000_000 ether});
    }
}
