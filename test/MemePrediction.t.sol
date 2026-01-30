// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { MemePrediction } from "../contracts/MemePrediction.sol";

contract MemePredictionTest is Test {
    MemePrediction public prediction;
    
    address public owner = address(this);
    address public feeRecipient = makeAddr("feeRecipient");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    // Salt for commit-reveal
    bytes32 constant SALT = keccak256("test_salt");

    function setUp() public {
        prediction = new MemePrediction(feeRecipient);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    // ============================================
    // Create Round Tests
    // ============================================

    function test_CreateRound() public {
        string[] memory coins = new string[](3);
        coins[0] = "PEPE";
        coins[1] = "DOGE";
        coins[2] = "SHIB";

        uint256 roundId = prediction.createRound(coins, 1 hours);
        assertEq(roundId, 1);

        (string[] memory returnedCoins, uint256 deadline, uint256 totalPot, , , bool resolved) = prediction.getRound(1);
        assertEq(returnedCoins.length, 3);
        assertEq(returnedCoins[0], "PEPE");
        assertEq(deadline, block.timestamp + 1 hours);
        assertEq(totalPot, 0);
        assertFalse(resolved);
    }

    function test_CreateRound_OnlyOwner() public {
        string[] memory coins = new string[](2);
        coins[0] = "PEPE";
        coins[1] = "DOGE";

        vm.prank(user1);
        vm.expectRevert();
        prediction.createRound(coins, 1 hours);
    }

    function test_CreateRound_RevertDurationTooShort() public {
        string[] memory coins = new string[](2);
        coins[0] = "PEPE";
        coins[1] = "DOGE";

        vm.expectRevert(MemePrediction.DurationTooShort.selector);
        prediction.createRound(coins, 30 minutes);
    }

    function test_CreateRound_RevertNeedAtLeastTwoCoins() public {
        string[] memory coins = new string[](1);
        coins[0] = "PEPE";

        vm.expectRevert(MemePrediction.NeedAtLeastTwoCoins.selector);
        prediction.createRound(coins, 1 hours);
    }

    // ============================================
    // Commit Winner Tests
    // ============================================

    function test_CommitWinner() public {
        _createBasicRound();
        
        bytes32 commitment = prediction.computeCommitment(1, 0, SALT);
        prediction.commitWinner(1, commitment);
        
        (, , , , bytes32 storedCommitment, ) = prediction.getRound(1);
        assertEq(storedCommitment, commitment);
    }

    function test_CommitWinner_RevertAfterDeadline() public {
        _createBasicRound();
        
        vm.warp(block.timestamp + 2 hours);
        
        bytes32 commitment = prediction.computeCommitment(1, 0, SALT);
        vm.expectRevert(MemePrediction.BettingClosed.selector);
        prediction.commitWinner(1, commitment);
    }

    function test_CommitWinner_RevertAlreadyCommitted() public {
        _createBasicRound();
        
        bytes32 commitment = prediction.computeCommitment(1, 0, SALT);
        prediction.commitWinner(1, commitment);
        
        vm.expectRevert(MemePrediction.AlreadyCommitted.selector);
        prediction.commitWinner(1, commitment);
    }

    // ============================================
    // Place Wager Tests
    // ============================================

    function test_PlaceWager() public {
        _createBasicRound();

        vm.prank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0); // Bet on PEPE

        (uint256 coinIndex, uint256 amount, bool claimed, bool refunded) = prediction.getWager(1, user1);
        assertEq(coinIndex, 0);
        assertEq(amount, 1 ether);
        assertFalse(claimed);
        assertFalse(refunded);

        (, , uint256 totalPot, , , ) = prediction.getRound(1);
        assertEq(totalPot, 1 ether);
    }

    function test_PlaceWager_AddToExisting() public {
        _createBasicRound();

        vm.startPrank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0);
        prediction.placeWager{ value: 0.5 ether }(1, 0);
        vm.stopPrank();

        (, uint256 amount, , ) = prediction.getWager(1, user1);
        assertEq(amount, 1.5 ether);
    }

    function test_PlaceWager_RevertDifferentCoin() public {
        _createBasicRound();

        vm.startPrank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0);
        
        vm.expectRevert(MemePrediction.InvalidCoinIndex.selector);
        prediction.placeWager{ value: 1 ether }(1, 1); // Try different coin
        vm.stopPrank();
    }

    function test_PlaceWager_RevertAfterDeadline() public {
        _createBasicRound();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        vm.expectRevert(MemePrediction.BettingClosed.selector);
        prediction.placeWager{ value: 1 ether }(1, 0);
    }

    function test_PlaceWager_RevertZeroAmount() public {
        _createBasicRound();

        vm.prank(user1);
        vm.expectRevert(MemePrediction.InsufficientWager.selector);
        prediction.placeWager{ value: 0 }(1, 0);
    }

    // ============================================
    // Resolve Round Tests
    // ============================================

    function test_ResolveRound() public {
        _createBasicRound();
        _commitWinner(0); // Commit to PEPE winning
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);

        uint256 feeRecipientBefore = feeRecipient.balance;
        prediction.resolveRound(1, 0, SALT); // PEPE wins
        
        (, , , uint256 winningCoinIndex, , bool resolved) = prediction.getRound(1);
        assertTrue(resolved);
        assertEq(winningCoinIndex, 0);

        // Fee should be 5% of 4 ETH = 0.2 ETH
        uint256 expectedFee = (4 ether * 500) / 10_000;
        assertEq(feeRecipient.balance - feeRecipientBefore, expectedFee);
    }

    function test_ResolveRound_OnlyOwner() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        vm.expectRevert();
        prediction.resolveRound(1, 0, SALT);
    }

    function test_ResolveRound_RevertNoCommitment() public {
        _createBasicRound();
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(MemePrediction.NoCommitment.selector);
        prediction.resolveRound(1, 0, SALT);
    }

    function test_ResolveRound_RevertCommitmentMismatch() public {
        _createBasicRound();
        _commitWinner(0); // Commit to PEPE winning
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);

        // Try to resolve with different winner
        vm.expectRevert(MemePrediction.CommitmentMismatch.selector);
        prediction.resolveRound(1, 1, SALT); // Try to say DOGE wins
    }

    function test_ResolveRound_RevertBettingStillOpen() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        // Don't warp time - betting still open
        vm.expectRevert(MemePrediction.BettingStillOpen.selector);
        prediction.resolveRound(1, 0, SALT);
    }

    function test_ResolveRound_RevertAlreadyResolved() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0, SALT);

        vm.expectRevert(MemePrediction.RoundAlreadyResolved.selector);
        prediction.resolveRound(1, 0, SALT);
    }

    // ============================================
    // Claim Winnings Tests
    // ============================================

    function test_ClaimWinnings() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0, SALT); // PEPE wins

        // User1 bet 1 ETH on PEPE, User3 bet 1 ETH on PEPE
        // Total pot: 4 ETH, PEPE pool: 2 ETH
        // Pot after fees: 4 - 0.2 = 3.8 ETH
        // User1 gets: 1/2 * 3.8 = 1.9 ETH

        uint256 user1Before = user1.balance;
        vm.prank(user1);
        prediction.claimWinnings(1);
        
        uint256 potAfterFees = 4 ether - ((4 ether * 500) / 10_000);
        uint256 expectedWinnings = (1 ether * potAfterFees) / 2 ether;
        
        assertEq(user1.balance - user1Before, expectedWinnings);
    }

    function test_ClaimWinnings_RevertNotResolved() public {
        _createBasicRound();
        _placeWagers();

        vm.prank(user1);
        vm.expectRevert(MemePrediction.RoundNotResolved.selector);
        prediction.claimWinnings(1);
    }

    function test_ClaimWinnings_RevertNoWinnings() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0, SALT); // PEPE wins

        vm.prank(user2); // User2 bet on DOGE, should lose
        vm.expectRevert(MemePrediction.NoWinnings.selector);
        prediction.claimWinnings(1);
    }

    function test_ClaimWinnings_RevertAlreadyClaimed() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0, SALT);

        vm.startPrank(user1);
        prediction.claimWinnings(1);
        
        vm.expectRevert(MemePrediction.AlreadyClaimed.selector);
        prediction.claimWinnings(1);
        vm.stopPrank();
    }

    // ============================================
    // Emergency Refund Tests
    // ============================================

    function test_EmergencyRefund() public {
        _createBasicRound();
        _placeWagers();

        // Warp past deadline + 7 days
        vm.warp(block.timestamp + 1 hours + 7 days + 1);

        uint256 user1Before = user1.balance;
        vm.prank(user1);
        prediction.emergencyRefund(1);

        assertEq(user1.balance - user1Before, 1 ether);
    }

    function test_EmergencyRefund_RevertTooEarly() public {
        _createBasicRound();
        _placeWagers();

        // Warp past deadline but not 7 days
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        vm.expectRevert(MemePrediction.RefundTooEarly.selector);
        prediction.emergencyRefund(1);
    }

    function test_EmergencyRefund_RevertAlreadyResolved() public {
        _createBasicRound();
        _commitWinner(0);
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0, SALT);

        // Even past 7 days, can't refund if resolved
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(user1);
        vm.expectRevert(MemePrediction.RoundAlreadyResolved.selector);
        prediction.emergencyRefund(1);
    }

    function test_EmergencyRefund_RevertAlreadyRefunded() public {
        _createBasicRound();
        _placeWagers();

        vm.warp(block.timestamp + 1 hours + 7 days + 1);

        vm.startPrank(user1);
        prediction.emergencyRefund(1);
        
        vm.expectRevert(MemePrediction.AlreadyRefunded.selector);
        prediction.emergencyRefund(1);
        vm.stopPrank();
    }

    function test_IsRefundAvailable() public {
        _createBasicRound();

        assertFalse(prediction.isRefundAvailable(1));

        vm.warp(block.timestamp + 1 hours + 7 days + 1);
        assertTrue(prediction.isRefundAvailable(1));
    }

    // ============================================
    // View Function Tests
    // ============================================

    function test_IsBettingOpen() public {
        _createBasicRound();

        assertTrue(prediction.isBettingOpen(1));

        vm.warp(block.timestamp + 2 hours);
        assertFalse(prediction.isBettingOpen(1));
    }

    function test_GetCoinTotal() public {
        _createBasicRound();
        _placeWagers();

        assertEq(prediction.getCoinTotal(1, 0), 2 ether); // PEPE
        assertEq(prediction.getCoinTotal(1, 1), 2 ether); // DOGE
    }

    function test_ComputeCommitment() public view {
        bytes32 commitment = prediction.computeCommitment(1, 0, SALT);
        bytes32 expected = keccak256(abi.encodePacked(uint256(1), uint256(0), SALT));
        assertEq(commitment, expected);
    }

    // ============================================
    // Admin Function Tests
    // ============================================

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        prediction.setFeeRecipient(newRecipient);
        assertEq(prediction.feeRecipient(), newRecipient);
    }

    function test_SetFeeRecipient_RevertZeroAddress() public {
        vm.expectRevert(MemePrediction.ZeroAddress.selector);
        prediction.setFeeRecipient(address(0));
    }

    // ============================================
    // Helpers
    // ============================================

    function _createBasicRound() internal {
        string[] memory coins = new string[](3);
        coins[0] = "PEPE";
        coins[1] = "DOGE";
        coins[2] = "SHIB";
        prediction.createRound(coins, 1 hours);
    }

    function _commitWinner(uint256 winnerIndex) internal {
        bytes32 commitment = prediction.computeCommitment(1, winnerIndex, SALT);
        prediction.commitWinner(1, commitment);
    }

    function _placeWagers() internal {
        vm.prank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0); // Bet on PEPE

        vm.prank(user2);
        prediction.placeWager{ value: 2 ether }(1, 1); // Bet on DOGE

        vm.prank(user3);
        prediction.placeWager{ value: 1 ether }(1, 0); // Also bet on PEPE
    }
}
