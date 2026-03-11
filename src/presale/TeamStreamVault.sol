// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./PresaleErrors.sol";
import { ITeamStreamVault } from "./interfaces/ITeamStreamVault.sol";

/// @title TeamStreamVault
/// @notice Linear-release team vault. No lump-sum drain path.
/// @dev Simplicity-first model: stream accrues from `streamStartTimestamp` over `streamDuration`.
contract TeamStreamVault is AccessControl, ReentrancyGuard, ITeamStreamVault {
    using SafeERC20 for IERC20;

    bytes32 public constant TEAM_OPERATOR_ROLE = keccak256("TEAM_OPERATOR_ROLE");

    IERC20 public immutable usdc;
    address public immutable beneficiary;
    uint64 public immutable streamStartTimestamp;
    uint256 public immutable streamDuration;

    address public presaleVault;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    event PresaleVaultSet(address indexed vault);
    event TeamDeposited(uint256 amount, uint256 totalDeposited);
    event TeamWithdrawn(address indexed caller, uint256 amount, address indexed beneficiary);

    modifier onlyPresaleVault() {
        if (msg.sender != presaleVault) revert NotAuthorized();
        _;
    }

    constructor(
        address admin,
        address usdc_,
        address beneficiary_,
        uint64 streamStartTimestamp_,
        uint256 streamDuration_
    ) {
        if (
            admin == address(0) || usdc_ == address(0) || beneficiary_ == address(0)
                || streamDuration_ == 0
        ) {
            revert InvalidConfiguration();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        usdc = IERC20(usdc_);
        beneficiary = beneficiary_;
        streamStartTimestamp = streamStartTimestamp_;
        streamDuration = streamDuration_;
    }

    /// @notice One-time PresaleVault binding.
    function setPresaleVault(address presaleVault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (presaleVault_ == address(0)) revert InvalidAddress();
        if (presaleVault != address(0)) revert AlreadyConfigured();

        presaleVault = presaleVault_;
        emit PresaleVaultSet(presaleVault_);
    }

    /// @inheritdoc ITeamStreamVault
    function onDeposit(uint256 amount) external onlyPresaleVault {
        if (amount == 0) revert ZeroAmount();

        totalDeposited += amount;
        emit TeamDeposited(amount, totalDeposited);
    }

    /// @notice Withdraw currently streamed amount to the fixed team beneficiary.
    function withdraw(uint256 amount) external onlyRole(TEAM_OPERATOR_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 available = withdrawableAmount();
        if (amount > available) revert WithdrawalExceedsLimit();

        totalWithdrawn += amount;
        usdc.safeTransfer(beneficiary, amount);

        emit TeamWithdrawn(msg.sender, amount, beneficiary);
    }

    /// @notice Total amount that has streamed so far.
    function streamedAmount() public view returns (uint256) {
        if (block.timestamp <= streamStartTimestamp) {
            return 0;
        }

        uint256 elapsed = block.timestamp - streamStartTimestamp;
        if (elapsed >= streamDuration) {
            return totalDeposited;
        }

        return (totalDeposited * elapsed) / streamDuration;
    }

    /// @notice Amount currently withdrawable by team operator role.
    function withdrawableAmount() public view returns (uint256) {
        uint256 streamed = streamedAmount();
        if (streamed <= totalWithdrawn) {
            return 0;
        }

        return streamed - totalWithdrawn;
    }
}
