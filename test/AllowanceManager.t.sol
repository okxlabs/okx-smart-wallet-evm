// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import {IAllowanceManager} from "src/interfaces/IAllowanceManager.sol";
import {IERC7914} from "src/interfaces/IERC7914.sol";

contract AllowanceManagerTest is Base {
    MockERC20 mockToken;
    MockERC20 mockToken2;
    
    address public spender;
    address public recipient;
    address public unauthorized;
    
    event ApproveToken(address indexed token, address indexed spender, uint256 amount);
    event ApproveTokenTransient(address indexed token, address indexed spender, uint256 amount);
    event TransferFromToken(address indexed token, address indexed recipient, uint256 amount);
    event TransferFromTokenTransient(address indexed token, address indexed recipient, uint256 amount);
    event TokenAllowanceUpdated(address indexed token, address indexed spender, uint256 newAllowance);
    
    event ApproveNative(address indexed owner, address indexed spender, uint256 value);
    event ApproveNativeTransient(address indexed owner, address indexed spender, uint256 value);
    event TransferFromNative(address indexed from, address indexed to, uint256 value);
    event TransferFromNativeTransient(address indexed from, address indexed to, uint256 value);
    event NativeAllowanceUpdated(address indexed spender, uint256 value);

    function setUp() public override {
        super.setUp();
        
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        unauthorized = makeAddr("unauthorized");
        
        vm.prank(_alice);
        mockToken = new MockERC20();
        
        vm.prank(_alice);
        mockToken2 = new MockERC20();
        
        // The wallet (_alice) already has tokens from MockERC20 constructor
        // No additional transfer needed since _alice IS the wallet address
    }

    // ============ ERC20 Token Tests ============
    
    function test_ApproveToken_Success() public {
        uint256 amount = 100 * 10**18;
        
        vm.expectEmit(true, true, false, true);
        emit ApproveToken(address(mockToken), spender, amount);
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveToken(address(mockToken), spender, amount);
        
        assertTrue(success);
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), amount);
    }
    
    function test_ApproveToken_OnlyOwnerOrEntryPoint() public {
        uint256 amount = 100 * 10**18;
        
        // Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount);
        
        // Should succeed for owner (Alice)
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount);
        
        // Should succeed for wallet itself
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount * 2);
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), amount * 2);
    }
    
    function test_ApproveTokenTransient_Success() public {
        uint256 amount = 100 * 10**18;
        
        vm.expectEmit(true, true, false, true);
        emit ApproveTokenTransient(address(mockToken), spender, amount);
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveTokenTransient(address(mockToken), spender, amount);
        
        assertTrue(success);
        assertEq(SmartWallet(_alice).transientTokenAllowance(address(mockToken), spender), amount);
    }
    
    function test_TransferFromToken_Success() public {
        uint256 allowanceAmount = 200 * 10**18;
        uint256 transferAmount = 100 * 10**18;
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, allowanceAmount);
        
        uint256 initialBalance = mockToken.balanceOf(recipient);
        
        vm.expectEmit(true, true, false, true);
        emit TokenAllowanceUpdated(address(mockToken), spender, allowanceAmount - transferAmount);
        
        vm.expectEmit(true, true, false, true);
        emit TransferFromToken(address(mockToken), recipient, transferAmount);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromToken(
            address(mockToken), 
            _alice, 
            recipient, 
            transferAmount
        );
        
        assertTrue(success);
        assertEq(mockToken.balanceOf(recipient), initialBalance + transferAmount);
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), allowanceAmount - transferAmount);
    }
    
    function test_TransferFromToken_InsufficientAllowance() public {
        uint256 allowanceAmount = 50 * 10**18;
        uint256 transferAmount = 100 * 10**18;
        
        // Set up insufficient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, allowanceAmount);
        
        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.TokenAllowanceExceeded.selector);
        SmartWallet(_alice).transferFromToken(
            address(mockToken), 
            _alice, 
            recipient, 
            transferAmount
        );
    }
    
    function test_TransferFromToken_IncorrectSender() public {
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, 100 * 10**18);
        
        vm.prank(spender);
        vm.expectRevert(IERC7914.IncorrectSender.selector);
        SmartWallet(_alice).transferFromToken(
            address(mockToken), 
            _bob, // Wrong sender - should be _alice (the wallet address)
            recipient, 
            50 * 10**18
        );
    }
    
    function test_TransferFromTokenTransient_Success() public {
        uint256 allowanceAmount = 200 * 10**18;
        uint256 transferAmount = 100 * 10**18;
        
        // Set up transient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveTokenTransient(address(mockToken), spender, allowanceAmount);
        
        uint256 initialBalance = mockToken.balanceOf(recipient);
        
        vm.expectEmit(true, true, false, true);
        emit TransferFromTokenTransient(address(mockToken), recipient, transferAmount);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromTokenTransient(
            address(mockToken), 
            _alice, 
            recipient, 
            transferAmount
        );
        
        assertTrue(success);
        assertEq(mockToken.balanceOf(recipient), initialBalance + transferAmount);
        assertEq(SmartWallet(_alice).transientTokenAllowance(address(mockToken), spender), allowanceAmount - transferAmount);
    }
    
    function test_TransferFromToken_ZeroAmount() public {
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromToken(
            address(mockToken), 
            _alice, 
            recipient, 
            0
        );
        assertTrue(success);
    }
    
    function test_TransferFromToken_UnlimitedAllowance() public {
        uint256 transferAmount = 100 * 10**18;
        
        // Set unlimited allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, type(uint256).max);
        
        vm.prank(spender);
        SmartWallet(_alice).transferFromToken(
            address(mockToken), 
            _alice, 
            recipient, 
            transferAmount
        );
        
        // Allowance should remain unlimited
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), type(uint256).max);
    }

    // ============ Native ETH Tests ============
    
    function test_ApproveNative_Success() public {
        uint256 amount = 1 ether;
        
        vm.expectEmit(true, true, false, true);
        emit ApproveNative(address(SmartWallet(_alice)), spender, amount);
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveNative(spender, amount);
        
        assertTrue(success);
        assertEq(SmartWallet(_alice).nativeAllowance(spender), amount);
    }
    
    function test_ApproveNative_OnlyOwnerOrEntryPoint() public {
        uint256 amount = 1 ether;
        
        // Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        SmartWallet(_alice).approveNative(spender, amount);
        
        // Should succeed for owner
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, amount);
        
        // Should succeed for entryPoint
        vm.prank(address(SmartWallet(_alice)));
        SmartWallet(_alice).approveNative(spender, amount * 2);
        assertEq(SmartWallet(_alice).nativeAllowance(spender), amount * 2);
    }
    
    function test_ApproveNativeTransient_Success() public {
        uint256 amount = 1 ether;
        
        vm.expectEmit(true, true, false, true);
        emit ApproveNativeTransient(address(SmartWallet(_alice)), spender, amount);
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveNativeTransient(spender, amount);
        
        assertTrue(success);
        assertEq(SmartWallet(_alice).transientNativeAllowance(spender), amount);
    }
    
    function test_TransferFromNative_Success() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, allowanceAmount);
        
        uint256 initialBalance = recipient.balance;
        
        vm.expectEmit(true, false, false, true);
        emit NativeAllowanceUpdated(spender, allowanceAmount - transferAmount);
        
        vm.expectEmit(true, true, false, true);
        emit TransferFromNative(address(SmartWallet(_alice)), recipient, transferAmount);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromNative(
            _alice, 
            recipient, 
            transferAmount
        );
        
        assertTrue(success);
        assertEq(recipient.balance, initialBalance + transferAmount);
        assertEq(SmartWallet(_alice).nativeAllowance(spender), allowanceAmount - transferAmount);
    }
    
    function test_TransferFromNative_InsufficientAllowance() public {
        uint256 allowanceAmount = 0.5 ether;
        uint256 transferAmount = 1 ether;
        
        // Set up insufficient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, allowanceAmount);
        
        vm.prank(spender);
        vm.expectRevert(IERC7914.AllowanceExceeded.selector);
        SmartWallet(_alice).transferFromNative(
            _alice, 
            recipient, 
            transferAmount
        );
    }
    
    function test_TransferFromNativeTransient_Success() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;
        
        // Set up transient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNativeTransient(spender, allowanceAmount);
        
        uint256 initialBalance = recipient.balance;
        
        vm.expectEmit(true, true, false, true);
        emit TransferFromNativeTransient(address(SmartWallet(_alice)), recipient, transferAmount);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromNativeTransient(
            _alice, 
            recipient, 
            transferAmount
        );
        
        assertTrue(success);
        assertEq(recipient.balance, initialBalance + transferAmount);
        assertEq(SmartWallet(_alice).transientNativeAllowance(spender), allowanceAmount - transferAmount);
    }
    
    function test_TransferFromNative_ZeroAmount() public {
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromNative(
            _alice, 
            recipient, 
            0
        );
        assertTrue(success);
    }

    // ============ Edge Cases and Integration Tests ============
    
    function test_MultipleSpenders() public {
        address spender2 = makeAddr("spender2");
        uint256 amount1 = 100 * 10**18;
        uint256 amount2 = 200 * 10**18;
        
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount1);
        
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender2, amount2);
        
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), amount1);
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender2), amount2);
    }
    
    function test_MultipleTokens() public {
        vm.prank(_alice);
        MockERC20 token2 = new MockERC20();
        
        uint256 amount1 = 100 * 10**18;
        uint256 amount2 = 200 * 10**18;
        
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount1);
        
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(token2), spender, amount2);
        
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), amount1);
        assertEq(SmartWallet(_alice).tokenAllowance(address(token2), spender), amount2);
    }
    
    function test_TransientStorageIsolation() public {
        uint256 amount = 100 * 10**18;
        
        // Set transient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveTokenTransient(address(mockToken), spender, amount);
        
        // Set persistent allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount * 2);
        
        // Both should be independent
        assertEq(SmartWallet(_alice).transientTokenAllowance(address(mockToken), spender), amount);
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), amount * 2);
    }
    
    function test_OverwriteAllowances() public {
        uint256 initialAmount = 100 * 10**18;
        uint256 newAmount = 200 * 10**18;
        
        // Set initial allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, initialAmount);
        
        // Overwrite with new amount
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, newAmount);
        
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), newAmount);
    }

    // ============ Fuzz Tests ============
    
    function testFuzz_ApproveToken(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveToken(address(mockToken), spender, amount);
        
        assertTrue(success);
        assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), amount);
    }
    
    function testFuzz_TransferFromToken(uint256 allowanceAmount, uint256 transferAmount) public {
        vm.assume(allowanceAmount <= mockToken.balanceOf(_alice));
        vm.assume(transferAmount <= allowanceAmount);
        vm.assume(transferAmount > 0);
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, allowanceAmount);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromToken(
            address(mockToken), 
            _alice, 
            recipient, 
            transferAmount
        );
        
        assertTrue(success);
        assertEq(mockToken.balanceOf(recipient), transferAmount);
        
        if (allowanceAmount < type(uint256).max) {
            assertEq(SmartWallet(_alice).tokenAllowance(address(mockToken), spender), allowanceAmount - transferAmount);
        }
    }
}
