// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMarketingVault {
    function onDeposit(uint256 amount) external;
    function onPresaleFinalized(uint64 finalizedAt) external;
}
