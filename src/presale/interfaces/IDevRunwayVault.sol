// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IDevRunwayVault {
    function onDeposit(uint256 amount, uint256 totalRaisedAfter) external;
}
