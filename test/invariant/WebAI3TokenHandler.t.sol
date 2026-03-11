// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { WebAI3Token } from "../../src/WebAI3Token.sol";

contract WebAI3TokenHandler is Test {
    WebAI3Token internal immutable TOKEN;
    address internal immutable ADMIN;
    address[] internal actors;

    constructor(WebAI3Token _token, address _admin, address[] memory _actors) {
        TOKEN = _token;
        ADMIN = _admin;
        actors = _actors;
    }

    function transferBetweenActors(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        uint256 actorLen = actors.length;
        address from = actors[fromSeed % actorLen];
        address to = actors[toSeed % actorLen];

        if (from == to) {
            return;
        }

        uint256 balance = TOKEN.balanceOf(from);
        if (balance == 0) {
            return;
        }

        amount = bound(amount, 0, balance);

        vm.prank(from);
        try TOKEN.transfer(to, amount) { } catch { }
    }

    function pause() external {
        vm.prank(ADMIN);
        try TOKEN.pause() { } catch { }
    }

    function unpause() external {
        vm.prank(ADMIN);
        try TOKEN.unpause() { } catch { }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }
}
