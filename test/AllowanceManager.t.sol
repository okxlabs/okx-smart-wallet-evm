// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {IAllowanceManager} from "src/interfaces/IAllowanceManager.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import {InitialOwner} from "src/Types.sol";

contract AllowanceManagerTest is Test {
    SmartWallet public wallet;
    MockERC20 public mockToken;
    address public spender;
    address public recipient;
    address payable public _alice;
    address public _bob;
    address public unauthorized;

    event ApproveNative(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    event ApproveToken(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    event TransferFromNative(
        address indexed owner,
        address indexed recipient,
        uint256 amount
    );

    event TransferFromToken(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    event NativeAllowanceUpdated(
        address indexed spender,
        uint256 newAllowance
    );

    event TokenAllowanceUpdated(
        address indexed token,
        address indexed spender,
        uint256 newAllowance
    );

    function setUp() public {
        // Set up test addresses
        _alice = payable(makeAddr("alice"));
        _bob = makeAddr("bob");
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        unauthorized = makeAddr("unauthorized");

        // Deploy mock token
        mockToken = new MockERC20();
        
        // Mint tokens to Alice
        mockToken.mint(_alice, 1000 * 10 ** 18);
        
        // Deploy wallet and set up EIP-7702
        wallet = new SmartWallet();
        _setCodeToEOA(address(wallet), _alice);
        
        // Initialize wallet with Alice as owner
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: _alice
        });
        
        vm.prank(_alice);
        SmartWallet(_alice).initialize(initialOwners);
        
        // Fund Alice with ETH
        vm.deal(_alice, 100 ether);
    }

    function _setCodeToEOA(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
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

    function test_ApproveNative_OnlySelf() public {
        uint256 amount = 1 ether;
        
        // Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        SmartWallet(_alice).approveNative(spender, amount);
        
        // Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert();
        SmartWallet(_alice).approveNative(spender, amount);
        
        // Should succeed for wallet owner (Alice) - since Alice IS the wallet in EIP-7702
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, amount * 2);
        assertEq(SmartWallet(_alice).nativeAllowance(spender), amount * 2);
    }

    function test_TransferFromNative_Success() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, allowanceAmount);
        
        uint256 initialBalance = recipient.balance;
        
        vm.expectEmit(true, true, false, true);
        emit TransferFromNative(
            address(SmartWallet(_alice)),
            recipient,
            transferAmount
        );
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromNative(
            _alice,
            recipient,
            transferAmount
        );
        
        assertTrue(success);
        assertEq(recipient.balance, initialBalance + transferAmount);
        assertEq(
            SmartWallet(_alice).nativeAllowance(spender),
            allowanceAmount - transferAmount
        );
    }

    function test_TransferFromNative_InsufficientAllowance() public {
        uint256 allowanceAmount = 1 ether;
        uint256 transferAmount = 2 ether;
        
        // Set up insufficient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, allowanceAmount);
        
        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.NativeAllowanceExceeded.selector);
        SmartWallet(_alice).transferFromNative(
            _alice,
            recipient,
            transferAmount
        );
    }

    function test_TransferFromNative_IncorrectSender() public {
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, 100 ether);
        
        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.IncorrectSender.selector);
        SmartWallet(_alice).transferFromNative(
            _bob, // Wrong sender - should be _alice (the wallet address)
            recipient,
            50 ether
        );
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

    function test_TransferFromNative_UnlimitedAllowance() public {
        uint256 transferAmount = 1 ether;
        
        // Set up unlimited allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, type(uint256).max);
        
        uint256 initialBalance = recipient.balance;
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromNative(
            _alice,
            recipient,
            transferAmount
        );
        
        assertTrue(success);
        assertEq(recipient.balance, initialBalance + transferAmount);
        // Unlimited allowance should remain unchanged
        assertEq(SmartWallet(_alice).nativeAllowance(spender), type(uint256).max);
    }

    // ============ ERC20 Token Tests ============

    function test_ApproveToken_Success() public {
        uint256 amount = 100 * 10 ** 18;
        
        vm.expectEmit(true, true, false, true);
        emit ApproveToken(address(mockToken), spender, amount);
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            amount
        );
        
        assertTrue(success);
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            amount
        );
    }

    function test_ApproveToken_OnlySelf() public {
        uint256 amount = 100 * 10 ** 18;
        
        // Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount);
        
        // Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert();
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount);
        
        // Should succeed for wallet owner (Alice) - since Alice IS the wallet in EIP-7702
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount * 2);
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            amount * 2
        );
    }

    function test_TransferFromToken_Success() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            allowanceAmount
        );
        
        uint256 initialBalance = mockToken.balanceOf(recipient);
        
        vm.expectEmit(true, true, false, true);
        emit TransferFromToken(
            address(mockToken),
            recipient,
            transferAmount
        );
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromToken(
            address(mockToken),
            _alice,
            recipient,
            transferAmount
        );
        
        assertTrue(success);
        assertEq(
            mockToken.balanceOf(recipient),
            initialBalance + transferAmount
        );
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            allowanceAmount - transferAmount
        );
    }

    function test_TransferFromToken_InsufficientAllowance() public {
        uint256 allowanceAmount = 100 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;
        
        // Set up insufficient allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            allowanceAmount
        );
        
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
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            100 * 10 ** 18
        );
        
        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.IncorrectSender.selector);
        SmartWallet(_alice).transferFromToken(
            address(mockToken),
            _bob, // Wrong sender - should be _alice (the wallet address)
            recipient,
            50 * 10 ** 18
        );
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
        uint256 transferAmount = 100 * 10 ** 18;
        
        // Set up unlimited allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            type(uint256).max
        );
        
        uint256 initialBalance = mockToken.balanceOf(recipient);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromToken(
            address(mockToken),
            _alice,
            recipient,
            transferAmount
        );
        
        assertTrue(success);
        assertEq(
            mockToken.balanceOf(recipient),
            initialBalance + transferAmount
        );
        // Unlimited allowance should remain unchanged
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            type(uint256).max
        );
    }

    // ============ Edge Cases and Integration Tests ============

    function test_MultipleSpenders() public {
        address spender2 = makeAddr("spender2");
        uint256 amount1 = 50 * 10 ** 18;
        uint256 amount2 = 75 * 10 ** 18;
        
        // Approve different amounts for different spenders
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount1);
        
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender2, amount2);
        
        // Verify allowances are independent
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender2),
            amount2
        );
    }

    function test_MultipleTokens() public {
        MockERC20 mockToken2 = new MockERC20();
        mockToken2.mint(_alice, 1000 * 10 ** 18);
        
        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;
        
        // Approve different amounts for different tokens
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken), spender, amount1);
        
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(address(mockToken2), spender, amount2);
        
        // Verify allowances are independent
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken2), spender),
            amount2
        );
    }

    function test_OverwriteAllowances() public {
        uint256 initialAmount = 100 * 10 ** 18;
        uint256 newAmount = 200 * 10 ** 18;
        
        // Set initial allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            initialAmount
        );
        
        // Overwrite with new amount
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            newAmount
        );
        
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            newAmount
        );
    }

    // ============ Fuzz Tests ============

    function testFuzz_ApproveNative(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveNative(spender, amount);
        
        assertTrue(success);
        assertEq(SmartWallet(_alice).nativeAllowance(spender), amount);
    }

    function testFuzz_ApproveToken(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds
        
        vm.prank(_alice);
        bool success = SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            amount
        );
        
        assertTrue(success);
        assertEq(
            SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
            amount
        );
    }

    function testFuzz_TransferFromToken(
        uint256 allowanceAmount,
        uint256 transferAmount
    ) public {
        vm.assume(allowanceAmount <= mockToken.balanceOf(_alice));
        vm.assume(transferAmount <= allowanceAmount);
        vm.assume(transferAmount > 0);
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveToken(
            address(mockToken),
            spender,
            allowanceAmount
        );
        
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
            assertEq(
                SmartWallet(_alice).tokenAllowance(address(mockToken), spender),
                allowanceAmount - transferAmount
            );
        }
    }

    function testFuzz_TransferFromNative(
        uint256 allowanceAmount,
        uint256 transferAmount
    ) public {
        vm.assume(allowanceAmount <= _alice.balance);
        vm.assume(transferAmount <= allowanceAmount);
        vm.assume(transferAmount > 0);
        
        // Set up allowance
        vm.prank(_alice);
        SmartWallet(_alice).approveNative(spender, allowanceAmount);
        
        vm.prank(spender);
        bool success = SmartWallet(_alice).transferFromNative(
            _alice,
            recipient,
            transferAmount
        );
        
        assertTrue(success);
        assertEq(recipient.balance, transferAmount);
        
        if (allowanceAmount < type(uint256).max) {
            assertEq(
                SmartWallet(_alice).nativeAllowance(spender),
                allowanceAmount - transferAmount
            );
        }
    }
}
