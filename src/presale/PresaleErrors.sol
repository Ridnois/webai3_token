// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

error InvalidAddress();
error InvalidTimestamp();
error InvalidConfiguration();
error AlreadyConfigured();
error NotAuthorized();

error ZeroAmount();
error PresaleNotActive();
error PresaleAlreadyFinalized();
error PresaleNotFinalized();
error PresaleNotStarted();
error PresaleEnded();
error PresaleNotFinalizable();

error PauseAlreadyActive();
error PauseNotActive();
error PauseBudgetExceeded();
error ForceUnpauseUnavailable();

error HardCapExceeded();
error NoActivePhase();
error PhaseCapExceeded();

error AllocationCapExceeded();
error ClaimsNotEnabled();
error NothingClaimable();
error LiquidityNotProvisioned();

error LiquidityAlreadyProvisioned();
error LiquidityWindowExpired();
error LiquidityFallbackNotAvailable();
error LiquidityExecutionFailed();

error MarketingLocked();
error TimelockNotReady();
error NoQueuedWithdrawal();
error WithdrawalExceedsLimit();
