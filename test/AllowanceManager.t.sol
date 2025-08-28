// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Base} from "./Base.t.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {IAllowanceManager} from "../src/interfaces/IAllowanceManager.sol";
import {ISmartWallet} from "../src/interfaces/ISmartWallet.sol";
import {MockERC20} from "../src/test/MockERC20.sol";
import {Call, BatchedCall} from "../src/Types.sol";
import {Static} from "../src/libraries/Static.sol";
import {BatchedCallLib} from "../src/libraries/BatchedCallLib.sol";
import {ERC712} from "../src/ERC712.sol";

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

contract AllowanceManagerTest is Base {
    SmartWallet public aliceSmartWallet;
    MockERC20 public mockToken;
    MockERC20 public mockToken2;
    address public spender;
    address public recipient;
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

    // Helper function to execute allowance manager calls through Alice's smart wallet
    function _executeApprove(bytes memory data) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(aliceSmartWallet),
            value: 0,
            data: data
        });
        vm.prank(_alice);
        ISmartWallet(address(aliceSmartWallet)).execute(calls);
    }

    // Helper function to execute allowance manager calls through relayer
    function _executeApproveWithRelayer(bytes memory data) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(aliceSmartWallet),
            value: 0,
            data: data
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(address(aliceSmartWallet)),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(address(aliceSmartWallet)).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            keccak256(abi.encodePacked(_alice)),
            _signHash(_alicePk, typedDataHash)
        );

        vm.prank(relayer);
        ISmartWallet(address(aliceSmartWallet)).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // Helper function to call transferFromNative directly as spender
    function _transferFromNativeCallAsSpender(
        address _from,
        address _recipient,
        uint256 _amount
    ) internal {
        vm.prank(spender);
        IAllowanceManager(address(aliceSmartWallet)).transferFromNative(
            _from,
            _recipient,
            _amount
        );
    }

    // Helper function to call transferFromToken directly as spender
    function _transferFromTokenCallAsSpender(
        address _token,
        address _from,
        address _recipient,
        uint256 _amount
    ) internal {
        vm.prank(spender);
        IAllowanceManager(address(aliceSmartWallet)).transferFromToken(
            _token,
            _from,
            _recipient,
            _amount
        );
    }

    function setUp() public override {
        super.setUp();
        // Set up additional test addresses
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        unauthorized = makeAddr("unauthorized");

        // Set up relayer
        (relayer, relayerPk) = makeAddrAndKey("relayer");

        // Deploy mock tokens
        mockToken = new MockERC20();
        mockToken2 = new MockERC20();

        // Use the smart wallet from Base setup
        aliceSmartWallet = SmartWallet(payable(_aliceWallet));

        // Transfer tokens to Alice's smart wallet
        bool success1 = mockToken.transfer(
            address(aliceSmartWallet),
            1000 * 10 ** 18
        );
        bool success2 = mockToken2.transfer(
            address(aliceSmartWallet),
            1000 * 10 ** 18
        );
        assertTrue(success1, "Token transfer failed");
        assertTrue(success2, "Token2 transfer failed");

        // Fund Alice's smart wallet with ETH
        vm.deal(address(aliceSmartWallet), 100 ether);
    }

    // ============ Native ETH Tests ============

    function test_ApproveNative_Success() public {
        uint256 amount = 1 ether;

        // Test 1: Should fail for unauthorized user - trying to call directly
        vm.prank(unauthorized);
        vm.expectRevert();
        aliceSmartWallet.approveNative(spender, amount);

        // Test 2: Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert();
        aliceSmartWallet.approveNative(spender, amount);

        // Test 3: Should succeed for wallet owner (Alice) through execute
        vm.expectEmit(true, true, false, true);
        emit ApproveNative(address(aliceSmartWallet), spender, amount);

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                amount
            )
        );

        assertEq(aliceSmartWallet.nativeAllowance(spender), amount);
        // Verify it's stored in the unified mapping
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function test_TransferFromNative_Success() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;

        // Set up allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                allowanceAmount
            )
        );

        uint256 initialBalance = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit TransferFromNative(
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        vm.prank(spender);
        bool success = aliceSmartWallet.transferFromNative(
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        assertTrue(success);

        assertEq(recipient.balance, initialBalance + transferAmount);
        assertEq(
            aliceSmartWallet.nativeAllowance(spender),
            allowanceAmount - transferAmount
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount - transferAmount
        );
    }

    function test_TransferFromNative_InsufficientAllowance() public {
        uint256 allowanceAmount = 1 ether;
        uint256 transferAmount = 2 ether;

        // Set up insufficient allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                allowanceAmount
            )
        );

        vm.expectRevert(IAllowanceManager.NativeAllowanceExceeded.selector);
        _transferFromNativeCallAsSpender(
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );
    }

    function test_TransferFromNative_IncorrectSender() public {
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                100 ether
            )
        );

        vm.expectRevert(IAllowanceManager.IncorrectSender.selector);
        _transferFromNativeCallAsSpender(
            _bob, // Wrong sender - should be address(aliceSmartWallet)
            recipient,
            50 ether
        );
    }

    function test_TransferFromNative_ZeroAmount() public {
        _transferFromNativeCallAsSpender(
            address(aliceSmartWallet),
            recipient,
            0
        );
    }

    function test_TransferFromNative_UnlimitedAllowance() public {
        uint256 transferAmount = 1 ether;

        // Set up unlimited allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                type(uint256).max
            )
        );

        uint256 initialBalance = recipient.balance;

        _transferFromNativeCallAsSpender(
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        assertEq(recipient.balance, initialBalance + transferAmount);
        // Unlimited allowance should remain unchanged
        assertEq(aliceSmartWallet.nativeAllowance(spender), type(uint256).max);
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            type(uint256).max
        );
    }

    // ============ ERC20 Token Tests ============

    function test_ApproveToken_Success() public {
        uint256 amount = 100 * 10 ** 18;

        // Test 1: Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        aliceSmartWallet.approveToken(address(mockToken), spender, amount);

        // Test 2: Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert();
        aliceSmartWallet.approveToken(address(mockToken), spender, amount);

        // Test 3: Should succeed for wallet owner (Alice) through execute
        vm.expectEmit(true, true, false, true);
        emit ApproveToken(address(mockToken), spender, amount);

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount
            )
        );

        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount
        );
    }

    function test_TransferFromToken_Success() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Set up allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                allowanceAmount
            )
        );

        uint256 initialBalance = mockToken.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit TransferFromToken(address(mockToken), recipient, transferAmount);

        _transferFromTokenCallAsSpender(
            address(mockToken),
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        assertEq(
            mockToken.balanceOf(recipient),
            initialBalance + transferAmount
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            allowanceAmount - transferAmount
        );
    }

    function test_TransferFromToken_InsufficientAllowance() public {
        uint256 allowanceAmount = 100 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;

        // Set up insufficient allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                allowanceAmount
            )
        );

        vm.expectRevert(IAllowanceManager.TokenAllowanceExceeded.selector);
        _transferFromTokenCallAsSpender(
            address(mockToken),
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );
    }

    function test_TransferFromToken_IncorrectSender() public {
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                100 * 10 ** 18
            )
        );

        vm.expectRevert(IAllowanceManager.IncorrectSender.selector);
        _transferFromTokenCallAsSpender(
            address(mockToken),
            _bob, // Wrong sender - should be address(aliceSmartWallet)
            recipient,
            50 * 10 ** 18
        );
    }

    function test_TransferFromToken_ZeroAmount() public {
        _transferFromTokenCallAsSpender(
            address(mockToken),
            address(aliceSmartWallet),
            recipient,
            0
        );
    }

    function test_TransferFromToken_UnlimitedAllowance() public {
        uint256 transferAmount = 100 * 10 ** 18;

        // Set up unlimited allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                type(uint256).max
            )
        );

        uint256 initialBalance = mockToken.balanceOf(recipient);

        _transferFromTokenCallAsSpender(
            address(mockToken),
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        assertEq(
            mockToken.balanceOf(recipient),
            initialBalance + transferAmount
        );
        // Unlimited allowance should remain unchanged
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            type(uint256).max
        );
    }

    // ============ Edge Cases and Integration Tests ============

    function test_MultipleSpenders() public {
        address spender2 = makeAddr("spender2");
        uint256 amount1 = 50 * 10 ** 18;
        uint256 amount2 = 75 * 10 ** 18;

        // Approve different amounts for different spenders through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount1
            )
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender2,
                amount2
            )
        );

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender2),
            amount2
        );
    }

    function test_MultipleTokens() public {
        // mockToken2 is already deployed in setUp()
        // Just mint tokens to wallet
        mockToken2.mint(address(aliceSmartWallet), 1000 * 10 ** 18);

        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;

        // Approve different amounts for different tokens through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount1
            )
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken2),
                spender,
                amount2
            )
        );

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken2), spender),
            amount2
        );
    }

    function test_OverwriteAllowances() public {
        uint256 initialAmount = 100 * 10 ** 18;
        uint256 newAmount = 200 * 10 ** 18;

        // Set initial allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                initialAmount
            )
        );

        // Overwrite with new amount through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                newAmount
            )
        );

        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            newAmount
        );
    }

    // ============ Unified Mapping Tests ============

    function test_UnifiedMapping_NativeAndTokenIndependent() public {
        uint256 nativeAmount = 5 ether;
        uint256 tokenAmount = 300 * 10 ** 18;

        // Set up both native and token allowances through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                nativeAmount
            )
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                tokenAmount
            )
        );

        // Verify they are stored independently in the unified mapping
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            tokenAmount
        );

        // Verify the nativeAllowance function returns the correct value
        assertEq(aliceSmartWallet.nativeAllowance(spender), nativeAmount);
    }

    function test_UnifiedMapping_DifferentSpenders() public {
        address spender2 = makeAddr("spender2");
        uint256 nativeAmount1 = 3 ether;
        uint256 nativeAmount2 = 7 ether;
        uint256 tokenAmount1 = 150 * 10 ** 18;
        uint256 tokenAmount2 = 250 * 10 ** 18;

        // Set up allowances for different spenders through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                nativeAmount1
            )
        );
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender2,
                nativeAmount2
            )
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                tokenAmount1
            )
        );
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender2,
                tokenAmount2
            )
        );

        // Verify all allowances are stored correctly in the unified mapping
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount1
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender2),
            nativeAmount2
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            tokenAmount1
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender2),
            tokenAmount2
        );
    }

    // ============ Fuzz Tests ============

    function testFuzz_ApproveNative(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                amount
            )
        );

        assertEq(aliceSmartWallet.nativeAllowance(spender), amount);
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function testFuzz_ApproveToken(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount
            )
        );

        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount
        );
    }

    function testFuzz_TransferFromToken(
        uint256 allowanceAmount,
        uint256 transferAmount
    ) public {
        vm.assume(
            allowanceAmount <= mockToken.balanceOf(address(aliceSmartWallet))
        );
        vm.assume(transferAmount <= allowanceAmount);
        vm.assume(transferAmount > 0);

        // Set up allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                allowanceAmount
            )
        );

        _transferFromTokenCallAsSpender(
            address(mockToken),
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        assertEq(mockToken.balanceOf(recipient), transferAmount);

        if (allowanceAmount < type(uint256).max) {
            assertEq(
                aliceSmartWallet.tokenAllowance(address(mockToken), spender),
                allowanceAmount - transferAmount
            );
        }
    }

    function testFuzz_TransferFromNative(
        uint256 allowanceAmount,
        uint256 transferAmount
    ) public {
        vm.assume(allowanceAmount <= address(aliceSmartWallet).balance);
        vm.assume(transferAmount <= allowanceAmount);
        vm.assume(transferAmount > 0);

        // Set up allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                allowanceAmount
            )
        );

        _transferFromNativeCallAsSpender(
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        assertEq(recipient.balance, transferAmount);

        if (allowanceAmount < type(uint256).max) {
            assertEq(
                aliceSmartWallet.nativeAllowance(spender),
                allowanceAmount - transferAmount
            );
            assertEq(
                aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
                allowanceAmount - transferAmount
            );
        }
    }

    // ============ Transfer Failure Tests ============

    function test_TransferFromNative_TransferNativeFailed() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;

        // Set up allowance through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                allowanceAmount
            )
        );

        // Deploy a contract that rejects ETH transfers
        ETHRejectingContract rejectingContract = new ETHRejectingContract();

        vm.expectRevert(IAllowanceManager.TransferNativeFailed.selector);
        _transferFromNativeCallAsSpender(
            address(aliceSmartWallet),
            address(rejectingContract),
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(aliceSmartWallet.nativeAllowance(spender), allowanceAmount);
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount
        );
    }

    function test_TransferFromToken_TokenTransferFailed() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Create a token that always fails transfers
        FailingToken failingToken = new FailingToken();

        // Mint tokens directly to the wallet
        failingToken.mint(address(aliceSmartWallet), 1000 * 10 ** 18);

        // Approve allowance for the failing token through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(failingToken),
                spender,
                allowanceAmount
            )
        );

        vm.expectRevert(IAllowanceManager.TokenTransferFailed.selector);
        _transferFromTokenCallAsSpender(
            address(failingToken),
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            aliceSmartWallet.tokenAllowance(address(failingToken), spender),
            allowanceAmount
        );
    }

    function test_TransferFromToken_TokenTransferReverts() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Create a token that always reverts on transfers
        RevertingToken revertingToken = new RevertingToken();

        // Mint tokens directly to the wallet
        revertingToken.mint(address(aliceSmartWallet), 1000 * 10 ** 18);

        // Approve allowance for the reverting token through execute
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(revertingToken),
                spender,
                allowanceAmount
            )
        );

        // The token transfer should revert, but the AllowanceManager should catch it
        // and revert with TokenTransferFailed
        vm.expectRevert(IAllowanceManager.TokenTransferFailed.selector);
        _transferFromTokenCallAsSpender(
            address(revertingToken),
            address(aliceSmartWallet),
            recipient,
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            aliceSmartWallet.tokenAllowance(address(revertingToken), spender),
            allowanceAmount
        );
    }

    // ============ ExecuteWithRelayer Tests ============

    function test_ApproveNative_Success_WithRelayer() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, false, true);
        emit ApproveNative(address(aliceSmartWallet), spender, amount);

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                amount
            )
        );

        assertEq(aliceSmartWallet.nativeAllowance(spender), amount);
        // Verify it's stored in the unified mapping
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function test_ApproveToken_Success_WithRelayer() public {
        uint256 amount = 100 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit ApproveToken(address(mockToken), spender, amount);

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount
            )
        );

        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount
        );
    }

    // Note: transferFromNative and transferFromToken should only be called directly by external spenders
    // They are not designed to work through the execution path (execute/executeWithRelayer)
    // because msg.sender becomes the smart wallet in that context, not the spender

    function test_MultipleSpenders_WithRelayer() public {
        address spender2 = makeAddr("spender2");
        uint256 amount1 = 50 * 10 ** 18;
        uint256 amount2 = 75 * 10 ** 18;

        // Approve different amounts for different spenders through relayer
        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount1
            )
        );

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender2,
                amount2
            )
        );

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender2),
            amount2
        );
    }

    function test_MultipleTokens_WithRelayer() public {
        // mockToken2 is already deployed in setUp()
        // Just mint tokens to wallet
        mockToken2.mint(address(aliceSmartWallet), 1000 * 10 ** 18);

        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;

        // Approve different amounts for different tokens through relayer
        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount1
            )
        );

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken2),
                spender,
                amount2
            )
        );

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken2), spender),
            amount2
        );
    }

    function test_UnifiedMapping_NativeAndTokenIndependent_WithRelayer()
        public
    {
        uint256 nativeAmount = 5 ether;
        uint256 tokenAmount = 300 * 10 ** 18;

        // Set up both native and token allowances through relayer
        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                nativeAmount
            )
        );

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                tokenAmount
            )
        );

        // Verify they are stored independently in the unified mapping
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            tokenAmount
        );

        // Verify the nativeAllowance function returns the correct value
        assertEq(aliceSmartWallet.nativeAllowance(spender), nativeAmount);
    }

    function testFuzz_ApproveNative_WithRelayer(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveNative.selector,
                spender,
                amount
            )
        );

        assertEq(aliceSmartWallet.nativeAllowance(spender), amount);
        assertEq(
            aliceSmartWallet.tokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function testFuzz_ApproveToken_WithRelayer(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.approveToken.selector,
                address(mockToken),
                spender,
                amount
            )
        );

        assertEq(
            aliceSmartWallet.tokenAllowance(address(mockToken), spender),
            amount
        );
    }
}
