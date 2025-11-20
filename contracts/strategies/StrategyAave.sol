// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../StrategyBase.sol";
import { Errors } from "../libraries/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title StrategyAave
 * @author Briq Protocol
 * @notice Aave V3 lending strategy for yield generation
 * @dev Implements the StrategyBase interface to provide Aave V3 integration
 *      for depositing tokens and earning yield through Aave's lending protocol.
 * 
 * Key Features:
 * - Aave V3 protocol integration for yield generation
 * - Multi-token support with dynamic token management
 * - Real-time APY calculation from Aave rates
 * - Comprehensive analytics and reward tracking
 * 
 * Security Features:
 * - Coordinator-only access control for deposits/withdrawals
 * - Reentrancy protection on external calls
 * - Owner-only administrative functions
 * - Token support validation
 */
contract StrategyAave is StrategyBase, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Address of the Aave V3 Pool contract
    address public aavePool;
    
    /// @notice Address of the timelock controller for critical operations
    address public timelock;
    
    /// @notice Array of supported token addresses
    address[] public supportedTokens;
    
    /// @notice Mapping to check if a token is supported
    mapping(address => bool) public isTokenSupported;
    
    /// @notice Mapping from token to its corresponding aToken address
    mapping(address => address) public tokenToAToken;
    
    /// @notice Mapping from token address to its index in supportedTokens array
    mapping(address => uint256) private tokenIndex;
    
    /// @notice Total amount deposited for each token (for analytics)
    mapping(address => uint256) public totalDeposited;
    
    /// @notice Total amount withdrawn for each token (for analytics)
    mapping(address => uint256) public totalWithdrawn;

    /// @notice Emitted when Aave pool address is updated
    event AavePoolUpdated(address indexed pool);
    
    /// @notice Emitted when token support status is updated
    event TokenSupportUpdated(address indexed token, bool status);
    
    /// @notice Emitted when coordinator address is updated
    event CoordinatorUpdated(address indexed coordinator);
    
    /// @notice Emitted when tokens are deposited
    event Deposited(address indexed token, uint256 amount, uint256 totalDeposited);
    
    /// @notice Emitted when tokens are withdrawn
    event Withdrawn(address indexed token, uint256 amount, uint256 totalWithdrawn);

    /// @notice Emitted when emergency withdrawal is performed
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed recipient);

    /// @notice Emitted when timelock address is updated
    event TimelockUpdated(address indexed timelock);

    /**
     * @notice Modifier to allow only owner or timelock to call critical functions
     */
    modifier onlyOwnerOrTimelock() {
        if (msg.sender != owner() && msg.sender != timelock) revert Errors.UnauthorizedAccess();
        _;
    }

    /**
     * @notice Initialize the StrategyAave contract
     * @dev Sets the deployer as the owner
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
     * @dev Only owner can call this function
     * @param _coordinator Address of the StrategyCoordinator contract
     */
    function setCoordinator(address _coordinator) external override onlyOwner {
        if (_coordinator == address(0)) revert Errors.InvalidAddress();
        if (_coordinator == coordinator) revert Errors.SameCoordinator();

        coordinator = _coordinator;

        emit CoordinatorUpdated(_coordinator);
    }

    /**
     * @notice Sets the Aave pool address
     * @dev Only owner or timelock can call this function
     * @param _pool Address of the Aave V3 Pool contract
     */
    function setAavePool(address _pool) external onlyOwnerOrTimelock {
        if (_pool == address(0)) revert Errors.InvalidAddress();
        aavePool = _pool;
        emit AavePoolUpdated(_pool);
    }

    /**
     * @notice Adds support for a new token
     * @dev Validates token compatibility with Aave pool. Only owner or timelock can call
     * @param _token Address of the token to add support for
     */
    function addSupportedToken(address _token) external onlyOwnerOrTimelock {
        if (_token == address(0)) revert Errors.InvalidAddress();
        if (aavePool == address(0)) revert Errors.NoPoolForToken();
        if (isTokenSupported[_token]) revert Errors.TokenSupportUnchanged();

        // Get aToken address from Aave pool
        DataTypes.ReserveData memory data = IPool(aavePool).getReserveData(_token);
        if (data.aTokenAddress == address(0)) revert Errors.UnsupportedTokenForPool();

        supportedTokens.push(_token);
        isTokenSupported[_token] = true;
        tokenToAToken[_token] = data.aTokenAddress;
        tokenIndex[_token] = supportedTokens.length - 1; // Store index for efficient removal

        emit TokenSupportUpdated(_token, true);
    }

    /**
     * @notice Removes support for a token
     * @dev Removes token from supported tokens array and mappings using O(1) removal. Only owner or timelock can call
     * @param _token Address of the token to remove support for
     */
    function removeSupportedToken(address _token) external onlyOwnerOrTimelock {
        if (_token == address(0)) revert Errors.InvalidAddress();
        if (!isTokenSupported[_token]) revert Errors.TokenSupportUnchanged();

        // Get the index of the token to remove
        uint256 indexToRemove = tokenIndex[_token];
        uint256 lastIndex = supportedTokens.length - 1;

        // If not the last element, move the last element to the position of the element to remove
        if (indexToRemove != lastIndex) {
            address lastToken = supportedTokens[lastIndex];
            supportedTokens[indexToRemove] = lastToken;
            tokenIndex[lastToken] = indexToRemove; // Update the moved token's index
        }

        // Remove the last element
        supportedTokens.pop();

        // Clean up mappings
        isTokenSupported[_token] = false;
        delete tokenToAToken[_token];
        delete tokenIndex[_token];

        emit TokenSupportUpdated(_token, false);
    }

    /**
     * @notice Returns array of all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice Emergency pause function to stop all operations
     * @dev Can be called by owner in emergency situations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the strategy
     * @dev Can be called by owner to resume operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal function for stuck funds
     * @dev Can only be called by owner when paused. Withdraws tokens directly without coordinator
     * @param _token Address of the token to withdraw
     * @param _amount Amount to withdraw (0 = withdraw all)
     * @param _recipient Address to receive the tokens
     */
    function emergencyWithdraw(
        address _token, 
        uint256 _amount, 
        address _recipient
    ) external onlyOwner whenPaused nonReentrant {
        if (_token == address(0) || _recipient == address(0)) revert Errors.InvalidAddress();
        if (!isTokenSupported[_token]) revert Errors.UnsupportedToken();
        if (aavePool == address(0)) revert Errors.NoPoolForToken();

        // If amount is 0, withdraw all available balance
        if (_amount == 0) {
            _amount = this.balanceOf(_token);
        }
        
        if (_amount == 0) revert Errors.InvalidAmount();

        // Withdraw from Aave directly to recipient
        uint256 withdrawn = IPool(aavePool).withdraw(_token, _amount, _recipient);
        if (withdrawn < _amount) revert Errors.InsufficientWithdrawal();

        emit EmergencyWithdraw(_token, withdrawn, _recipient);
    }

    /**
     * @notice Deposits tokens into Aave V3 protocol
     * @dev Only coordinator can call this function
     * @param _token Address of the token to deposit
     * @param _amount Amount of tokens to deposit
     */
    function deposit(address _token, uint256 _amount) external override onlyCoordinator nonReentrant whenNotPaused {
        if (!isTokenSupported[_token]) revert Errors.UnsupportedToken();
        if (_amount == 0) revert Errors.InvalidAmount();
        if (aavePool == address(0)) revert Errors.NoPoolForToken();

        IERC20(_token).safeTransferFrom(coordinator, address(this), _amount);
        IERC20(_token).approve(aavePool, _amount);
        IPool(aavePool).supply(_token, _amount, address(this), 0); // aTokens go to StrategyAave
        
        // Track total deposited for rewards calculation
        totalDeposited[_token] += _amount;
        
        emit Deposited(_token, _amount, totalDeposited[_token]);
    }

    /**
     * @notice Withdraws tokens from Aave V3 protocol
     * @dev Only coordinator can call this function
     * @param _token Address of the token to withdraw
     * @param _amount Amount of tokens to withdraw
     */
    function withdraw(address _token, uint256 _amount) external override onlyCoordinator nonReentrant whenNotPaused {
        if (!isTokenSupported[_token]) revert Errors.UnsupportedToken();
        if (_amount == 0) revert Errors.InvalidAmount();
        if (aavePool == address(0)) revert Errors.NoPoolForToken();

        uint256 withdrawn = IPool(aavePool).withdraw(_token, _amount, coordinator); // Sends tokens back to coordinator
        if (withdrawn < _amount) revert Errors.InsufficientWithdrawal();
        
        // Track total withdrawn for rewards calculation
        totalWithdrawn[_token] += withdrawn;
        
        emit Withdrawn(_token, withdrawn, totalWithdrawn[_token]);
    }

    /**
     * @notice Returns the current balance of a token in this strategy
     * @dev Returns the aToken balance which includes accrued interest
     * @param _token Address of the token to check balance for
     * @return Current balance of the token in this strategy
     */
    function balanceOf(address _token) external view override returns (uint256) {
        address aToken = tokenToAToken[_token];
        if (aToken == address(0)) return 0;
        return IERC20(aToken).balanceOf(address(this));
    }

    /**
     * @notice Returns the current APY for a supported token
     * @dev Fetches the current liquidity rate from Aave and converts to basis points
     * @param _token Address of the token to get APY for
     * @return apy Current annual percentage yield in basis points (e.g., 500 = 5.00%)
     */
    function getCurrentAPY(address _token) external view override returns (uint256 apy) {
        if (!isTokenSupported[_token] || aavePool == address(0)) return 0;
        
        // Get current liquidity rate from Aave
        DataTypes.ReserveData memory reserveData = IPool(aavePool).getReserveData(_token);
        
        // Convert from ray (1e27) to basis points (1e4)
        // Aave rate is already annualized
        uint256 liquidityRate = uint256(reserveData.currentLiquidityRate);
        apy = liquidityRate / 1e23;
        
        return apy;
    }

    /**
     * @notice Returns the total accrued rewards for a token
     * @dev Calculates rewards as: current aToken balance - (total deposited - total withdrawn)
     * @param _token Address of the token to get rewards for
     * @return rewards Total accrued rewards in token units
     */
    function getAccruedRewards(address _token) external view returns (uint256 rewards) {
        if (!isTokenSupported[_token]) return 0;
        
        uint256 currentBalance = this.balanceOf(_token);
        uint256 netDeposits = totalDeposited[_token] - totalWithdrawn[_token];
        
        return currentBalance > netDeposits ? currentBalance - netDeposits : 0;
    }

    /**
     * @notice Returns detailed analytics for a token
     * @dev Provides comprehensive data for frontend display
     * @param _token Address of the token to get analytics for
     * @return currentBalance Current aToken balance (principal + rewards)
     * @return totalDeposits Total amount ever deposited
     * @return totalWithdrawals Total amount ever withdrawn
     * @return netDeposits Current net deposits (deposits - withdrawals)
     * @return accruedRewards Total rewards earned
     * @return currentAPY Current APY in basis points
     */
    function getTokenAnalytics(address _token) external view returns (
        uint256 currentBalance,
        uint256 totalDeposits,
        uint256 totalWithdrawals,
        uint256 netDeposits,
        uint256 accruedRewards,
        uint256 currentAPY
    ) {
        if (!isTokenSupported[_token]) {
            return (0, 0, 0, 0, 0, 0);
        }
        
        currentBalance = this.balanceOf(_token);
        totalDeposits = totalDeposited[_token];
        totalWithdrawals = totalWithdrawn[_token];
        netDeposits = totalDeposits - totalWithdrawals;
        accruedRewards = currentBalance > netDeposits ? currentBalance - netDeposits : 0;
        currentAPY = this.getCurrentAPY(_token);
        
        return (currentBalance, totalDeposits, totalWithdrawals, netDeposits, accruedRewards, currentAPY);
    }

    /**
     * @notice Returns analytics for all supported tokens
     * @dev Batch function to get analytics for all tokens at once
     * @return tokens Array of supported token addresses
     * @return analytics Array of analytics data for each token
     */
    function getAllTokenAnalytics() external view returns (
        address[] memory tokens,
        uint256[6][] memory analytics
    ) {
        tokens = supportedTokens;
        analytics = new uint256[6][](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            (
                analytics[i][0], // currentBalance
                analytics[i][1], // totalDeposits
                analytics[i][2], // totalWithdrawals
                analytics[i][3], // netDeposits
                analytics[i][4], // accruedRewards
                analytics[i][5]  // currentAPY
            ) = this.getTokenAnalytics(tokens[i]);
        }
        
        return (tokens, analytics);
    }
}
