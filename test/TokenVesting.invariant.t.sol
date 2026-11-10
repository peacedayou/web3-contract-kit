// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @dev Random sequences of create / release / revoke / time travel.
contract VestingHandler is CommonBase, StdCheats, StdUtils {
    TokenVesting public vesting;
    MockERC20 public token;
    address public owner;

    constructor(TokenVesting vesting_, MockERC20 token_, address owner_) {
        vesting = vesting_;
        token = token_;
        owner = owner_;
    }

    function create(uint256 amount, uint64 cliff, uint64 duration, bool revocable) external {
        amount = bound(amount, 1, 1e30);
        duration = uint64(bound(duration, 1, 4 * 365 days));
        cliff = uint64(bound(cliff, 0, duration));
        token.mint(owner, amount);
        vm.prank(owner);
        vesting.createSchedule(makeAddr("beneficiary"), uint64(block.timestamp), cliff, duration, amount, revocable);
    }

    function release(uint256 id) external {
        uint256 n = vesting.scheduleCount();
        if (n == 0) return;
        id = bound(id, 0, n - 1);
        if (vesting.releasableAmount(id) > 0) vesting.release(id);
    }

    function revoke(uint256 id) external {
        uint256 n = vesting.scheduleCount();
        if (n == 0) return;
        id = bound(id, 0, n - 1);
        TokenVesting.Schedule memory s = vesting.getSchedule(id);
        if (!s.revocable || s.revoked) return;
        vm.prank(owner);
        vesting.revoke(id);
    }

    function warp(uint256 secondsForward) external {
        vm.warp(block.timestamp + bound(secondsForward, 1, 180 days));
    }
}

contract TokenVestingInvariantTest is Test {
    TokenVesting vesting;
    MockERC20 token;
    VestingHandler handler;
    address owner = makeAddr("owner");

    function setUp() public {
        token = new MockERC20();
        vesting = new TokenVesting(token, owner);
        handler = new VestingHandler(vesting, token, owner);
        vm.prank(owner);
        token.approve(address(vesting), type(uint256).max);
        targetContract(address(handler));
    }

    /// The contract always holds enough tokens to pay every beneficiary.
    function invariant_Solvent() public view {
        assertGe(token.balanceOf(address(vesting)), vesting.totalCommitted());
    }

    /// No schedule ever releases more than its total.
    function invariant_ReleasedNeverExceedsTotal() public view {
        uint256 n = vesting.scheduleCount();
        for (uint256 i = 0; i < n; i++) {
            TokenVesting.Schedule memory s = vesting.getSchedule(i);
            assertLe(s.released, s.total);
        }
    }
}
