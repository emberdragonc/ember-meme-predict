// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PullPayment
/// @author Ember 🐉
/// @notice Abstract contract implementing pull payment pattern for DoS-resistant fund distribution
/// @dev Inherit this contract to safely distribute ETH to multiple recipients
abstract contract PullPayment is ReentrancyGuard {
    // ============ Errors ============
    error NothingToWithdraw();
    error TransferFailed();
    error ZeroAddress();
    error ZeroAmount();

    // ============ Events ============
    event PaymentAllocated(address indexed payee, uint256 amount);
    event PaymentWithdrawn(address indexed payee, uint256 amount);

    // ============ Storage ============
    /// @notice Pending withdrawals for each address
    mapping(address => uint256) public pendingWithdrawals;

    /// @notice Total amount pending withdrawal
    uint256 public totalPending;

    // ============ External Functions ============

    /// @notice Withdraw all pending payments
    /// @dev Uses CEI pattern and reentrancy guard
    function withdrawPayments() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];

        if (amount == 0) revert NothingToWithdraw();

        // Effects: Update state before interaction
        pendingWithdrawals[msg.sender] = 0;
        totalPending -= amount;

        // Interaction: Transfer ETH
        (bool success,) = msg.sender.call{ value: amount }("");
        if (!success) revert TransferFailed();

        emit PaymentWithdrawn(msg.sender, amount);
    }

    /// @notice Withdraw payments to a specific address
    /// @param payee The address to withdraw to
    /// @dev Allows withdrawal on behalf of others (gas sponsorship)
    function withdrawPaymentsTo(address payable payee) external nonReentrant {
        if (payee == address(0)) revert ZeroAddress();

        uint256 amount = pendingWithdrawals[payee];

        if (amount == 0) revert NothingToWithdraw();

        // Effects
        pendingWithdrawals[payee] = 0;
        totalPending -= amount;

        // Interaction
        (bool success,) = payee.call{ value: amount }("");
        if (!success) revert TransferFailed();

        emit PaymentWithdrawn(payee, amount);
    }

    // ============ Internal Functions ============

    /// @notice Allocate payment to an address for later withdrawal
    /// @param payee The address to allocate payment to
    /// @param amount The amount to allocate
    function _allocatePayment(address payee, uint256 amount) internal {
        if (payee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        pendingWithdrawals[payee] += amount;
        totalPending += amount;

        emit PaymentAllocated(payee, amount);
    }

    /// @notice Allocate payments to multiple addresses
    /// @param payees Array of addresses
    /// @param amounts Array of amounts
    /// @dev Arrays must be same length
    function _allocatePaymentsBatch(address[] calldata payees, uint256[] calldata amounts) internal {
        require(payees.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < payees.length; i++) {
            _allocatePayment(payees[i], amounts[i]);
        }
    }

    // ============ View Functions ============

    /// @notice Get pending withdrawal for an address
    /// @param payee The address to check
    /// @return The pending amount
    function pendingPayment(address payee) external view returns (uint256) {
        return pendingWithdrawals[payee];
    }

    /// @notice Check if contract has sufficient balance for all pending
    /// @return True if solvent
    function isSolvent() external view returns (bool) {
        return address(this).balance >= totalPending;
    }
}

/// @title ERC20PullPayment
/// @notice Pull payment pattern for ERC20 tokens
/// @dev Same pattern but for token distributions
abstract contract ERC20PullPayment is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Errors ============
    error NothingToWithdraw();
    error ZeroAddress();
    error ZeroAmount();

    // ============ Events ============
    event TokenPaymentAllocated(address indexed token, address indexed payee, uint256 amount);
    event TokenPaymentWithdrawn(address indexed token, address indexed payee, uint256 amount);

    // ============ Storage ============
    /// @notice token => payee => amount
    mapping(address => mapping(address => uint256)) public pendingTokenWithdrawals;

    // ============ External Functions ============

    /// @notice Withdraw pending token payment
    /// @param token The token to withdraw
    function withdrawTokenPayment(address token) external nonReentrant {
        uint256 amount = pendingTokenWithdrawals[token][msg.sender];

        if (amount == 0) revert NothingToWithdraw();

        pendingTokenWithdrawals[token][msg.sender] = 0;

        IERC20(token).safeTransfer(msg.sender, amount);

        emit TokenPaymentWithdrawn(token, msg.sender, amount);
    }

    // ============ Internal Functions ============

    /// @notice Allocate token payment
    /// @param token The token address
    /// @param payee The recipient
    /// @param amount The amount to allocate
    function _allocateTokenPayment(address token, address payee, uint256 amount) internal {
        if (payee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        pendingTokenWithdrawals[token][payee] += amount;

        emit TokenPaymentAllocated(token, payee, amount);
    }
}
