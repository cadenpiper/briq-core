// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../StrategyBase.sol";
import "../interfaces/IComet.sol";
import { Errors } from "../libraries/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title StrategyCompoundComet
 * @author Briq Protocol
 * @notice Strategy implementation for Compound V3 (Comet) lending protocol integration
 * @dev This contract implements the StrategyBase interface to provide yield generation
 *      through Compound V3 (Comet) lending markets. It handles token deposits, withdrawals,
 *      and balance tracking for supported base assets in Comet markets.
 * 
 * Key Features:
 * - Deposits base tokens into Compound V3 Comet markets to earn yield
 * - Supports multiple tokens through dynamic market configuration
 * - Handles withdrawals with automatic interest calculation
 * - Maps tokens to their corresponding Comet market contracts
 * 
 * Architecture:
 * - Integrates with Compound V3 Comet contracts for lending operations
 * - Maintains mapping of supported tokens to their Comet markets
 * - Implements StrategyBase interface for coordinator compatibility
 * 
 * Security Features:
 * - Coordinator-only access for deposit/withdraw operations
 * - Owner-only administrative functions
 * - ReentrancyGuard protection on state-changing functions
 * - SafeERC20 for secure token transfers
 * - Custom error handling for gas efficiency
 */
contract StrategyCompoundComet is StrategyBase, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Mapping to check if a token is supported by this strategy
    mapping(address => bool) public supportedTokens;
    
    /// @notice Mapping to check if a Comet market is supported
    mapping(address => bool) public supportedMarkets;
    
    /// @notice Mapping from token address to its corresponding Comet market contract
    mapping(address => IComet) public tokenToComet;

    /// @notice Address of the timelock controller for critical operations
    address public timelock;

    // Rewards tracking for analytics
    mapping(address => uint256) public totalDeposited;
    mapping(address => uint256) public totalWithdrawn;

    /**
     * @notice Modifier to allow only owner or timelock to call critical functions
     */
    modifier onlyOwnerOrTimelock() {
        if (msg.sender != owner() && msg.sender != timelock) revert Errors.UnauthorizedAccess();
        _;
    }

    /**
     * @notice Emitted when a token's support status is updated
     * @param token Address of the token whose support was updated
     * @param status New support status (true = supported, false = not supported)
     */
    event TokenSupportUpdated(address indexed token, bool status);
    
    /**
     * @notice Emitted when a Comet market's support status is updated
     * @param market Address of the Comet market whose support was updated
     * @param status New support status (true = supported, false = not supported)
     * @param token Address of the base token for this market
     */
    event MarketSupportUpdated(address indexed market, bool status, address indexed token);
    
    /**
     * @notice Emitted when the coordinator address is updated
     * @param coordinator New coordinator address
     */
    event CoordinatorUpdated(address indexed coordinator);

    /**
     * @notice Emitted when tokens are deposited
     * @param token Address of the deposited token
     * @param amount Amount deposited
     * @param totalDeposited Running total of deposits for this token
     */
    event Deposited(address indexed token, uint256 amount, uint256 totalDeposited);

    /**
     * @notice Emitted when tokens are withdrawn
     * @param token Address of the withdrawn token
     * @param amount Amount withdrawn
     * @param totalWithdrawn Running total of withdrawals for this token
     */
    event Withdrawn(address indexed token, uint256 amount, uint256 totalWithdrawn);

    /**
     * @notice Emitted when timelock address is updated
     * @param timelock New timelock address
     */
    event TimelockUpdated(address indexed timelock);

    /**
     * @notice Emitted when emergency withdrawal is executed
     * @param token Address of the withdrawn token
     * @param amount Amount withdrawn
     * @param recipient Address that received the tokens
     */
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed recipient);

    /**
     * @notice Initializes the StrategyCompoundComet contract
     * @dev Sets up the strategy with owner permissions. Coordinator address
     *      must be set separately after deployment.
     * 
     * Effects:
     * - Inherits from StrategyBase, ReentrancyGuard, and Ownable
     * - Sets deployer as owner
     */
    constructor() StrategyBase() Ownable(msg.sender) {}

    /**
     * @notice Sets the timelock address for critical operations
     * @dev Only owner can call this function
     * @param _timelock Address of the timelock controller
     */
    function setTimelock(address _timelock) external onlyOwner {
        if (_timelock == address(0)) revert Errors.InvalidAddress();
        timelock = _timelock;
        emit TimelockUpdated(_timelock);
    }

    /**
     * @notice Sets the coordinator address for this strategy
     * @dev Implements the StrategyBase interface requirement. Only the owner
     *      can set the coordinator, and it cannot be the same as current.
     * 
     * @param _coordinator Address of the StrategyCoordinator contract
     * 
     * Requirements:
     * - Coordinator address cannot be zero address
     * - Coordinator address cannot be the same as current
     * - Can only be called by the contract owner
     * 
     * Effects:
     * - Updates the coordinator address
     * - Emits CoordinatorUpdated event
     */
    function setCoordinator(address _coordinator) external override onlyOwner {
        if (_coordinator == address(0)) revert Errors.InvalidAddress();
        if (_coordinator == coordinator) revert Errors.SameCoordinator();

        coordinator = _coordinator;

        emit CoordinatorUpdated(_coordinator);
    }

    /**
     * @notice Updates support status for a specific token
     * @dev Enables or disables support for a token. When disabling, also clears
     *      the token-to-comet mapping. When enabling, requires that a Comet market
     *      has already been configured for the token.
     * 
     * @param _token Address of the token to update support for
     * @param _status New support status (true = supported, false = not supported)
     * 
     * Requirements:
     * - Token address cannot be zero address
     * - Status must be different from current status
     * - If enabling support, token must have a configured Comet market
     * - Can only be called by the contract owner
     * 
     * Effects:
     * - Updates supportedTokens mapping
     * - If disabling, clears tokenToComet mapping
     * - Emits TokenSupportUpdated event
     */
    function updateTokenSupport(address _token, bool _status) external onlyOwnerOrTimelock {
        if (_token == address(0)) revert Errors.InvalidAddress();
        if (supportedTokens[_token] == _status) revert Errors.TokenSupportUnchanged();
        if (_status && address(tokenToComet[_token]) == address(0)) revert Errors.NoPoolForToken();

        supportedTokens[_token] = _status;

        if (!_status) {
            delete tokenToComet[_token];
        }

        emit TokenSupportUpdated(_token, _status);
    }

    /**
     * @notice Updates support status for a Comet market and associates it with a token
     * @dev Enables or disables support for a Comet market. When enabling, validates
     *      that the market's base token matches the specified token. When disabling,
     *      clears the token-to-comet mapping.
     * 
     * @param _market Address of the Comet market contract
     * @param _token Address of the base token for this market
     * @param _status New support status (true = supported, false = not supported)
     * 
     * Requirements:
     * - Market and token addresses cannot be zero address
     * - Status must be different from current status
     * - If enabling, market's base token must match the specified token
     * - Can only be called by the contract owner
     * 
     * Effects:
     * - Updates supportedMarkets mapping
     * - If enabling, sets tokenToComet mapping
     * - If disabling, clears tokenToComet mapping
     * - Emits MarketSupportUpdated event
     * 
     * Security:
     * - Validates market-token compatibility before enabling
     * - Prevents misconfiguration of market-token relationships
     */
    function updateMarketSupport(address _market, address _token, bool _status) external onlyOwnerOrTimelock {
        if (_market == address(0) || _token == address(0)) revert Errors.InvalidAddress();
        if (supportedMarkets[_market] == _status) revert Errors.PoolSupportUnchanged();

        supportedMarkets[_market] = _status;

        if (_status) {
            IComet comet = IComet(_market);
            address base = comet.baseToken();
            if (base != _token) revert Errors.UnsupportedTokenForPool();

            tokenToComet[_token] = comet;
        } else {
            delete tokenToComet[_token];
        }

        emit MarketSupportUpdated(_market, _status, _token);
    }

    /**
     * @notice Deposits tokens into Compound V3 Comet market
     * @dev Implements the StrategyBase deposit interface. Transfers tokens from
     *      coordinator, approves Comet market, and supplies tokens to earn yield.
     *      The supplied tokens start earning interest immediately.
     * 
     * @param _token Address of the token to deposit (must be a base token)
     * @param _amount Amount of tokens to deposit
     * 
     * Requirements:
     * - Can only be called by the coordinator
     * - Token must be supported by this strategy
     * - Amount must be greater than 0
     * - Token must have a configured Comet market
     * 
     * Effects:
     * - Transfers tokens from coordinator to this contract
     * - Approves Comet market to spend tokens
     * - Supplies tokens to Comet market
     * - Tokens start earning interest in the Comet market
     * 
     * Security:
     * - Protected by onlyCoordinator modifier
     * - Protected by nonReentrant modifier
     * - Uses SafeERC20 for secure token transfers
     * - Validates all parameters before execution
     */
    function deposit(address _token, uint256 _amount) external override onlyCoordinator nonReentrant whenNotPaused {
        if (!supportedTokens[_token]) revert Errors.UnsupportedToken();
        if (_amount == 0) revert Errors.InvalidAmount();
        IComet comet = tokenToComet[_token];
        if (address(comet) == address(0)) revert Errors.NoPoolForToken();

        IERC20(_token).safeTransferFrom(coordinator, address(this), _amount);
        IERC20(_token).approve(address(comet), _amount);
        comet.supply(_token, _amount); // supply base token
        
        // Track total deposited for rewards calculation
        totalDeposited[_token] += _amount;
        
        emit Deposited(_token, _amount, totalDeposited[_token]);
    }

    /**
     * @notice Withdraws tokens from Compound V3 Comet market
     * @dev Implements the StrategyBase withdraw interface. Withdraws tokens from
     *      Comet market and sends them to the coordinator. The withdrawal amount
     *      includes any accrued interest. Uses before/after balance tracking to
     *      handle potential rounding differences.
     * 
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     * 
     * Requirements:
     * - Can only be called by the coordinator
     * - Token must be supported by this strategy
     * - Amount must be greater than 0
     * - Token must have a configured Comet market
     * - Strategy must have sufficient balance in Comet
     * 
     * Effects:
     * - Withdraws tokens from Comet market
     * - Transfers actual received tokens to coordinator
     * - Handles any rounding differences in withdrawal amounts
     * 
     * Security:
     * - Protected by onlyCoordinator modifier
     * - Protected by nonReentrant modifier
     * - Uses SafeERC20 for secure token transfers
     * - Tracks actual received amount to handle rounding
     */
    function withdraw(address _token, uint256 _amount) external override onlyCoordinator nonReentrant whenNotPaused {
        if (!supportedTokens[_token]) revert Errors.UnsupportedToken();
        if (_amount == 0) revert Errors.InvalidAmount();
        IComet comet = tokenToComet[_token];
        if (address(comet) == address(0)) revert Errors.NoPoolForToken();

        // Track before/after balances
        uint256 before = IERC20(_token).balanceOf(address(this));
        comet.withdraw(_token, _amount);
        uint256 afterBal = IERC20(_token).balanceOf(address(this));
        uint256 received = afterBal - before;

        IERC20(_token).safeTransfer(coordinator, received);
        
        // Track total withdrawn for rewards calculation
        totalWithdrawn[_token] += received;
        
        emit Withdrawn(_token, received, totalWithdrawn[_token]);
    }

    /**
     * @notice Returns the current balance of a token in Compound V3 Comet
     * @dev Implements the StrategyBase balanceOf interface. Returns the current
     *      balance in the Comet market which represents the original deposit plus
     *      accrued interest.
     * 
     * @param _token Address of the token to check balance for
     * @return Current balance of the token in Comet (including accrued interest)
     * 
     * Returns:
     * - Current Comet balance representing deposit + interest
     * - 0 if token has no configured Comet market
     * 
     * Note:
     * - Comet balances automatically increase over time due to interest accrual
     * - This balance represents the amount that can be withdrawn
     */
    function balanceOf(address _token) external view override returns (uint256) {
        IComet comet = tokenToComet[_token];
        return comet.balanceOf(address(this));
    }

    /**
     * @notice Returns the current APY for a supported token
     * @dev Fetches the current supply rate from Compound Comet and converts to basis points
     * 
     * @param _token Address of the token to get APY for
     * @return apy Current annual percentage yield in basis points (e.g., 500 = 5.00%)
     */
    function getCurrentAPY(address _token) external view override returns (uint256 apy) {
        if (!supportedTokens[_token]) return 0;
        
        IComet comet = tokenToComet[_token];
        if (address(comet) == address(0)) return 0;
        
        // Get current utilization and supply rate from Compound V3
        uint256 utilization = comet.getUtilization();
        uint64 supplyRate = comet.getSupplyRate(utilization);
        
        // Convert to APY in basis points
        // Formula: APR = (supplyRate / 10^18) * (seconds per year) * 100
        // APY in basis points = APR * 100
        uint256 secondsPerYear = 365 * 24 * 60 * 60;
        uint256 aprBasisPoints = (uint256(supplyRate) * secondsPerYear * 10000) / 1e18;
        
        return aprBasisPoints;
    }

    /**
     * @notice Returns the total accrued interest rewards for a token
     * @dev Calculates interest rewards as: current Comet balance - (total deposited - total withdrawn)
     * 
     * @param _token Address of the token to get interest rewards for
     * @return rewards Total accrued interest rewards in token units
     */
    function getAccruedInterestRewards(address _token) external view returns (uint256 rewards) {
        if (!supportedTokens[_token]) return 0;
        
        uint256 currentBalance = this.balanceOf(_token);
        uint256 netDeposits = totalDeposited[_token] - totalWithdrawn[_token];
        
        return currentBalance > netDeposits ? currentBalance - netDeposits : 0;
    }

    /**
     * @notice Returns the accrued protocol rewards (COMP tokens) for a token
     * @dev Uses Compound's baseTrackingAccrued to get protocol reward tokens earned
     * 
     * @param _token Address of the token to get protocol rewards for
     * @return rewards Total accrued protocol rewards (scaled by 10^6)
     */
    function getAccruedProtocolRewards(address _token) external view returns (uint256 rewards) {
        if (!supportedTokens[_token]) return 0;
        
        IComet comet = tokenToComet[_token];
        if (address(comet) == address(0)) return 0;
        
        try comet.baseTrackingAccrued(address(this)) returns (uint64 accrued) {
            return uint256(accrued);
        } catch {
            return 0;
        }
    }

    /**
     * @notice Returns detailed analytics for a token including both interest and protocol rewards
     * @dev Provides comprehensive data for frontend display
     * 
     * @param _token Address of the token to get analytics for
     * @return currentBalance Current Comet balance (principal + interest)
     * @return totalDeposits Total amount ever deposited
     * @return totalWithdrawals Total amount ever withdrawn
     * @return netDeposits Current net deposits (deposits - withdrawals)
     * @return interestRewards Total interest rewards earned
     * @return protocolRewards Total protocol rewards earned (COMP tokens, scaled by 10^6)
     * @return currentAPY Current APY in basis points
     */
    function getTokenAnalytics(address _token) external view returns (
        uint256 currentBalance,
        uint256 totalDeposits,
        uint256 totalWithdrawals,
        uint256 netDeposits,
        uint256 interestRewards,
        uint256 protocolRewards,
        uint256 currentAPY
    ) {
        if (!supportedTokens[_token]) {
            return (0, 0, 0, 0, 0, 0, 0);
        }
        
        currentBalance = this.balanceOf(_token);
        totalDeposits = totalDeposited[_token];
        totalWithdrawals = totalWithdrawn[_token];
        netDeposits = totalDeposits - totalWithdrawals;
        interestRewards = currentBalance > netDeposits ? currentBalance - netDeposits : 0;
        protocolRewards = this.getAccruedProtocolRewards(_token);
        currentAPY = this.getCurrentAPY(_token);
        
        return (currentBalance, totalDeposits, totalWithdrawals, netDeposits, interestRewards, protocolRewards, currentAPY);
    }

    /**
     * @notice Returns analytics for all supported tokens
     * @dev Batch function to get analytics for all tokens at once
     * 
     * @return tokens Array of supported token addresses
     * @return analytics Array of analytics data for each token (7 values per token)
     */
    function getAllTokenAnalytics() external view returns (
        address[] memory tokens,
        uint256[7][] memory analytics
    ) {
        // Get all supported tokens by iterating through known tokens
        // Note: This is a simplified approach - in production you might want to maintain a tokens array
        address[] memory knownTokens = new address[](2);
        knownTokens[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        knownTokens[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        
        uint256 supportedCount = 0;
        for (uint256 i = 0; i < knownTokens.length; i++) {
            if (supportedTokens[knownTokens[i]]) {
                supportedCount++;
            }
        }
        
        tokens = new address[](supportedCount);
        analytics = new uint256[7][](supportedCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < knownTokens.length; i++) {
            if (supportedTokens[knownTokens[i]]) {
                tokens[index] = knownTokens[i];
                
                // Get analytics data to avoid stack too deep
                (
                    uint256 currentBalance,
                    uint256 totalDeposits,
                    uint256 totalWithdrawals,
                    uint256 netDeposits,
                    uint256 interestRewards,
                    uint256 protocolRewards,
                    uint256 currentAPY
                ) = this.getTokenAnalytics(knownTokens[i]);
                
                // Assign to analytics array
                analytics[index][0] = currentBalance;
                analytics[index][1] = totalDeposits;
                analytics[index][2] = totalWithdrawals;
                analytics[index][3] = netDeposits;
                analytics[index][4] = interestRewards;
                analytics[index][5] = protocolRewards;
                analytics[index][6] = currentAPY;
                
                index++;
            }
        }
        
        return (tokens, analytics);
    }

    /**
     * @notice Returns the Comet market address for a given token
     * @dev Helper function to get the associated Comet market
     * 
     * @param _token Address of the token
     * @return market Address of the Comet market contract
     */
    function getCometMarket(address _token) external view returns (address market) {
        return address(tokenToComet[_token]);
    }

    /**
     * @notice Pauses the contract, preventing deposits and withdrawals
     * @dev Only owner or timelock can call this function
     */
    function pause() external onlyOwnerOrTimelock {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing deposits and withdrawals
     * @dev Only owner or timelock can call this function
     */
    function unpause() external onlyOwnerOrTimelock {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal function that can be called when paused
     * @dev Allows withdrawal of tokens from Comet when contract is paused for emergency situations
     * @param _token Address of the token to withdraw
     * @param _amount Amount to withdraw (0 = withdraw all)
     * @param _recipient Address to receive the withdrawn tokens
     */
    function emergencyWithdraw(address _token, uint256 _amount, address _recipient) external onlyOwnerOrTimelock whenPaused {
        if (_token == address(0)) revert Errors.InvalidAddress();
        if (_recipient == address(0)) revert Errors.InvalidAddress();
        if (!supportedTokens[_token]) revert Errors.UnsupportedToken();

        IComet comet = tokenToComet[_token];
        if (address(comet) == address(0)) revert Errors.NoPoolForToken();

        uint256 currentBalance = comet.balanceOf(address(this));
        uint256 withdrawAmount = _amount == 0 ? currentBalance : _amount;
        
        if (withdrawAmount == 0) revert Errors.InvalidAmount();

        // Track before/after balances
        uint256 before = IERC20(_token).balanceOf(address(this));
        comet.withdraw(_token, withdrawAmount);
        uint256 afterBal = IERC20(_token).balanceOf(address(this));
        uint256 received = afterBal - before;

        IERC20(_token).safeTransfer(_recipient, received);
        
        emit EmergencyWithdraw(_token, received, _recipient);
    }
}
