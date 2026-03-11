// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Test } from "forge-std/Test.sol";
import { WebAI3Token } from "../src/WebAI3Token.sol";

contract WebAI3TokenTest is Test {
    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal community = makeAddr("community");
    address internal investors = makeAddr("investors");
    address internal team = makeAddr("team");
    address internal incentives = makeAddr("incentives");
    address internal liquidity = makeAddr("liquidity");
    address internal spender = makeAddr("spender");

    uint256 internal alicePk = 0xA11CE;
    address internal alice = vm.addr(alicePk);

    WebAI3Token internal token;

    function setUp() public {
        token = new WebAI3Token(admin, _defaultAllocations());
    }

    function test_ConstructorMintsExactMaxSupply() public view {
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
        assertEq(token.balanceOf(community), 350_000_000 ether);
        assertEq(token.balanceOf(team), 200_000_000 ether);
        assertEq(token.balanceOf(investors), 150_000_000 ether);
        assertEq(token.balanceOf(treasury), 150_000_000 ether);
        assertEq(token.balanceOf(incentives), 100_000_000 ether);
        assertEq(token.balanceOf(liquidity), 50_000_000 ether);
    }

    function test_ConstructorGrantsAdminAndPauserRoles() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
    }

    function test_ConstructorRevertsForZeroAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(WebAI3Token.InvalidAdmin.selector, address(0)));
        new WebAI3Token(address(0), _defaultAllocations());
    }

    function test_ConstructorRevertsForEmptyAllocations() public {
        WebAI3Token.Allocation[] memory empty;

        vm.expectRevert(WebAI3Token.EmptyAllocations.selector);
        new WebAI3Token(admin, empty);
    }

    function test_ConstructorRevertsForZeroRecipient() public {
        WebAI3Token.Allocation[] memory allocations = _defaultAllocations();
        allocations[2].recipient = address(0);

        vm.expectRevert(abi.encodeWithSelector(WebAI3Token.InvalidAllocationRecipient.selector, 2));
        new WebAI3Token(admin, allocations);
    }

    function test_ConstructorRevertsWhenTotalIsNotMaxSupply() public {
        WebAI3Token.Allocation[] memory allocations = _defaultAllocations();
        allocations[0].amount -= 1 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                WebAI3Token.InvalidAllocationTotal.selector,
                token.MAX_SUPPLY(),
                token.MAX_SUPPLY() - 1 ether
            )
        );
        new WebAI3Token(admin, allocations);
    }

    function test_OnlyPauserCanPause() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                token.PAUSER_ROLE()
            )
        );
        token.pause();
        vm.stopPrank();
    }

    function test_PauseBlocksTransfers() public {
        vm.prank(admin);
        token.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(community);
        this.transferToken(address(token), treasury, 1 ether);
    }

    function test_UnpauseRestoresTransfers() public {
        vm.startPrank(admin);
        token.pause();
        token.unpause();
        vm.stopPrank();

        vm.prank(community);
        bool success = token.transfer(treasury, 1 ether);
        assertTrue(success);

        assertEq(token.balanceOf(treasury), 150_000_001 ether);
    }

    function test_TransferMovesVotingPowerAfterDelegation() public {
        vm.prank(community);
        token.delegate(community);

        vm.prank(team);
        token.delegate(team);

        assertEq(token.getVotes(community), 350_000_000 ether);
        assertEq(token.getVotes(team), 200_000_000 ether);

        vm.prank(community);
        bool success = token.transfer(team, 10 ether);
        assertTrue(success);

        assertEq(token.getVotes(community), 349_999_990 ether);
        assertEq(token.getVotes(team), 200_000_010 ether);
    }

    function test_PermitSetsAllowance() public {
        WebAI3Token permitToken = new WebAI3Token(admin, _allocationsForPermit());
        uint256 deadline = block.timestamp + 1 days;
        uint256 value = 123 ether;

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, spender, value, permitToken.nonces(alice), deadline)
        );
        bytes32 digest =
            MessageHashUtils.toTypedDataHash(permitToken.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        permitToken.permit(alice, spender, value, deadline, v, r, s);

        assertEq(permitToken.allowance(alice, spender), value);
        assertEq(permitToken.nonces(alice), 1);
    }

    function testFuzz_TransferPreservesSupply(uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(community));

        vm.prank(community);
        bool success = token.transfer(treasury, amount);
        assertTrue(success);

        assertEq(token.totalSupply(), token.MAX_SUPPLY());
        assertEq(token.balanceOf(community), 350_000_000 ether - amount);
        assertEq(token.balanceOf(treasury), 150_000_000 ether + amount);
    }

    function _defaultAllocations()
        internal
        view
        returns (WebAI3Token.Allocation[] memory allocations)
    {
        allocations = new WebAI3Token.Allocation[](6);
        allocations[0] = WebAI3Token.Allocation({ recipient: community, amount: 350_000_000 ether });
        allocations[1] = WebAI3Token.Allocation({ recipient: team, amount: 200_000_000 ether });
        allocations[2] = WebAI3Token.Allocation({ recipient: investors, amount: 150_000_000 ether });
        allocations[3] = WebAI3Token.Allocation({ recipient: treasury, amount: 150_000_000 ether });
        allocations[4] =
            WebAI3Token.Allocation({ recipient: incentives, amount: 100_000_000 ether });
        allocations[5] = WebAI3Token.Allocation({ recipient: liquidity, amount: 50_000_000 ether });
    }

    function _allocationsForPermit()
        internal
        view
        returns (WebAI3Token.Allocation[] memory allocations)
    {
        allocations = new WebAI3Token.Allocation[](2);
        allocations[0] = WebAI3Token.Allocation({ recipient: alice, amount: 600_000_000 ether });
        allocations[1] = WebAI3Token.Allocation({ recipient: treasury, amount: 400_000_000 ether });
    }

    function transferToken(address tokenAddress, address to, uint256 amount)
        external
        returns (bool)
    {
        return WebAI3Token(tokenAddress).transfer(to, amount);
    }
}
