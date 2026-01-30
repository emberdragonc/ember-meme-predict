// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/security/CommitReveal.sol";

contract CommitRevealImpl is CommitReveal {
    uint256 public lastRevealedSecret;

    function doSomething(bytes32 secret) external onlyRevealed(secret) {
        lastRevealedSecret = uint256(secret);
    }
}

contract CommitRevealTest is Test {
    CommitRevealImpl public target;
    address public user = address(0x1);
    bytes32 public secret = keccak256("my secret");

    function setUp() public {
        target = new CommitRevealImpl();
    }

    function testCommit() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        vm.prank(user);
        target.commit(hash);

        assertEq(target.commits(user), hash);
        assertGt(target.commitTimestamps(user), 0);
    }

    function testCannotRevealTooEarly() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        vm.prank(user);
        target.commit(hash);

        // Try to reveal immediately (should fail)
        vm.prank(user);
        vm.expectRevert(CommitReveal.RevealTooEarly.selector);
        target.doSomething(secret);
    }

    function testSuccessfulReveal() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        vm.prank(user);
        target.commit(hash);

        // Wait for MIN_REVEAL_DELAY
        vm.warp(block.timestamp + target.MIN_REVEAL_DELAY() + 1);

        // Now reveal should work
        vm.prank(user);
        target.doSomething(secret);

        assertEq(target.lastRevealedSecret(), uint256(secret));

        // Commit should be cleared
        assertEq(target.commits(user), bytes32(0));
    }

    function testCannotRevealTooLate() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        vm.prank(user);
        target.commit(hash);

        // Wait past MAX_REVEAL_WINDOW
        vm.warp(block.timestamp + target.MAX_REVEAL_WINDOW() + 1);

        vm.prank(user);
        vm.expectRevert(CommitReveal.RevealTooLate.selector);
        target.doSomething(secret);
    }

    function testInvalidReveal() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        vm.prank(user);
        target.commit(hash);

        vm.warp(block.timestamp + target.MIN_REVEAL_DELAY() + 1);

        // Try with wrong secret
        bytes32 wrongSecret = keccak256("wrong secret");
        vm.prank(user);
        vm.expectRevert(CommitReveal.InvalidReveal.selector);
        target.doSomething(wrongSecret);
    }

    function testCancelCommit() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        vm.prank(user);
        target.commit(hash);

        vm.prank(user);
        target.cancelCommit();

        assertEq(target.commits(user), bytes32(0));
    }

    function testGetCommitStatus() public {
        bytes32 hash = target.computeCommitHash(secret, user);

        // No commit yet
        (bool hasCommit, bool canReveal) = target.getCommitStatus(user);
        assertFalse(hasCommit);
        assertFalse(canReveal);

        // After commit
        vm.prank(user);
        target.commit(hash);

        (hasCommit, canReveal) = target.getCommitStatus(user);
        assertTrue(hasCommit);
        assertFalse(canReveal); // Too early

        // After delay
        vm.warp(block.timestamp + target.MIN_REVEAL_DELAY() + 1);

        (hasCommit, canReveal) = target.getCommitStatus(user);
        assertTrue(hasCommit);
        assertTrue(canReveal);
    }
}
