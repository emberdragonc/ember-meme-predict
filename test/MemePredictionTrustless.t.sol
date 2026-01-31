// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { MemePredictionTrustless } from "../contracts/MemePredictionTrustless.sol";
import { MockPyth } from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title MemePredictionTrustless Tests
 * @notice Comprehensive test suite for the trustless oracle-based prediction market
 */
contract MemePredictionTrustlessTest is Test {
    MemePredictionTrustless public prediction;
    MockPyth public mockPyth;

    address public owner = makeAddr("owner");
    address public feeRecipient = makeAddr("feeRecipient");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public resolver = makeAddr("resolver");

    // Pyth price feed IDs (mock)
    bytes32 public constant PEPE_FEED = bytes32(uint256(1));
    bytes32 public constant DOGE_FEED = bytes32(uint256(2));
    bytes32 public constant SHIB_FEED = bytes32(uint256(3));

    uint256 public constant VALID_UPDATE_FEE = 1;

    function setUp() public {
        // Deploy mock Pyth with 1 wei update fee and 60s validity period
        mockPyth = new MockPyth(60, VALID_UPDATE_FEE);
        
        vm.prank(owner);
        prediction = new MemePredictionTrustless(address(mockPyth), feeRecipient);

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(resolver, 1 ether);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _createPriceUpdate(bytes32 feedId, int64 price, int32 expo) internal view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            feedId,
            price,
            10, // conf
            expo,
            price,
            10,
            uint64(block.timestamp)
        );
        return updateData;
    }

    function _createMultiPriceUpdate(
        bytes32[] memory feedIds,
        int64[] memory prices,
        int32 expo
    ) internal view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](feedIds.length);
        for (uint256 i = 0; i < feedIds.length; i++) {
            updateData[i] = mockPyth.createPriceFeedUpdateData(
                feedIds[i],
                prices[i],
                10,
                expo,
                prices[i],
                10,
                uint64(block.timestamp)
            );
        }
        return updateData;
    }

    function _createStandardRound() internal returns (uint256 roundId) {
        string[] memory symbols = new string[](3);
        bytes32[] memory feeds = new bytes32[](3);
        
        symbols[0] = "PEPE";
        symbols[1] = "DOGE";
        symbols[2] = "SHIB";
        
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;

        vm.prank(owner);
        roundId = prediction.createRound(symbols, feeds, 1 days);
    }

    function _snapshotPrices(uint256 roundId, int64[] memory prices) internal {
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, prices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        prediction.snapshotStartPrices{value: fee}(roundId, updateData);
    }

    // ============================================
    // Round Creation Tests
    // ============================================

    function test_createRound_success() public {
        uint256 roundId = _createStandardRound();
        
        (
            string[] memory symbols,
            bytes32[] memory priceFeeds,
            ,
            ,
            uint256 deadline,
            uint256 totalPot,
            ,
            bool pricesSnapshotted,
            bool resolved,
            bool cancelled
        ) = prediction.getRound(roundId);

        assertEq(symbols.length, 3);
        assertEq(symbols[0], "PEPE");
        assertEq(priceFeeds[0], PEPE_FEED);
        assertEq(deadline, block.timestamp + 1 days);
        assertEq(totalPot, 0);
        assertFalse(pricesSnapshotted);
        assertFalse(resolved);
        assertFalse(cancelled);
    }

    function test_createRound_revert_notOwner() public {
        string[] memory symbols = new string[](2);
        bytes32[] memory feeds = new bytes32[](2);
        
        vm.prank(alice);
        vm.expectRevert();
        prediction.createRound(symbols, feeds, 1 days);
    }

    function test_createRound_revert_durationTooShort() public {
        string[] memory symbols = new string[](2);
        bytes32[] memory feeds = new bytes32[](2);
        
        vm.prank(owner);
        vm.expectRevert(MemePredictionTrustless.DurationTooShort.selector);
        prediction.createRound(symbols, feeds, 30 minutes);
    }

    function test_createRound_revert_needAtLeastTwoCoins() public {
        string[] memory symbols = new string[](1);
        bytes32[] memory feeds = new bytes32[](1);
        
        vm.prank(owner);
        vm.expectRevert(MemePredictionTrustless.NeedAtLeastTwoCoins.selector);
        prediction.createRound(symbols, feeds, 1 days);
    }

    function test_createRound_revert_arrayLengthMismatch() public {
        string[] memory symbols = new string[](3);
        bytes32[] memory feeds = new bytes32[](2);
        
        vm.prank(owner);
        vm.expectRevert(MemePredictionTrustless.ArrayLengthMismatch.selector);
        prediction.createRound(symbols, feeds, 1 days);
    }

    // ============================================
    // Price Snapshot Tests
    // ============================================

    function test_snapshotStartPrices_success() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory prices = new int64[](3);
        prices[0] = 100; // PEPE
        prices[1] = 200; // DOGE
        prices[2] = 50;  // SHIB
        
        _snapshotPrices(roundId, prices);
        
        (
            ,
            ,
            int64[] memory startPrices,
            ,
            ,
            ,
            ,
            bool pricesSnapshotted,
            ,
            
        ) = prediction.getRound(roundId);

        assertTrue(pricesSnapshotted);
        // Prices normalized to 18 decimals from -8 expo
        assertGt(startPrices[0], 0);
        assertGt(startPrices[1], 0);
        assertGt(startPrices[2], 0);
    }

    function test_snapshotStartPrices_revert_alreadySnapshotted() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory prices = new int64[](3);
        prices[0] = 100;
        prices[1] = 200;
        prices[2] = 50;
        
        _snapshotPrices(roundId, prices);
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, prices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.expectRevert(MemePredictionTrustless.PriceNotSnapshotted.selector);
        prediction.snapshotStartPrices{value: fee}(roundId, updateData);
    }

    // ============================================
    // Wager Tests
    // ============================================

    function test_placeWager_success() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0); // Bet on PEPE
        
        (uint256 coinIndex, uint256 amount, bool claimed, bool refunded) = prediction.getWager(roundId, alice);
        
        assertEq(coinIndex, 0);
        assertEq(amount, 1 ether);
        assertFalse(claimed);
        assertFalse(refunded);
        assertEq(prediction.getCoinTotal(roundId, 0), 1 ether);
    }

    function test_placeWager_multipleOnSameCoin() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        vm.prank(alice);
        prediction.placeWager{value: 0.5 ether}(roundId, 0);
        
        (, uint256 amount,,) = prediction.getWager(roundId, alice);
        assertEq(amount, 1.5 ether);
    }

    function test_placeWager_revert_differentCoin() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        vm.prank(alice);
        vm.expectRevert(MemePredictionTrustless.InvalidCoinIndex.selector);
        prediction.placeWager{value: 1 ether}(roundId, 1);
    }

    function test_placeWager_revert_insufficientWager() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        vm.expectRevert(MemePredictionTrustless.InsufficientWager.selector);
        prediction.placeWager{value: 0.0001 ether}(roundId, 0);
    }

    function test_placeWager_revert_bettingClosed() public {
        uint256 roundId = _createStandardRound();
        
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(alice);
        vm.expectRevert(MemePredictionTrustless.BettingClosed.selector);
        prediction.placeWager{value: 1 ether}(roundId, 0);
    }

    // ============================================
    // Resolution Tests (The Key Trustless Feature!)
    // ============================================

    function test_resolveRound_winnerByPercentGain() public {
        uint256 roundId = _createStandardRound();
        
        // Snapshot starting prices
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100; // PEPE starts at 100
        startPrices[1] = 200; // DOGE starts at 200
        startPrices[2] = 50;  // SHIB starts at 50
        _snapshotPrices(roundId, startPrices);
        
        // Place bets
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0); // PEPE
        
        vm.prank(bob);
        prediction.placeWager{value: 1 ether}(roundId, 1); // DOGE
        
        vm.prank(charlie);
        prediction.placeWager{value: 1 ether}(roundId, 2); // SHIB
        
        // Skip to after deadline
        vm.warp(block.timestamp + 2 days);
        
        // End prices: PEPE +50%, DOGE +25%, SHIB +10%
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 150; // PEPE: +50%
        endPrices[1] = 250; // DOGE: +25%
        endPrices[2] = 55;  // SHIB: +10%
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        // ANYONE can resolve - no admin involvement!
        vm.prank(resolver);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        // Verify PEPE won (highest % gain)
        (,,,,,, uint256 winningCoinIndex,, bool resolved,) = prediction.getRound(roundId);
        assertTrue(resolved);
        assertEq(winningCoinIndex, 0); // PEPE index
    }

    function test_resolveRound_winnerBySmallestLoss() public {
        uint256 roundId = _createStandardRound();
        
        // Snapshot starting prices
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100;
        startPrices[1] = 200;
        startPrices[2] = 50;
        _snapshotPrices(roundId, startPrices);
        
        // Place bets
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        vm.prank(bob);
        prediction.placeWager{value: 1 ether}(roundId, 1);
        
        vm.prank(charlie);
        prediction.placeWager{value: 1 ether}(roundId, 2);
        
        vm.warp(block.timestamp + 2 days);
        
        // End prices: ALL DOWN, but DOGE down least (-10% vs -20% vs -30%)
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 80;  // PEPE: -20%
        endPrices[1] = 180; // DOGE: -10% (WINNER - smallest loss)
        endPrices[2] = 35;  // SHIB: -30%
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.prank(resolver);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        (,,,,,, uint256 winningCoinIndex,, bool resolved,) = prediction.getRound(roundId);
        assertTrue(resolved);
        assertEq(winningCoinIndex, 1); // DOGE (smallest loss)
    }

    function test_resolveRound_anyoneCanCall() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100;
        startPrices[1] = 200;
        startPrices[2] = 50;
        _snapshotPrices(roundId, startPrices);
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        vm.warp(block.timestamp + 2 days);
        
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 150;
        endPrices[1] = 200;
        endPrices[2] = 50;
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        // Random person can resolve - NOT just owner!
        address randomPerson = makeAddr("random");
        vm.deal(randomPerson, 1 ether);
        
        vm.prank(randomPerson);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        (,,,,,,,, bool resolved,) = prediction.getRound(roundId);
        assertTrue(resolved);
    }

    function test_resolveRound_revert_bettingStillOpen() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory prices = new int64[](3);
        prices[0] = 100;
        prices[1] = 200;
        prices[2] = 50;
        _snapshotPrices(roundId, prices);
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, prices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.prank(resolver);
        vm.expectRevert(MemePredictionTrustless.BettingStillOpen.selector);
        prediction.resolveRound{value: fee}(roundId, updateData);
    }

    function test_resolveRound_revert_notSnapshotted() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        vm.warp(block.timestamp + 2 days);
        
        int64[] memory prices = new int64[](3);
        prices[0] = 100;
        prices[1] = 200;
        prices[2] = 50;
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, prices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.prank(resolver);
        vm.expectRevert(MemePredictionTrustless.PriceNotSnapshotted.selector);
        prediction.resolveRound{value: fee}(roundId, updateData);
    }

    // ============================================
    // Claim Tests
    // ============================================

    function test_claimWinnings_success() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100;
        startPrices[1] = 200;
        startPrices[2] = 50;
        _snapshotPrices(roundId, startPrices);
        
        vm.prank(alice);
        prediction.placeWager{value: 2 ether}(roundId, 0); // PEPE
        
        vm.prank(bob);
        prediction.placeWager{value: 1 ether}(roundId, 1); // DOGE
        
        vm.warp(block.timestamp + 2 days);
        
        // PEPE wins with +50%
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 150;
        endPrices[1] = 200;
        endPrices[2] = 50;
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.prank(resolver);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        uint256 aliceBalanceBefore = alice.balance;
        
        vm.prank(alice);
        prediction.claimWinnings(roundId);
        
        // Alice should get pot minus 5% fee
        // Total pot = 3 ETH, fee = 0.15 ETH, remaining = 2.85 ETH
        // Alice wagered 2 ETH on PEPE, only winner
        uint256 expectedWinnings = 2.85 ether;
        assertEq(alice.balance - aliceBalanceBefore, expectedWinnings);
    }

    function test_claimWinnings_revert_loser() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100;
        startPrices[1] = 200;
        startPrices[2] = 50;
        _snapshotPrices(roundId, startPrices);
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        vm.prank(bob);
        prediction.placeWager{value: 1 ether}(roundId, 1);
        
        vm.warp(block.timestamp + 2 days);
        
        // PEPE wins
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 150;
        endPrices[1] = 200;
        endPrices[2] = 50;
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.prank(resolver);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        // Bob bet on DOGE which lost
        vm.prank(bob);
        vm.expectRevert(MemePredictionTrustless.NoWinnings.selector);
        prediction.claimWinnings(roundId);
    }

    // ============================================
    // Emergency Refund Tests
    // ============================================

    function test_emergencyRefund_afterTimeout() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        // Skip past deadline + refund timeout (7 days)
        vm.warp(block.timestamp + 1 days + 7 days + 1);
        
        uint256 aliceBalanceBefore = alice.balance;
        
        vm.prank(alice);
        prediction.emergencyRefund(roundId);
        
        assertEq(alice.balance - aliceBalanceBefore, 1 ether);
    }

    function test_emergencyRefund_afterCancellation() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        // Admin cancels round
        vm.prank(owner);
        prediction.cancelRound(roundId);
        
        uint256 aliceBalanceBefore = alice.balance;
        
        // Immediate refund after cancellation (no timeout wait)
        vm.prank(alice);
        prediction.emergencyRefund(roundId);
        
        assertEq(alice.balance - aliceBalanceBefore, 1 ether);
    }

    function test_emergencyRefund_revert_tooEarly() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(alice);
        prediction.placeWager{value: 1 ether}(roundId, 0);
        
        // Skip to just after deadline but before timeout
        vm.warp(block.timestamp + 1 days + 1);
        
        vm.prank(alice);
        vm.expectRevert(MemePredictionTrustless.RefundTooEarly.selector);
        prediction.emergencyRefund(roundId);
    }

    // ============================================
    // Edge Cases
    // ============================================

    function test_noBettorsOnWinningCoin_fallbackToNextBest() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100;
        startPrices[1] = 200;
        startPrices[2] = 50;
        _snapshotPrices(roundId, startPrices);
        
        // Only bet on DOGE (index 1), no one bets on PEPE (index 0)
        vm.prank(bob);
        prediction.placeWager{value: 1 ether}(roundId, 1);
        
        vm.warp(block.timestamp + 2 days);
        
        // PEPE has highest gain, but no one bet on it
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 200; // PEPE: +100% (but no bettors!)
        endPrices[1] = 250; // DOGE: +25% (has bettors - should win)
        endPrices[2] = 40;  // SHIB: -20%
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        vm.prank(resolver);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        // DOGE should win (best performer WITH bettors)
        (,,,,,, uint256 winningCoinIndex,, bool resolved,) = prediction.getRound(roundId);
        assertTrue(resolved);
        assertEq(winningCoinIndex, 1); // DOGE
    }

    function test_feeCollection() public {
        uint256 roundId = _createStandardRound();
        
        int64[] memory startPrices = new int64[](3);
        startPrices[0] = 100;
        startPrices[1] = 200;
        startPrices[2] = 50;
        _snapshotPrices(roundId, startPrices);
        
        vm.prank(alice);
        prediction.placeWager{value: 10 ether}(roundId, 0);
        
        vm.warp(block.timestamp + 2 days);
        
        int64[] memory endPrices = new int64[](3);
        endPrices[0] = 150;
        endPrices[1] = 200;
        endPrices[2] = 50;
        
        bytes32[] memory feeds = new bytes32[](3);
        feeds[0] = PEPE_FEED;
        feeds[1] = DOGE_FEED;
        feeds[2] = SHIB_FEED;
        bytes[] memory updateData = _createMultiPriceUpdate(feeds, endPrices, -8);
        uint256 fee = prediction.getUpdateFee(updateData);
        
        uint256 feeRecipientBalanceBefore = feeRecipient.balance;
        
        vm.prank(resolver);
        prediction.resolveRound{value: fee}(roundId, updateData);
        
        // 5% fee on 10 ETH = 0.5 ETH
        assertEq(feeRecipient.balance - feeRecipientBalanceBefore, 0.5 ether);
    }

    // ============================================
    // Admin Function Tests
    // ============================================

    function test_setFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        
        vm.prank(owner);
        prediction.setFeeRecipient(newRecipient);
        
        assertEq(prediction.feeRecipient(), newRecipient);
    }

    function test_setFeeRecipient_revert_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MemePredictionTrustless.ZeroAddress.selector);
        prediction.setFeeRecipient(address(0));
    }

    function test_cancelRound() public {
        uint256 roundId = _createStandardRound();
        
        vm.prank(owner);
        prediction.cancelRound(roundId);
        
        (,,,,,,,,, bool cancelled) = prediction.getRound(roundId);
        assertTrue(cancelled);
    }

    function test_renounceOwnership_reverts() public {
        vm.prank(owner);
        vm.expectRevert(MemePredictionTrustless.ZeroAddress.selector);
        prediction.renounceOwnership();
    }
}
