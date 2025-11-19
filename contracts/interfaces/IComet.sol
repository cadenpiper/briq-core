// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IComet
 * @author Briq Protocol
 * @notice Interface for Compound V3 (Comet) lending protocol integration
 * @dev This interface defines the essential functions needed to interact with
 *      Compound V3 Comet markets for lending and borrowing operations. It provides
 *      a simplified interface focusing on the core functionality required by the
 *      Briq Protocol strategies.
 * 
 * Compound V3 Overview:
 * - Comet markets are isolated lending pools for specific base assets
 * - Each market has one base asset (e.g., USDC, WETH) that can be supplied/borrowed
 * - Suppliers earn interest on their base asset deposits
 * - Interest rates are determined algorithmically based on utilization
 * 
 * Integration Notes:
 * - Used by StrategyCompoundComet for yield generation
 * - Focuses on supply-side operations (lending) for yield
 * - Balances automatically accrue interest over time
 */
interface IComet {
    
    /**
     * @notice Supplies base assets to the Comet market to earn interest
     * @dev Transfers tokens from the caller to the Comet market and starts
     *      earning interest immediately. The caller's balance in the market
     *      increases and begins accruing interest.
     * 
     * @param asset Address of the asset to supply (must be the base asset)
     * @param amount Amount of the asset to supply
     * 
     * Requirements:
     * - Caller must have approved Comet to spend the tokens
     * - Asset must be the base asset for this Comet market
     * - Amount must be greater than 0
     * 
     * Effects:
     * - Transfers tokens from caller to Comet
     * - Increases caller's supply balance in the market
     * - Starts earning interest on the supplied amount
     */
    function supply(address asset, uint amount) external;
    
    /**
     * @notice Withdraws base assets from the Comet market
     * @dev Withdraws the specified amount of base assets from the caller's
     *      supply balance, including any accrued interest. The withdrawn
     *      amount is transferred to the caller.
     * 
     * @param asset Address of the asset to withdraw (must be the base asset)
     * @param amount Amount of the asset to withdraw
     * 
     * Requirements:
     * - Caller must have sufficient supply balance in the market
     * - Asset must be the base asset for this Comet market
     * - Amount must be greater than 0
     * 
     * Effects:
     * - Decreases caller's supply balance in the market
     * - Transfers tokens from Comet to the caller
     * - Stops earning interest on the withdrawn amount
     */
    function withdraw(address asset, uint amount) external;
    
    /**
     * @notice Returns the current supply balance of an account in the market
     * @dev Returns the account's current supply balance including accrued interest.
     *      This balance represents the total amount that can be withdrawn.
     * 
     * @param account Address of the account to check balance for
     * @return Current supply balance including accrued interest
     * 
     * Notes:
     * - Balance automatically increases over time due to interest accrual
     * - Represents the total withdrawable amount for the account
     * - Updated in real-time based on current interest rates
     */
    function balanceOf(address account) external view returns (uint256);
    
    /**
     * @notice Returns the base asset address for this Comet market
     * @dev Each Comet market has one base asset that can be supplied and borrowed
     * @return Address of the base asset token for this market
     */
    function baseToken() external view returns (address);

    /**
     * @notice Returns the current protocol utilization of the base asset
     * @dev Utilization = TotalBorrows / TotalSupply
     * @return The current utilization percentage scaled up by 10^18 (e.g. 1e17 = 10%)
     */
    function getUtilization() external view returns (uint256);

    /**
     * @notice Returns the per second supply rate for a given utilization
     * @dev Rate is per second and scaled up by 10^18
     * @param utilization The utilization at which to calculate the rate (scaled by 10^18)
     * @return The per second supply rate scaled up by 10^18
     */
    function getSupplyRate(uint256 utilization) external view returns (uint64);

    /**
     * @notice Returns the amount of reward token accrued for an account
     * @dev Returns the amount of protocol reward tokens (like COMP) that have
     *      accrued based on the account's usage of the base asset within the protocol.
     *      The returned value is scaled up by 10^6 for precision.
     * 
     * @param account Address of the account to check rewards for
     * @return Amount of reward token accrued, scaled up by 10^6
     * 
     * Notes:
     * - Rewards accrue based on supply and borrow activity
     * - Value is scaled by 10^6 for precision (divide by 1e6 for actual amount)
     * - Used in conjunction with CometRewards contract for claiming
     */
    function baseTrackingAccrued(address account) external view returns (uint64);
}
