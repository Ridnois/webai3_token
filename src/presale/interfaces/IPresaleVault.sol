// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IPresaleVault {
    function routeDeposit(uint256 usdcAmount, uint256 totalRaisedAfter) external;
    function onPresaleFinalized(uint64 finalizedAt) external;
    function liquidityProvisioned() external view returns (bool);
}
