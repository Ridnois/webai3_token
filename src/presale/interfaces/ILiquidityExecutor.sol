// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ILiquidityExecutor {
    /// @notice Execute the pre-approved liquidity plan.
    /// @param usdc USDC token address.
    /// @param usdcAmount Amount of USDC to use for provisioning.
    /// @param planHash Immutable plan commitment hash.
    /// @return lpTokensMinted Amount of LP tokens minted by the integration.
    function executeLiquidityProvision(address usdc, uint256 usdcAmount, bytes32 planHash)
        external
        returns (uint256 lpTokensMinted);
}
