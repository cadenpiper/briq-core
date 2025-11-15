// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BriqShares
 * @author Briq Protocol
 * @notice ERC20 token representing ownership shares in the Briq yield optimization vault
 * @dev This contract implements a shares token that represents proportional ownership
 *      of the underlying assets in the BriqVault. Shares are minted when users deposit
 *      and burned when users withdraw, maintaining proportional ownership.
 * 
 * Key Features:
 * - Standard ERC20 functionality for transferability
 * - Mint/burn functionality restricted to the vault contract
 * - Ownership transfer to vault for operational control
 * 
 * Security Features:
 * - Only vault can mint/burn shares
 * - Owner-only vault address updates
 * - Standard ERC20 protections
 * - Custom errors for gas efficiency
 */
contract BriqShares is ERC20, Ownable {
    
    /// @notice Address of the vault contract authorized to mint/burn shares
    address public vault;

    /// @notice Thrown when vault address is zero
    error InvalidVaultAddress();
    
    /// @notice Thrown when caller is not the vault
    error OnlyVault();

    /// @notice Emitted when vault address is set
    event VaultSet(address indexed vault);

    /**
     * @notice Initializes the BriqShares token contract
     * @dev Creates an ERC20 token with the specified name and symbol
     * @param name The name of the shares token (e.g., "Briq Vault Shares")
     * @param symbol The symbol of the shares token (e.g., "bVault")
     * 
     * Effects:
     * - Deploys ERC20 token with specified parameters
     * - Sets deployer as initial owner
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    /**
     * @notice Sets the vault address and transfers ownership to it
     * @dev This function should be called once during deployment to establish
     *      the relationship between the shares token and the vault contract.
     *      After calling this, only the vault can mint/burn shares.
     * 
     * @param _vault Address of the BriqVault contract
     * 
     * Requirements:
     * - Vault address cannot be zero address
     * - Can only be called by the current owner
     * 
     * Effects:
     * - Sets the vault address
     * - Transfers ownership to the vault contract
     * - Emits VaultSet event
     * 
     * Security:
     * - Only owner can call this function
     * - Validates vault address is not zero
     */
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert InvalidVaultAddress();
        vault = _vault;
        transferOwnership(_vault);
        emit VaultSet(_vault);
    }

    /**
     * @notice Mints new shares to a specified address
     * @dev This function can only be called by the vault contract when users
     *      deposit tokens. The amount of shares minted is calculated by the
     *      vault based on the user's proportional contribution.
     * 
     * @param _to Address to receive the newly minted shares
     * @param _amount Amount of shares to mint
     * 
     * Requirements:
     * - Can only be called by the vault contract
     * - Recipient address is validated by ERC20 _mint function
     * 
     * Effects:
     * - Increases total supply by _amount
     * - Increases _to balance by _amount
     * - Emits Transfer event (from ERC20)
     */
    function mint(address _to, uint256 _amount) external {
        if (msg.sender != vault) revert OnlyVault();
        _mint(_to, _amount);
    }

    /**
     * @notice Burns shares from a specified address
     * @dev This function can only be called by the vault contract when users
     *      withdraw tokens. The amount of shares burned corresponds to the
     *      user's withdrawal amount relative to their total holdings.
     * 
     * @param _from Address to burn shares from
     * @param _amount Amount of shares to burn
     * 
     * Requirements:
     * - Can only be called by the vault contract
     * - _from must have sufficient balance (validated by ERC20 _burn)
     * 
     * Effects:
     * - Decreases total supply by _amount
     * - Decreases _from balance by _amount
     * - Emits Transfer event (from ERC20)
     */
    function burn(address _from, uint256 _amount) external {
        if (msg.sender != vault) revert OnlyVault();
        _burn(_from, _amount);
    }
}
