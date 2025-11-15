// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import "../contracts/BriqShares.sol";

contract BriqSharesTest is Test {
    BriqShares public briqShares;
    
    address public owner;
    address public vault;
    address public user1;
    address public user2;
    address public unauthorized;
    
    string constant TOKEN_NAME = "Briq Vault Shares";
    string constant TOKEN_SYMBOL = "bVault";
    
    event VaultSet(address indexed vault);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function setUp() public {
        owner = address(this);
        vault = makeAddr("vault");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        unauthorized = makeAddr("unauthorized");
        
        briqShares = new BriqShares(TOKEN_NAME, TOKEN_SYMBOL);
    }
    
    // ============ DEPLOYMENT TESTS ============
    
    function testDeployment() public view {
        assertEq(briqShares.name(), TOKEN_NAME);
        assertEq(briqShares.symbol(), TOKEN_SYMBOL);
        assertEq(briqShares.decimals(), 18);
        assertEq(briqShares.totalSupply(), 0);
        assertEq(briqShares.owner(), owner);
        assertEq(briqShares.vault(), address(0));
    }
    
    // ============ SET VAULT TESTS ============
    
    function testSetVault() public {
        vm.expectEmit(true, false, false, false);
        emit VaultSet(vault);
        
        briqShares.setVault(vault);
        
        assertEq(briqShares.vault(), vault);
        assertEq(briqShares.owner(), vault);
    }
    
    function testSetVaultRevertsOnZeroAddress() public {
        vm.expectRevert(BriqShares.InvalidVaultAddress.selector);
        briqShares.setVault(address(0));
    }
    
    function testSetVaultRevertsIfNotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        briqShares.setVault(vault);
    }
    
    function testSetVaultOnlyCallableOnce() public {
        briqShares.setVault(vault);
        
        // Now vault is owner, original owner can't call setVault again
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        briqShares.setVault(user1);
    }
    
    // ============ MINT TESTS ============
    
    function testMint() public {
        briqShares.setVault(vault);
        uint256 amount = 100 ether;
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, amount);
        
        vm.prank(vault);
        briqShares.mint(user1, amount);
        
        assertEq(briqShares.balanceOf(user1), amount);
        assertEq(briqShares.totalSupply(), amount);
    }
    
    function testMintRevertsIfNotVault() public {
        briqShares.setVault(vault);
        uint256 amount = 100 ether;
        
        vm.expectRevert(BriqShares.OnlyVault.selector);
        briqShares.mint(user1, amount);
        
        vm.prank(unauthorized);
        vm.expectRevert(BriqShares.OnlyVault.selector);
        briqShares.mint(user1, amount);
    }
    
    function testMintZeroAmount() public {
        briqShares.setVault(vault);
        
        vm.prank(vault);
        briqShares.mint(user1, 0);
        
        assertEq(briqShares.balanceOf(user1), 0);
        assertEq(briqShares.totalSupply(), 0);
    }
    
    function testMintMultipleTimes() public {
        briqShares.setVault(vault);
        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        
        vm.startPrank(vault);
        briqShares.mint(user1, amount1);
        briqShares.mint(user1, amount2);
        vm.stopPrank();
        
        assertEq(briqShares.balanceOf(user1), amount1 + amount2);
        assertEq(briqShares.totalSupply(), amount1 + amount2);
    }
    
    function testMintToDifferentAddresses() public {
        briqShares.setVault(vault);
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;
        
        vm.startPrank(vault);
        briqShares.mint(user1, amount1);
        briqShares.mint(user2, amount2);
        vm.stopPrank();
        
        assertEq(briqShares.balanceOf(user1), amount1);
        assertEq(briqShares.balanceOf(user2), amount2);
        assertEq(briqShares.totalSupply(), amount1 + amount2);
    }
    
    function testMintRevertsOnZeroAddress() public {
        briqShares.setVault(vault);
        uint256 amount = 100 ether;
        
        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        briqShares.mint(address(0), amount);
    }
    
    // ============ BURN TESTS ============
    
    function testBurn() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        uint256 burnAmount = 100 ether;
        
        vm.startPrank(vault);
        briqShares.mint(user1, initialAmount);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, address(0), burnAmount);
        
        briqShares.burn(user1, burnAmount);
        vm.stopPrank();
        
        assertEq(briqShares.balanceOf(user1), initialAmount - burnAmount);
        assertEq(briqShares.totalSupply(), initialAmount - burnAmount);
    }
    
    function testBurnRevertsIfNotVault() public {
        briqShares.setVault(vault);
        uint256 amount = 100 ether;
        
        vm.prank(vault);
        briqShares.mint(user1, amount);
        
        vm.expectRevert(BriqShares.OnlyVault.selector);
        briqShares.burn(user1, amount);
        
        vm.prank(unauthorized);
        vm.expectRevert(BriqShares.OnlyVault.selector);
        briqShares.burn(user1, amount);
    }
    
    function testBurnRevertsOnInsufficientBalance() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        uint256 burnAmount = initialAmount + 1;
        
        vm.startPrank(vault);
        briqShares.mint(user1, initialAmount);
        
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user1, initialAmount, burnAmount));
        briqShares.burn(user1, burnAmount);
        vm.stopPrank();
    }
    
    function testBurnZeroAmount() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        
        vm.startPrank(vault);
        briqShares.mint(user1, initialAmount);
        briqShares.burn(user1, 0);
        vm.stopPrank();
        
        assertEq(briqShares.balanceOf(user1), initialAmount);
        assertEq(briqShares.totalSupply(), initialAmount);
    }
    
    function testBurnEntireBalance() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        
        vm.startPrank(vault);
        briqShares.mint(user1, initialAmount);
        briqShares.burn(user1, initialAmount);
        vm.stopPrank();
        
        assertEq(briqShares.balanceOf(user1), 0);
        assertEq(briqShares.totalSupply(), 0);
    }
    
    function testBurnFromZeroAddress() public {
        briqShares.setVault(vault);
        uint256 amount = 100 ether;
        
        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        briqShares.burn(address(0), amount);
    }
    
    // ============ ERC20 STANDARD FUNCTION TESTS ============
    
    function testTransfer() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        uint256 transferAmount = 100 ether;
        
        vm.prank(vault);
        briqShares.mint(user1, initialAmount);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, transferAmount);
        
        vm.prank(user1);
        bool success = briqShares.transfer(user2, transferAmount);
        
        assertTrue(success);
        assertEq(briqShares.balanceOf(user1), initialAmount - transferAmount);
        assertEq(briqShares.balanceOf(user2), transferAmount);
    }
    
    function testTransferRevertsOnInsufficientBalance() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        uint256 transferAmount = initialAmount + 1;
        
        vm.prank(vault);
        briqShares.mint(user1, initialAmount);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user1, initialAmount, transferAmount));
        briqShares.transfer(user2, transferAmount);
    }
    
    function testApprove() public {
        uint256 approveAmount = 100 ether;
        
        vm.expectEmit(true, true, false, true);
        emit Approval(user1, user2, approveAmount);
        
        vm.prank(user1);
        bool success = briqShares.approve(user2, approveAmount);
        
        assertTrue(success);
        assertEq(briqShares.allowance(user1, user2), approveAmount);
    }
    
    function testTransferFrom() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        uint256 approveAmount = 200 ether;
        uint256 transferAmount = 100 ether;
        
        vm.prank(vault);
        briqShares.mint(user1, initialAmount);
        
        vm.prank(user1);
        briqShares.approve(user2, approveAmount);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, transferAmount);
        
        vm.prank(user2);
        bool success = briqShares.transferFrom(user1, user2, transferAmount);
        
        assertTrue(success);
        assertEq(briqShares.balanceOf(user1), initialAmount - transferAmount);
        assertEq(briqShares.balanceOf(user2), transferAmount);
        assertEq(briqShares.allowance(user1, user2), approveAmount - transferAmount);
    }
    
    function testTransferFromRevertsOnInsufficientAllowance() public {
        briqShares.setVault(vault);
        uint256 initialAmount = 1000 ether;
        uint256 approveAmount = 200 ether;
        uint256 transferAmount = approveAmount + 1;
        
        vm.prank(vault);
        briqShares.mint(user1, initialAmount);
        
        vm.prank(user1);
        briqShares.approve(user2, approveAmount);
        
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, user2, approveAmount, transferAmount));
        briqShares.transferFrom(user1, user2, transferAmount);
    }
    
    // ============ EDGE CASES AND SECURITY TESTS ============
    
    function testTotalSupplyConsistency() public {
        briqShares.setVault(vault);
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;
        uint256 burnAmount = 50 ether;
        
        vm.startPrank(vault);
        briqShares.mint(user1, amount1);
        briqShares.mint(user2, amount2);
        briqShares.burn(user1, burnAmount);
        vm.stopPrank();
        
        uint256 expectedTotal = amount1 + amount2 - burnAmount;
        assertEq(briqShares.totalSupply(), expectedTotal);
        
        uint256 actualTotal = briqShares.balanceOf(user1) + briqShares.balanceOf(user2);
        assertEq(actualTotal, expectedTotal);
    }
    
    function testUnauthorizedAccessAfterVaultSet() public {
        briqShares.setVault(vault);
        uint256 amount = 100 ether;
        
        // Original owner can't mint/burn after vault is set
        vm.expectRevert(BriqShares.OnlyVault.selector);
        briqShares.mint(user1, amount);
        
        vm.expectRevert(BriqShares.OnlyVault.selector);
        briqShares.burn(user1, amount);
    }
    
    // ============ FUZZ TESTS ============
    
    function testFuzzMint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount <= type(uint128).max); // Avoid overflow
        
        briqShares.setVault(vault);
        
        vm.prank(vault);
        briqShares.mint(to, amount);
        
        assertEq(briqShares.balanceOf(to), amount);
        assertEq(briqShares.totalSupply(), amount);
    }
    
    function testFuzzBurn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount <= type(uint128).max);
        vm.assume(burnAmount <= mintAmount);
        
        briqShares.setVault(vault);
        
        vm.startPrank(vault);
        briqShares.mint(user1, mintAmount);
        briqShares.burn(user1, burnAmount);
        vm.stopPrank();
        
        assertEq(briqShares.balanceOf(user1), mintAmount - burnAmount);
        assertEq(briqShares.totalSupply(), mintAmount - burnAmount);
    }
    
    function testFuzzTransfer(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount <= type(uint128).max);
        vm.assume(transferAmount <= mintAmount);
        
        briqShares.setVault(vault);
        
        vm.prank(vault);
        briqShares.mint(user1, mintAmount);
        
        vm.prank(user1);
        briqShares.transfer(user2, transferAmount);
        
        assertEq(briqShares.balanceOf(user1), mintAmount - transferAmount);
        assertEq(briqShares.balanceOf(user2), transferAmount);
        assertEq(briqShares.totalSupply(), mintAmount);
    }
}
