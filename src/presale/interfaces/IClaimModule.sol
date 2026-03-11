// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IClaimModule {
    function recordAllocation(address buyer, uint256 amount) external;
}
