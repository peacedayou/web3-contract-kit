// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SimpleMultisig} from "../src/SimpleMultisig.sol";

contract Reverter {
    function boom() external pure {
        revert("boom");
    }
}

contract SimpleMultisigTest is Test {
    SimpleMultisig wallet;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address recipient = makeAddr("recipient");

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = alice;
        owners[1] = bob;
        owners[2] = carol;
        wallet = new SimpleMultisig(owners, 2);
        vm.deal(address(wallet), 10 ether);
    }

    function test_TwoOfThreeSendsEther() public {
        vm.prank(alice);
        uint256 id = wallet.submit(recipient, 1 ether, "");
        vm.prank(bob);
        wallet.confirm(id);
        vm.prank(carol);
        wallet.execute(id);

        assertEq(recipient.balance, 1 ether);
        assertTrue(wallet.getTransaction(id).executed);
    }

    function test_RevertWhen_NotEnoughConfirmations() public {
        vm.prank(alice);
        uint256 id = wallet.submit(recipient, 1 ether, "");
        vm.prank(alice);
        vm.expectRevert(SimpleMultisig.NotEnoughConfirmations.selector);
        wallet.execute(id);
    }

    function test_RevertWhen_NonOwnerActs() public {
        vm.expectRevert(SimpleMultisig.NotOwner.selector);
        wallet.submit(recipient, 1 ether, "");
    }

    function test_RevertWhen_ConfirmingTwice() public {
        vm.prank(alice);
        uint256 id = wallet.submit(recipient, 1 ether, "");
        vm.prank(alice);
        vm.expectRevert(SimpleMultisig.AlreadyConfirmed.selector);
        wallet.confirm(id);
    }

    function test_RevokedConfirmationNoLongerCounts() public {
        vm.prank(alice);
        uint256 id = wallet.submit(recipient, 1 ether, "");
        vm.prank(bob);
        wallet.confirm(id);
        vm.prank(bob);
        wallet.revokeConfirmation(id);
        vm.prank(alice);
        vm.expectRevert(SimpleMultisig.NotEnoughConfirmations.selector);
        wallet.execute(id);
    }

    function test_RevertWhen_ExecutingTwice() public {
        vm.prank(alice);
        uint256 id = wallet.submit(recipient, 1 ether, "");
        vm.prank(bob);
        wallet.confirm(id);
        vm.prank(bob);
        wallet.execute(id);
        vm.prank(carol);
        vm.expectRevert(SimpleMultisig.AlreadyExecuted.selector);
        wallet.execute(id);
    }

    function test_FailedCallRevertsAndStaysPending() public {
        Reverter r = new Reverter();
        vm.prank(alice);
        uint256 id = wallet.submit(address(r), 0, abi.encodeCall(Reverter.boom, ()));
        vm.prank(bob);
        wallet.confirm(id);
        vm.prank(bob);
        vm.expectRevert();
        wallet.execute(id);
        assertFalse(wallet.getTransaction(id).executed);
    }

    function test_ThresholdChangesOnlyThroughWallet() public {
        vm.prank(alice);
        vm.expectRevert(SimpleMultisig.NotSelf.selector);
        wallet.changeThreshold(3);

        vm.prank(alice);
        uint256 id = wallet.submit(address(wallet), 0, abi.encodeCall(SimpleMultisig.changeThreshold, (3)));
        vm.prank(bob);
        wallet.confirm(id);
        vm.prank(bob);
        wallet.execute(id);
        assertEq(wallet.threshold(), 3);
    }

    function test_RevertWhen_InvalidConstructorArgs() public {
        address[] memory dup = new address[](2);
        dup[0] = alice;
        dup[1] = alice;
        vm.expectRevert(SimpleMultisig.InvalidOwners.selector);
        new SimpleMultisig(dup, 1);

        address[] memory one = new address[](1);
        one[0] = alice;
        vm.expectRevert(SimpleMultisig.InvalidThreshold.selector);
        new SimpleMultisig(one, 2);
    }

    function test_ReceivesEther() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(wallet).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(wallet).balance, 11 ether);
    }
}
