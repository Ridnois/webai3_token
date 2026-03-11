# Presale Integration Note

1. Deploy `LiquidityVault`, `DevRunwayVault`, `TeamStreamVault`, and `MarketingVault`.
2. Deploy `PresaleVault` with the 4 vault addresses.
3. Call `setPresaleVault(presaleVault)` once on each sub-vault.
4. Deploy `ClaimModule`.
5. Deploy `WebAI3Presale` with `PresaleVault` and `ClaimModule` addresses.
6. Call `setPresale(webAI3Presale)` on `PresaleVault` and `ClaimModule`.
7. Grant operational roles:
   - `PAUSER_ROLE` on `WebAI3Presale`
   - `LIQUIDITY_EXECUTOR_ROLE` on `LiquidityVault`
   - `DEV_OPERATOR_ROLE` on `DevRunwayVault`
   - `TEAM_OPERATOR_ROLE` on `TeamStreamVault`
   - `MARKETING_OPERATOR_ROLE` on `MarketingVault`
8. Transfer presale AIC allocation to `ClaimModule` before enabling claims.

Claims flow is strictly ordered:
- `finalizePresale()` (permissionless)
- `provideLiquidity()` or `provideLiquidityFallback()`
- `enableClaims()`
