// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {WebAI3Token} from "../src/WebAI3Token.sol";

contract DeployWebAI3Token is Script {
    function run() external returns (WebAI3Token token) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("TOKEN_ADMIN");
        address treasury = vm.envAddress("TOKEN_TREASURY");
        address community = vm.envAddress("TOKEN_COMMUNITY");
        address investors = vm.envAddress("TOKEN_INVESTORS");
        address team = vm.envAddress("TOKEN_TEAM");
        address incentives = vm.envAddress("TOKEN_INCENTIVES");
        address liquidity = vm.envAddress("TOKEN_LIQUIDITY");

        WebAI3Token.Allocation[] memory allocations = new WebAI3Token.Allocation[](6);
        allocations[0] = WebAI3Token.Allocation({recipient: community, amount: 350_000_000 ether});
        allocations[1] = WebAI3Token.Allocation({recipient: team, amount: 200_000_000 ether});
        allocations[2] = WebAI3Token.Allocation({recipient: investors, amount: 150_000_000 ether});
        allocations[3] = WebAI3Token.Allocation({recipient: treasury, amount: 150_000_000 ether});
        allocations[4] = WebAI3Token.Allocation({recipient: incentives, amount: 100_000_000 ether});
        allocations[5] = WebAI3Token.Allocation({recipient: liquidity, amount: 50_000_000 ether});

        vm.startBroadcast(deployerPrivateKey);
        token = new WebAI3Token(admin, allocations);
        vm.stopBroadcast();
    }
}
