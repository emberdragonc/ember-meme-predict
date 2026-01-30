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

        (string[] memory returnedCoins, uint256 deadline, uint256 totalPot, , bool resolved) = prediction.getRound(1);
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

    // ============================================
    // Place Wager Tests
    // ============================================

    function test_PlaceWager() public {
        _createBasicRound();

        vm.prank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0); // Bet on PEPE

        (uint256 coinIndex, uint256 amount, bool claimed) = prediction.getWager(1, user1);
        assertEq(coinIndex, 0);
        assertEq(amount, 1 ether);
        assertFalse(claimed);

        (, , uint256 totalPot, , ) = prediction.getRound(1);
        assertEq(totalPot, 1 ether);
    }

    function test_PlaceWager_AddToExisting() public {
        _createBasicRound();

        vm.startPrank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0);
        prediction.placeWager{ value: 0.5 ether }(1, 0);
        vm.stopPrank();

        (, uint256 amount, ) = prediction.getWager(1, user1);
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
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);

        uint256 feeRecipientBefore = feeRecipient.balance;
        prediction.resolveRound(1, 0); // PEPE wins
        
        (, , , uint256 winningCoinIndex, bool resolved) = prediction.getRound(1);
        assertTrue(resolved);
        assertEq(winningCoinIndex, 0);

        // Fee should be 5% of 4 ETH = 0.2 ETH
        uint256 expectedFee = (4 ether * 500) / 10_000;
        assertEq(feeRecipient.balance - feeRecipientBefore, expectedFee);
    }

    function test_ResolveRound_OnlyOwner() public {
        _createBasicRound();
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        vm.expectRevert();
        prediction.resolveRound(1, 0);
    }

    function test_ResolveRound_RevertAlreadyResolved() public {
        _createBasicRound();
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0);

        vm.expectRevert(MemePrediction.RoundAlreadyResolved.selector);
        prediction.resolveRound(1, 1);
    }

    // ============================================
    // Claim Winnings Tests
    // ============================================

    function test_ClaimWinnings() public {
        _createBasicRound();
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0); // PEPE wins

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
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0); // PEPE wins

        vm.prank(user2); // User2 bet on DOGE, should lose
        vm.expectRevert(MemePrediction.NoWinnings.selector);
        prediction.claimWinnings(1);
    }

    function test_ClaimWinnings_RevertAlreadyClaimed() public {
        _createBasicRound();
        _placeWagers();

        vm.warp(block.timestamp + 2 hours);
        prediction.resolveRound(1, 0);

        vm.startPrank(user1);
        prediction.claimWinnings(1);
        
        vm.expectRevert(MemePrediction.AlreadyClaimed.selector);
        prediction.claimWinnings(1);
        vm.stopPrank();
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

    // ============================================
    // Admin Function Tests
    // ============================================

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        prediction.setFeeRecipient(newRecipient);
        assertEq(prediction.feeRecipient(), newRecipient);
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

    function _placeWagers() internal {
        vm.prank(user1);
        prediction.placeWager{ value: 1 ether }(1, 0); // Bet on PEPE

        vm.prank(user2);
        prediction.placeWager{ value: 2 ether }(1, 1); // Bet on DOGE

        vm.prank(user3);
        prediction.placeWager{ value: 1 ether }(1, 0); // Also bet on PEPE
    }
}
