// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Pausable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

contract WebAI3Token is ERC20, ERC20Pausable, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    error InvalidAdmin(address admin);
    error EmptyAllocations();
    error InvalidAllocationRecipient(uint256 index);
    error InvalidAllocationTotal(uint256 expected, uint256 actual);

    struct Allocation {
        address recipient;
        uint256 amount;
    }

    constructor(address admin, Allocation[] memory allocations)
        ERC20("WebAI3 Token", "AIC")
        ERC20Permit("WebAI3 Token")
    {
        if (admin == address(0)) {
            revert InvalidAdmin(admin);
        }

        if (allocations.length == 0) {
            revert EmptyAllocations();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        uint256 totalAllocated;
        for (uint256 i = 0; i < allocations.length; ++i) {
            Allocation memory allocation = allocations[i];

            if (allocation.recipient == address(0)) {
                revert InvalidAllocationRecipient(i);
            }

            totalAllocated += allocation.amount;
            _mint(allocation.recipient, allocation.amount);
        }

        if (totalAllocated != MAX_SUPPLY) {
            revert InvalidAllocationTotal(MAX_SUPPLY, totalAllocated);
        }
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
