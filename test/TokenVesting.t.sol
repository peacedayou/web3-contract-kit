// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MockERC20, FeeToken} from "./mocks/MockERC20.sol";

contract TokenVestingTest is Test {
    TokenVesting vesting;
    MockERC20 token;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    uint64 constant START = 1_000_000;
    uint64 constant CLIFF = 90 days;
    uint64 constant DURATION = 365 days;
    uint256 constant AMOUNT = 1_000_000 ether;

    function setUp() public {
        token = new MockERC20();
        vesting = new TokenVesting(token, owner);
        token.mint(owner, 10 * AMOUNT);
        vm.prank(owner);
        token.approve(address(vesting), type(uint256).max);
        vm.warp(START);
    }

    function _create(bool revocable) internal returns (uint256) {
        vm.prank(owner);
        return vesting.createSchedule(alice, START, CLIFF, DURATION, AMOUNT, revocable);
    }

    function test_NothingVestedBeforeCliff() public {
        uint256 id = _create(true);
        vm.warp(START + CLIFF - 1);
        assertEq(vesting.vestedAmount(id), 0);
        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release(id);
    }

    function test_LinearVestingAfterCliff() public {
        uint256 id = _create(true);
        vm.warp(START + DURATION / 2);
        assertEq(vesting.vestedAmount(id), AMOUNT / 2);
    }

    function test_FullyVestedAfterEnd() public {
        uint256 id = _create(true);
        vm.warp(START + DURATION + 1);
        vesting.release(id);
        assertEq(token.balanceOf(alice), AMOUNT);
        assertEq(vesting.totalCommitted(), 0);
    }

    function test_ReleaseTwiceOnlyPaysDifference() public {
        uint256 id = _create(true);
        vm.warp(START + DURATION / 2);
        vesting.release(id);
        vm.warp(START + (DURATION * 3) / 4);
        vesting.release(id);
        assertEq(token.balanceOf(alice), (AMOUNT * 3) / 4);
    }

    function test_RevokeRefundsUnvestedAndKeepsVested() public {
        uint256 id = _create(true);
        vm.warp(START + DURATION / 4);
        uint256 ownerBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.revoke(id);

        assertEq(token.balanceOf(owner) - ownerBefore, (AMOUNT * 3) / 4);
        // Vested part stays claimable, even much later
        vm.warp(START + DURATION * 2);
        vesting.release(id);
        assertEq(token.balanceOf(alice), AMOUNT / 4);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_RevertWhen_RevokingNonRevocable() public {
        uint256 id = _create(false);
        vm.prank(owner);
        vm.expectRevert(TokenVesting.NotRevocable.selector);
        vesting.revoke(id);
    }

    function test_RevertWhen_RevokingTwice() public {
        uint256 id = _create(true);
        vm.startPrank(owner);
        vesting.revoke(id);
        vm.expectRevert(TokenVesting.AlreadyRevoked.selector);
        vesting.revoke(id);
        vm.stopPrank();
    }

    function test_RevertWhen_NotOwnerCreates() public {
        vm.prank(alice);
        vm.expectRevert();
        vesting.createSchedule(alice, START, CLIFF, DURATION, AMOUNT, true);
    }

    function test_RevertWhen_InvalidParameters() public {
        vm.startPrank(owner);
        vm.expectRevert(TokenVesting.ZeroAddress.selector);
        vesting.createSchedule(address(0), START, CLIFF, DURATION, AMOUNT, true);
        vm.expectRevert(TokenVesting.ZeroAmount.selector);
        vesting.createSchedule(alice, START, CLIFF, DURATION, 0, true);
        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        vesting.createSchedule(alice, START, DURATION + 1, DURATION, AMOUNT, true);
        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        vesting.createSchedule(alice, START, 0, 0, AMOUNT, true);
        vm.stopPrank();
    }

    function test_RevertWhen_UnknownSchedule() public {
        vm.expectRevert(TokenVesting.UnknownSchedule.selector);
        vesting.vestedAmount(42);
    }

    function test_RevertWhen_FeeOnTransferToken() public {
        FeeToken fee = new FeeToken();
        TokenVesting v = new TokenVesting(fee, owner);
        fee.mint(owner, AMOUNT);
        vm.startPrank(owner);
        fee.approve(address(v), AMOUNT);
        vm.expectRevert(TokenVesting.UnsupportedToken.selector);
        v.createSchedule(alice, START, CLIFF, DURATION, AMOUNT, true);
        vm.stopPrank();
    }

    /// Vested amount never decreases over time and never exceeds the total.
    function testFuzz_VestedIsMonotonicAndBounded(uint256 amount, uint64 t1, uint64 t2) public {
        amount = bound(amount, 1, 10 * AMOUNT);
        t1 = uint64(bound(t1, START, START + 2 * DURATION));
        t2 = uint64(bound(t2, t1, START + 2 * DURATION));

        vm.prank(owner);
        uint256 id = vesting.createSchedule(alice, START, CLIFF, DURATION, amount, true);

        vm.warp(t1);
        uint256 v1 = vesting.vestedAmount(id);
        vm.warp(t2);
        uint256 v2 = vesting.vestedAmount(id);

        assertLe(v1, v2);
        assertLe(v2, amount);
    }

    /// After a revoke at any time, owner refund + beneficiary payout == original amount.
    function testFuzz_RevokeConservesTokens(uint64 revokeAt) public {
        revokeAt = uint64(bound(revokeAt, START, START + 2 * DURATION));
        uint256 id = _create(true);
        uint256 ownerBefore = token.balanceOf(owner);

        vm.warp(revokeAt);
        vm.prank(owner);
        vesting.revoke(id);
        if (vesting.releasableAmount(id) > 0) vesting.release(id);

        assertEq(token.balanceOf(owner) - ownerBefore + token.balanceOf(alice), AMOUNT);
    }
}
