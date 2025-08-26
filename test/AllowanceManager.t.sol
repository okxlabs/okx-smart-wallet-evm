// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {IAllowanceManager} from "src/interfaces/IAllowanceManager.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import {InitialOwner} from "src/Types.sol";
import {Static} from "../src/libraries/Static.sol";
import {MockMaliciousERC20} from "src/test/MockMaliciousERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Contract that rejects ETH transfers
contract ETHRejectingContract {
    receive() external payable {
        revert("ETH transfer rejected");
    }
}

// Token that always fails transfers (returns false)
contract FailingToken {
    string public name = "FailingToken";
    string public symbol = "FAIL";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false; // Always fail
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure returns (bool) {
        return false; // Always fail
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Token that always reverts on transfers
contract RevertingToken {
    string public name = "RevertingToken";
    string public symbol = "REVERT";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("Transfer reverted");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure returns (bool) {
        revert("TransferFrom reverted");
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract AllowanceManagerTest is Test {
    SmartWallet public wallet;
    MockERC20 public mockToken;
    MockERC20 public mockToken2;
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

    event NativeAllowanceUpdated(address indexed spender, uint256 newAllowance);

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

        // Deploy mock tokens
        mockToken = new MockERC20();
        mockToken2 = new MockERC20();

        // Deploy wallet implementation
        SmartWallet implementation = new SmartWallet();

        // Set up EIP-7702: Alice's EOA gets the wallet code
        _setCodeToEOA(address(implementation), _alice);
        wallet = SmartWallet(payable(_alice));

        // Initialize wallet with Alice as owner
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(0x1) // Mock validator address
        });

        vm.prank(_alice);
        wallet.initialize(initialOwners);

        // Transfer tokens to wallet
        bool success1 = mockToken.transfer(address(wallet), 1000 * 10 ** 18);
        bool success2 = mockToken2.transfer(address(wallet), 1000 * 10 ** 18);
        assertTrue(success1, "Token transfer failed");
        assertTrue(success2, "Token2 transfer failed");

        // Fund wallet with ETH
        vm.deal(address(wallet), 100 ether);
    }

    function _setCodeToEOA(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
    }

    // ============ Native ETH Tests ============

    function test_ApproveNative_Success() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, false, true);
        emit ApproveNative(address(wallet), spender, amount);

        vm.prank(_alice);
        bool success = wallet.approveNative(spender, amount);

        assertTrue(success);
        assertEq(wallet.nativeAllowance(spender), amount);
        // Verify it's stored in the unified mapping
        assertEq(wallet.tokenAllowance(Static.NATIVE_ETH, spender), amount);
    }

    function test_ApproveNative_OnlySelf() public {
        uint256 amount = 1 ether;

        // Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        wallet.approveNative(spender, amount);

        // Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert();
        wallet.approveNative(spender, amount);

        // Should succeed for wallet owner (Alice) - since Alice IS the wallet in EIP-7702
        vm.prank(_alice);
        wallet.approveNative(spender, amount * 2);
        assertEq(wallet.nativeAllowance(spender), amount * 2);
        assertEq(wallet.tokenAllowance(Static.NATIVE_ETH, spender), amount * 2);
    }

    function test_TransferFromNative_Success() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;

        // Set up allowance
        vm.prank(_alice);
        wallet.approveNative(spender, allowanceAmount);

        uint256 initialBalance = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit TransferFromNative(address(wallet), recipient, transferAmount);

        vm.prank(spender);
        bool success = wallet.transferFromNative(
            _alice,
            recipient,
            transferAmount
        );

        assertTrue(success);
        assertEq(recipient.balance, initialBalance + transferAmount);
        assertEq(
            wallet.nativeAllowance(spender),
            allowanceAmount - transferAmount
        );
        assertEq(
            wallet.tokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount - transferAmount
        );
    }

    function test_TransferFromNative_InsufficientAllowance() public {
        uint256 allowanceAmount = 1 ether;
        uint256 transferAmount = 2 ether;

        // Set up insufficient allowance
        vm.prank(_alice);
        wallet.approveNative(spender, allowanceAmount);

        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.NativeAllowanceExceeded.selector);
        wallet.transferFromNative(_alice, recipient, transferAmount);
    }

    function test_TransferFromNative_IncorrectSender() public {
        vm.prank(_alice);
        wallet.approveNative(spender, 100 ether);

        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.IncorrectSender.selector);
        wallet.transferFromNative(
            _bob, // Wrong sender - should be _alice (the wallet address)
            recipient,
            50 ether
        );
    }

    function test_TransferFromNative_ZeroAmount() public {
        vm.prank(spender);
        bool success = wallet.transferFromNative(_alice, recipient, 0);
        assertTrue(success);
    }

    function test_TransferFromNative_UnlimitedAllowance() public {
        uint256 transferAmount = 1 ether;

        // Set up unlimited allowance
        vm.prank(_alice);
        wallet.approveNative(spender, type(uint256).max);

        uint256 initialBalance = recipient.balance;

        vm.prank(spender);
        bool success = wallet.transferFromNative(
            _alice,
            recipient,
            transferAmount
        );

        assertTrue(success);
        assertEq(recipient.balance, initialBalance + transferAmount);
        // Unlimited allowance should remain unchanged
        assertEq(wallet.nativeAllowance(spender), type(uint256).max);
        assertEq(
            wallet.tokenAllowance(Static.NATIVE_ETH, spender),
            type(uint256).max
        );
    }

    // ============ ERC20 Token Tests ============

    function test_ApproveToken_Success() public {
        uint256 amount = 100 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit ApproveToken(address(mockToken), spender, amount);

        vm.prank(_alice);
        bool success = wallet.approveToken(address(mockToken), spender, amount);

        assertTrue(success);
        assertEq(wallet.tokenAllowance(address(mockToken), spender), amount);
    }

    function test_ApproveToken_OnlySelf() public {
        uint256 amount = 100 * 10 ** 18;

        // Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        wallet.approveToken(address(mockToken), spender, amount);

        // Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert();
        wallet.approveToken(address(mockToken), spender, amount);

        // Should succeed for wallet owner (Alice) - since Alice IS the wallet in EIP-7702
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, amount * 2);
        assertEq(
            wallet.tokenAllowance(address(mockToken), spender),
            amount * 2
        );
    }

    function test_TransferFromToken_Success() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Set up allowance
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, allowanceAmount);

        uint256 initialBalance = mockToken.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit TransferFromToken(address(mockToken), recipient, transferAmount);

        vm.prank(spender);
        bool success = wallet.transferFromToken(
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
            wallet.tokenAllowance(address(mockToken), spender),
            allowanceAmount - transferAmount
        );
    }

    function test_TransferFromToken_InsufficientAllowance() public {
        uint256 allowanceAmount = 100 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;

        // Set up insufficient allowance
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, allowanceAmount);

        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.TokenAllowanceExceeded.selector);
        wallet.transferFromToken(
            address(mockToken),
            _alice,
            recipient,
            transferAmount
        );
    }

    function test_TransferFromToken_IncorrectSender() public {
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, 100 * 10 ** 18);

        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.IncorrectSender.selector);
        wallet.transferFromToken(
            address(mockToken),
            _bob, // Wrong sender - should be _alice (the wallet address)
            recipient,
            50 * 10 ** 18
        );
    }

    function test_TransferFromToken_ZeroAmount() public {
        vm.prank(spender);
        bool success = wallet.transferFromToken(
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
        wallet.approveToken(address(mockToken), spender, type(uint256).max);

        uint256 initialBalance = mockToken.balanceOf(recipient);

        vm.prank(spender);
        bool success = wallet.transferFromToken(
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
            wallet.tokenAllowance(address(mockToken), spender),
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
        wallet.approveToken(address(mockToken), spender, amount1);

        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender2, amount2);

        // Verify allowances are independent
        assertEq(wallet.tokenAllowance(address(mockToken), spender), amount1);
        assertEq(wallet.tokenAllowance(address(mockToken), spender2), amount2);
    }

    function test_MultipleTokens() public {
        // mockToken2 is already deployed in setUp()
        // Just mint tokens to alice
        mockToken2.mint(_alice, 1000 * 10 ** 18);

        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;

        // Approve different amounts for different tokens
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, amount1);

        vm.prank(_alice);
        wallet.approveToken(address(mockToken2), spender, amount2);

        // Verify allowances are independent
        assertEq(wallet.tokenAllowance(address(mockToken), spender), amount1);
        assertEq(wallet.tokenAllowance(address(mockToken2), spender), amount2);
    }

    function test_OverwriteAllowances() public {
        uint256 initialAmount = 100 * 10 ** 18;
        uint256 newAmount = 200 * 10 ** 18;

        // Set initial allowance
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, initialAmount);

        // Overwrite with new amount
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, newAmount);

        assertEq(wallet.tokenAllowance(address(mockToken), spender), newAmount);
    }

    // ============ Unified Mapping Tests ============

    function test_UnifiedMapping_NativeAndTokenIndependent() public {
        uint256 nativeAmount = 5 ether;
        uint256 tokenAmount = 300 * 10 ** 18;

        // Set up both native and token allowances
        vm.prank(_alice);
        wallet.approveNative(spender, nativeAmount);

        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, tokenAmount);

        // Verify they are stored independently in the unified mapping
        assertEq(
            wallet.tokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
        assertEq(
            wallet.tokenAllowance(address(mockToken), spender),
            tokenAmount
        );

        // Verify the nativeAllowance function returns the correct value
        assertEq(wallet.nativeAllowance(spender), nativeAmount);
    }

    function test_UnifiedMapping_DifferentSpenders() public {
        address spender2 = makeAddr("spender2");
        uint256 nativeAmount1 = 3 ether;
        uint256 nativeAmount2 = 7 ether;
        uint256 tokenAmount1 = 150 * 10 ** 18;
        uint256 tokenAmount2 = 250 * 10 ** 18;

        // Set up allowances for different spenders
        vm.prank(_alice);
        wallet.approveNative(spender, nativeAmount1);
        vm.prank(_alice);
        wallet.approveNative(spender2, nativeAmount2);

        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender, tokenAmount1);
        vm.prank(_alice);
        wallet.approveToken(address(mockToken), spender2, tokenAmount2);

        // Verify all allowances are stored correctly in the unified mapping
        assertEq(
            wallet.tokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount1
        );
        assertEq(
            wallet.tokenAllowance(Static.NATIVE_ETH, spender2),
            nativeAmount2
        );
        assertEq(
            wallet.tokenAllowance(address(mockToken), spender),
            tokenAmount1
        );
        assertEq(
            wallet.tokenAllowance(address(mockToken), spender2),
            tokenAmount2
        );
    }

    // ============ Fuzz Tests ============

    function testFuzz_ApproveNative(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        vm.prank(_alice);
        bool success = wallet.approveNative(spender, amount);

        assertTrue(success);
        assertEq(wallet.nativeAllowance(spender), amount);
        assertEq(wallet.tokenAllowance(Static.NATIVE_ETH, spender), amount);
    }

    function testFuzz_ApproveToken(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        vm.prank(_alice);
        bool success = wallet.approveToken(address(mockToken), spender, amount);

        assertTrue(success);
        assertEq(wallet.tokenAllowance(address(mockToken), spender), amount);
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
        wallet.approveToken(address(mockToken), spender, allowanceAmount);

        vm.prank(spender);
        bool success = wallet.transferFromToken(
            address(mockToken),
            _alice,
            recipient,
            transferAmount
        );

        assertTrue(success);
        assertEq(mockToken.balanceOf(recipient), transferAmount);

        if (allowanceAmount < type(uint256).max) {
            assertEq(
                wallet.tokenAllowance(address(mockToken), spender),
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
        wallet.approveNative(spender, allowanceAmount);

        vm.prank(spender);
        bool success = wallet.transferFromNative(
            _alice,
            recipient,
            transferAmount
        );

        assertTrue(success);
        assertEq(recipient.balance, transferAmount);

        if (allowanceAmount < type(uint256).max) {
            assertEq(
                wallet.nativeAllowance(spender),
                allowanceAmount - transferAmount
            );
            assertEq(
                wallet.tokenAllowance(Static.NATIVE_ETH, spender),
                allowanceAmount - transferAmount
            );
        }
    }

    // ============ Transfer Failure Tests ============

    function test_TransferFromNative_TransferNativeFailed() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;

        // Set up allowance
        vm.prank(_alice);
        wallet.approveNative(spender, allowanceAmount);

        // Deploy a contract that rejects ETH transfers
        ETHRejectingContract rejectingContract = new ETHRejectingContract();

        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.TransferNativeFailed.selector);
        wallet.transferFromNative(
            _alice,
            address(rejectingContract),
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(wallet.nativeAllowance(spender), allowanceAmount);
        assertEq(
            wallet.tokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount
        );
    }

    function test_TransferFromToken_TokenTransferFailed() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Create a token that always fails transfers
        FailingToken failingToken = new FailingToken();

        // Mint tokens directly to the wallet
        failingToken.mint(address(wallet), 1000 * 10 ** 18);

        // Approve allowance for the failing token
        vm.prank(_alice);
        wallet.approveToken(address(failingToken), spender, allowanceAmount);

        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.TokenTransferFailed.selector);
        wallet.transferFromToken(
            address(failingToken),
            _alice,
            recipient,
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            wallet.tokenAllowance(address(failingToken), spender),
            allowanceAmount
        );
    }

    function test_TransferFromToken_TokenTransferReverts() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Create a token that always reverts on transfers
        RevertingToken revertingToken = new RevertingToken();

        // Mint tokens directly to the wallet
        revertingToken.mint(address(wallet), 1000 * 10 ** 18);

        // Approve allowance for the reverting token
        vm.prank(_alice);
        wallet.approveToken(address(revertingToken), spender, allowanceAmount);

        // The token transfer should revert, but the AllowanceManager should catch it
        // and revert with TokenTransferFailed
        vm.prank(spender);
        vm.expectRevert(IAllowanceManager.TokenTransferFailed.selector);
        wallet.transferFromToken(
            address(revertingToken),
            _alice,
            recipient,
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            wallet.tokenAllowance(address(revertingToken), spender),
            allowanceAmount
        );
    }
}
