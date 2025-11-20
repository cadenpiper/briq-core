// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Errors
 * @author Briq Protocol
 * @notice Library containing all custom error definitions for the Briq Protocol
 * @dev This library centralizes all custom errors used throughout the protocol
 *      for consistent error handling and gas optimization. Custom errors are
 *      more gas-efficient than require statements with string messages.
 * 
 * Benefits:
 * - Gas optimization through custom errors
 * - Centralized error management
 * - Consistent error handling across contracts
 * - Better debugging and monitoring capabilities
 */
library Errors {
    
    /**
     * @notice Thrown when an invalid address (typically zero address) is provided
     * @dev Used across multiple contracts when validating address parameters
     */
    error InvalidAddress();
    
    /**
     * @notice Thrown when attempting to change token support to the same status
     * @dev Used in strategy contracts when token support status is unchanged
     */
    error TokenSupportUnchanged();
    
    /**
     * @notice Thrown when attempting to change pool support to the same status
     * @dev Used in strategy contracts when pool/market support status is unchanged
     */
    error PoolSupportUnchanged();
    
    /**
     * @notice Thrown when a token has no associated pool or market configured
     * @dev Used when operations require a pool/market but none is configured
     */
    error NoPoolForToken();
    
    /**
     * @notice Thrown when an invalid amount (typically zero) is provided
     * @dev Used for deposit/withdraw operations that require non-zero amounts
     */
    error InvalidAmount();
    
    /**
     * @notice Thrown when invalid shares amount is provided for operations
     * @dev Used in vault operations when share calculations or validations fail
     */
    error InvalidShares();
    
    /**
     * @notice Thrown when attempting operations with unsupported tokens
     * @dev Used across strategies and coordinator when token is not supported
     */
    error UnsupportedToken();
    
    /**
     * @notice Thrown when a token is not supported by a specific pool/market
     * @dev Used when validating token compatibility with DeFi protocols
     */
    error UnsupportedTokenForPool();
    
    /**
     * @notice Thrown when withdrawal operations fail to retrieve expected amounts
     * @dev Used in strategy contracts when withdrawal amounts don't match expectations
     */
    error InsufficientWithdrawal();
    
    /**
     * @notice Thrown when non-vault addresses attempt vault-only operations
     * @dev Used in coordinator to restrict access to vault-only functions
     */
    error OnlyVault();
    
    /**
     * @notice Thrown when unauthorized addresses attempt restricted operations
     * @dev Used for access control in strategy management functions
     */
    error UnauthorizedAccess();
    
    /**
     * @notice Thrown when attempting to set coordinator to the same address
     * @dev Used in strategy contracts when coordinator address is unchanged
     */
    error SameCoordinator();
    
    /**
     * @notice Thrown when attempting to activate an already active strategy
     * @dev Reserved for future strategy management features
     */
    error StrategyAlreadyActive();
    
    /**
     * @notice Thrown when attempting operations on inactive strategies
     * @dev Reserved for future strategy management features
     */
    error StrategyNotActive();
    
    /**
     * @notice Thrown when invalid strategy pair configurations are detected
     * @dev Reserved for future multi-strategy coordination features
     */
    error InvalidStrategyPair();
    
    /**
     * @notice Thrown when a price feed is not found for a token
     * @dev Used in PriceFeedManager when requesting price for unsupported token
     */
    error PriceFeedNotFound();
    
    /**
     * @notice Thrown when price feed returns invalid price (zero or negative)
     * @dev Used in PriceFeedManager when Chainlink returns invalid price data
     */
    error InvalidPrice();
    
    /**
     * @notice Thrown when price feed data is too old/stale
     * @dev Used in PriceFeedManager when price data exceeds staleness threshold
     */
    error StalePrice();
    
    /**
     * @notice Thrown when vault has insufficient liquidity for operations
     * @dev Used in vault when total USD value is zero or insufficient for withdrawals
     */
    error InsufficientLiquidity();
}
