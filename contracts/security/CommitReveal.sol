// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CommitReveal
/// @author Ember 🐉
/// @notice Abstract contract implementing commit-reveal scheme for frontrunning protection
/// @dev Inherit this contract and use onlyRevealed modifier on functions that need protection
abstract contract CommitReveal {
    // ============ Errors ============
    error NoCommitFound();
    error RevealTooEarly();
    error RevealTooLate();
    error InvalidReveal();
    error AlreadyCommitted();

    // ============ Events ============
    event Committed(address indexed user, bytes32 indexed commitHash, uint256 timestamp);
    event Revealed(address indexed user, uint256 timestamp);
    event CommitCancelled(address indexed user);

    // ============ Storage ============
    mapping(address => bytes32) public commits;
    mapping(address => uint256) public commitTimestamps;

    // ============ Constants ============
    /// @notice Minimum time between commit and reveal (prevents same-block reveal)
    uint256 public constant MIN_REVEAL_DELAY = 1 minutes;

    /// @notice Maximum time to reveal after commit (prevents stale commits)
    uint256 public constant MAX_REVEAL_WINDOW = 24 hours;

    // ============ External Functions ============

    /// @notice Commit a hash for later reveal
    /// @param hash The keccak256 hash of (secret, msg.sender)
    /// @dev User computes: keccak256(abi.encodePacked(secret, userAddress))
    function commit(bytes32 hash) external virtual {
        if (commits[msg.sender] != bytes32(0)) revert AlreadyCommitted();

        commits[msg.sender] = hash;
        commitTimestamps[msg.sender] = block.timestamp;

        emit Committed(msg.sender, hash, block.timestamp);
    }

    /// @notice Cancel an existing commit
    /// @dev Useful if user wants to change their commitment
    function cancelCommit() external virtual {
        if (commits[msg.sender] == bytes32(0)) revert NoCommitFound();

        delete commits[msg.sender];
        delete commitTimestamps[msg.sender];

        emit CommitCancelled(msg.sender);
    }

    // ============ Modifiers ============

    /// @notice Modifier to verify a reveal matches a previous commit
    /// @param secret The secret that was hashed in the commit
    modifier onlyRevealed(bytes32 secret) {
        _verifyReveal(secret);
        _;
    }

    // ============ Internal Functions ============

    /// @notice Internal function to verify reveal
    /// @param secret The secret that was hashed in the commit
    function _verifyReveal(bytes32 secret) internal {
        bytes32 storedCommit = commits[msg.sender];
        uint256 commitTime = commitTimestamps[msg.sender];

        // Check commit exists
        if (storedCommit == bytes32(0)) revert NoCommitFound();

        // Check timing
        uint256 elapsed = block.timestamp - commitTime;
        if (elapsed < MIN_REVEAL_DELAY) revert RevealTooEarly();
        if (elapsed > MAX_REVEAL_WINDOW) revert RevealTooLate();

        // Verify the reveal matches the commit
        bytes32 expectedHash = keccak256(abi.encodePacked(secret, msg.sender));
        if (storedCommit != expectedHash) revert InvalidReveal();

        // Clear the commit (single use)
        delete commits[msg.sender];
        delete commitTimestamps[msg.sender];

        emit Revealed(msg.sender, block.timestamp);
    }

    /// @notice Check if an address has an active commit
    /// @param user The address to check
    /// @return hasCommit Whether the user has an active commit
    /// @return canReveal Whether the user can currently reveal
    function getCommitStatus(address user) external view returns (bool hasCommit, bool canReveal) {
        hasCommit = commits[user] != bytes32(0);

        if (hasCommit) {
            uint256 elapsed = block.timestamp - commitTimestamps[user];
            canReveal = elapsed >= MIN_REVEAL_DELAY && elapsed <= MAX_REVEAL_WINDOW;
        }
    }

    /// @notice Helper to compute commit hash off-chain
    /// @param secret The secret value
    /// @param user The user address
    /// @return The hash to use in commit()
    function computeCommitHash(bytes32 secret, address user) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(secret, user));
    }
}
