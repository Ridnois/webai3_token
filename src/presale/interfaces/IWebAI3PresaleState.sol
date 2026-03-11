// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IWebAI3PresaleState {
    function presaleFinalized() external view returns (bool);
    function liquidityProvisioned() external view returns (bool);
}
