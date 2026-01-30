// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/security/PullPayment.sol";

contract PullPaymentImpl is PullPayment {
    function allocate(address payee, uint256 amount) external {
        _allocatePayment(payee, amount);
    }

    function allocateBatch(address[] calldata payees, uint256[] calldata amounts) external {
        _allocatePaymentsBatch(payees, amounts);
    }

    receive() external payable { }
}

contract PullPaymentTest is Test {
    PullPaymentImpl public target;
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        target = new PullPaymentImpl();
        vm.deal(address(target), 100 ether);
    }

    function testAllocatePayment() public {
        target.allocate(user1, 1 ether);

        assertEq(target.pendingWithdrawals(user1), 1 ether);
        assertEq(target.totalPending(), 1 ether);
    }

    function testWithdrawPayments() public {
        target.allocate(user1, 1 ether);

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        target.withdrawPayments();

        assertEq(user1.balance, balanceBefore + 1 ether);
        assertEq(target.pendingWithdrawals(user1), 0);
        assertEq(target.totalPending(), 0);
    }

    function testCannotWithdrawNothing() public {
        vm.prank(user1);
        vm.expectRevert(PullPayment.NothingToWithdraw.selector);
        target.withdrawPayments();
    }

    function testWithdrawPaymentsTo() public {
        target.allocate(user1, 1 ether);

        uint256 balanceBefore = user1.balance;

        // Someone else can trigger the withdrawal for user1
        vm.prank(user2);
        target.withdrawPaymentsTo(payable(user1));

        assertEq(user1.balance, balanceBefore + 1 ether);
    }

    function testBatchAllocate() public {
        address[] memory payees = new address[](2);
        payees[0] = user1;
        payees[1] = user2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        target.allocateBatch(payees, amounts);

        assertEq(target.pendingWithdrawals(user1), 1 ether);
        assertEq(target.pendingWithdrawals(user2), 2 ether);
        assertEq(target.totalPending(), 3 ether);
    }

    function testIsSolvent() public {
        assertTrue(target.isSolvent());

        target.allocate(user1, 50 ether);
        assertTrue(target.isSolvent());

        target.allocate(user2, 60 ether);
        assertFalse(target.isSolvent()); // 110 ether pending, only 100 in contract
    }

    function testCannotAllocateZeroAddress() public {
        vm.expectRevert(PullPayment.ZeroAddress.selector);
        target.allocate(address(0), 1 ether);
    }

    function testCannotAllocateZeroAmount() public {
        vm.expectRevert(PullPayment.ZeroAmount.selector);
        target.allocate(user1, 0);
    }

    function testFuzz_AllocateAndWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= address(target).balance);

        target.allocate(user1, amount);

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        target.withdrawPayments();

        assertEq(user1.balance, balanceBefore + amount);
    }
}
