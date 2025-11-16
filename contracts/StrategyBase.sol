// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title StrategyBase
 * @author Briq Protocol
 * @notice Abstract base contract defining the interface for yield generation strategies
 * @dev This contract establishes the standard interface that all strategy implementations
 *      must follow. It ensures consistent interaction patterns between the StrategyCoordinator
 *      and various DeFi protocol integrations (Aave, Compound, etc.).
 * 
 * Key Features:
 * - Standardized interface for all strategy implementations
 * - Coordinator-only access control for core functions
 * - Abstract functions that must be implemented by derived contracts
 * 
 * Security Features:
 * - onlyCoordinator modifier for access control
 * - Abstract design prevents direct deployment
 */
abstract contract StrategyBase {
    
    // Custom Errors
    error OnlyCoordinator();
    
    /// @notice Address of the StrategyCoordinator contract authorized to call strategy functions
    address public coordinator;

    /**
     * @notice Restricts function access to the StrategyCoordinator contract only
     * @dev This modifier ensures that only the authorized coordinator can execute
     *      strategy operations, maintaining proper access control in the system.
     */
    modifier onlyCoordinator() {
        if (msg.sender != coordinator) revert OnlyCoordinator();
        _;
    }

    /**
     * @notice Sets the coordinator address for this strategy
     * @dev This function must be implemented by derived contracts to establish
     *      the relationship with the StrategyCoordinator. Should include proper
     *      access control and validation.
     * 
     * @param _coordinator Address of the StrategyCoordinator contract
     * 
     * Requirements (to be enforced by implementations):
     * - Coordinator address should not be zero
     * - Should have proper access control (onlyOwner)
     * - Should emit appropriate events
     */
    function setCoordinator(address _coordinator) external virtual;

    /**
     * @notice Deposits tokens into the underlying DeFi protocol
     * @dev This function must be implemented by derived contracts to handle
     *      token deposits into their respective protocols (Aave, Compound, etc.).
     *      Should include proper validation and error handling.
     * 
     * @param _token Address of the token to deposit
     * @param _amount Amount of tokens to deposit
     * 
     * Requirements (to be enforced by implementations):
     * - Only coordinator can call this function
     * - Token must be supported by the strategy
     * - Amount must be greater than 0
     * - Should handle token transfers and protocol interactions
     */
    function deposit(address _token, uint256 _amount) external virtual;

    /**
     * @notice Withdraws tokens from the underlying DeFi protocol
     * @dev This function must be implemented by derived contracts to handle
     *      token withdrawals from their respective protocols. Should handle
     *      partial withdrawals and return tokens to the coordinator.
     * 
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     * 
     * Requirements (to be enforced by implementations):
     * - Only coordinator can call this function
     * - Token must be supported by the strategy
     * - Amount must be greater than 0
     * - Strategy must have sufficient balance
     * - Should handle protocol interactions and token transfers
     */
    function withdraw(address _token, uint256 _amount) external virtual;

    /**
     * @notice Returns the current balance of a token in this strategy
     * @dev This function must be implemented by derived contracts to return
     *      the current balance of tokens deployed in their respective protocols.
     *      Used by the coordinator for balance tracking and withdrawal calculations.
     * 
     * @param _token Address of the token to check balance for
     * @return Current balance of the token in this strategy
     * 
     * Implementation Notes:
     * - Should return the actual balance in the underlying protocol
     * - For interest-bearing tokens, should return the current redeemable amount
     * - Should return 0 for unsupported tokens
     */
    function balanceOf(address _token) external view virtual returns (uint256);

    /**
     * @notice Returns the current APY for a supported token
     * @dev This function must be implemented by derived contracts to return
     *      the current annual percentage yield for tokens in their respective protocols.
     *      Used by the frontend to display real-time yield information to users.
     * 
     * @param _token Address of the token to get APY for
     * @return apy Current annual percentage yield in basis points (e.g., 500 = 5.00%)
     * 
     * Implementation Notes:
     * - Should return APY in basis points for consistency (1% = 100 basis points)
     * - Should fetch real-time rates from the underlying protocol
     * - Should return 0 for unsupported tokens
     * - Should handle rate conversions from protocol-specific formats
     */
    function getCurrentAPY(address _token) external view virtual returns (uint256 apy);
}
