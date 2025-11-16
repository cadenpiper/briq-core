// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title BriqTimelock
 * @author Briq Protocol
 * @notice Timelock controller for critical protocol operations
 * @dev Uses OpenZeppelin's TimelockController with 48-hour delay
 * 
 * Initial Setup (Solo Dev):
 * - Admin (you) can propose and execute
 * - 48-hour delay on all operations
 * - Admin should eventually renounce admin role to make timelock self-governing
 */
contract BriqTimelock is TimelockController {
    
    // Custom Errors
    error NotAdmin();
    
    /// @notice Delay period for critical operations (48 hours)
    uint256 public constant DELAY = 48 hours;

    /**
     * @notice Initialize the timelock controller
     * @param admin Address that will have initial admin/proposer/executor rights
     */
    constructor(address admin) 
        TimelockController(
            DELAY,                    // 48 hour delay
            new address[](1),         // proposers array (will be set below)
            new address[](1),         // executors array (will be set below)  
            admin                     // admin address
        ) 
    {
        // The constructor above doesn't actually set the proposers/executors
        // We need to grant the roles manually
        
        // Grant admin the ability to propose operations
        _grantRole(PROPOSER_ROLE, admin);
        
        // Grant admin the ability to execute operations
        _grantRole(EXECUTOR_ROLE, admin);
        
        // Admin keeps DEFAULT_ADMIN_ROLE initially (can manage other roles)
        // Later, admin should renounce this role to make timelock self-governing
    }

    /**
     * @notice Renounce admin privileges and make timelock self-governing
     * @dev After calling this, all role management must go through timelock delay
     * WARNING: Only call this when you're ready to fully decentralize
     */
    function renounceAdminRole() external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        
        // Transfer admin role to the timelock itself
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));
        
        // Renounce your admin role
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
