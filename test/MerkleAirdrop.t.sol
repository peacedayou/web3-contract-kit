// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MerkleAirdropTest is Test {
    MerkleAirdrop airdrop;
    MockERC20 token;
    address owner = makeAddr("owner");
    address[4] accounts;
    uint256[4] amounts = [uint256(100 ether), 250 ether, 75 ether, 1 ether];
    bytes32[4] leaves;
    bytes32 n01;
    bytes32 n23;
    uint64 deadline;

    function _leaf(uint256 index, address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
    }

    /// Same pair hashing as OpenZeppelin MerkleProof (sorted pairs).
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function setUp() public {
        accounts = [makeAddr("a0"), makeAddr("a1"), makeAddr("a2"), makeAddr("a3")];
        for (uint256 i = 0; i < 4; i++) {
            leaves[i] = _leaf(i, accounts[i], amounts[i]);
        }
        n01 = _hashPair(leaves[0], leaves[1]);
        n23 = _hashPair(leaves[2], leaves[3]);
        bytes32 root = _hashPair(n01, n23);

        deadline = uint64(block.timestamp + 30 days);
        token = new MockERC20();
        airdrop = new MerkleAirdrop(token, root, deadline, owner);
        token.mint(address(airdrop), 426 ether);
    }

    function _proof(uint256 index) internal view returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = leaves[index ^ 1];
        p[1] = index < 2 ? n23 : n01;
    }

    function test_ClaimTransfersTokens() public {
        for (uint256 i = 0; i < 4; i++) {
            airdrop.claim(i, accounts[i], amounts[i], _proof(i));
            assertEq(token.balanceOf(accounts[i]), amounts[i]);
            assertTrue(airdrop.isClaimed(i));
        }
        assertEq(token.balanceOf(address(airdrop)), 0);
    }

    function test_RevertWhen_ClaimingTwice() public {
        airdrop.claim(1, accounts[1], amounts[1], _proof(1));
        vm.expectRevert(MerkleAirdrop.AlreadyClaimed.selector);
        airdrop.claim(1, accounts[1], amounts[1], _proof(1));
    }

    function test_RevertWhen_AmountIsInflated() public {
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        airdrop.claim(0, accounts[0], amounts[0] + 1, _proof(0));
    }

    function test_RevertWhen_ClaimingForAnotherAccount() public {
        address attacker = makeAddr("attacker");
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        airdrop.claim(0, attacker, amounts[0], _proof(0));
    }

    function test_RevertWhen_DeadlinePassed() public {
        vm.warp(deadline + 1);
        vm.expectRevert(MerkleAirdrop.ClaimWindowClosed.selector);
        airdrop.claim(0, accounts[0], amounts[0], _proof(0));
    }

    function test_SweepOnlyAfterDeadline() public {
        vm.prank(owner);
        vm.expectRevert(MerkleAirdrop.ClaimWindowOpen.selector);
        airdrop.sweep(owner);

        airdrop.claim(0, accounts[0], amounts[0], _proof(0));
        vm.warp(deadline + 1);
        vm.prank(owner);
        airdrop.sweep(owner);
        assertEq(token.balanceOf(owner), 326 ether);
    }

    function test_RevertWhen_NotOwnerSweeps() public {
        vm.warp(deadline + 1);
        vm.expectRevert();
        airdrop.sweep(address(this));
    }

    function testFuzz_RandomProofIsRejected(bytes32 a, bytes32 b) public {
        bytes32[] memory p = new bytes32[](2);
        p[0] = a;
        p[1] = b;
        vm.assume(a != leaves[1] || b != n23);
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        airdrop.claim(0, accounts[0], amounts[0], p);
    }
}
