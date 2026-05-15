// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base, MockERC20} from "./Base.t.sol";
import {BaseAuthorization} from "src/BaseAuthorization.sol";
import {SmartWallet} from "../src/SmartWallet.sol";
import {IAllowanceManager} from "../src/interfaces/IAllowanceManager.sol";
import {ISmartWallet} from "../src/interfaces/ISmartWallet.sol";
import {Call, BatchedCall} from "../src/Types.sol";
import {Static} from "../src/libraries/Static.sol";

// Contract that rejects ETH transfers
contract ETHRejectingContract {
    receive() external payable {
        revert("ETH transfer rejected");
    }
}

// Token that always fails transfers (returns false)
contract FailingToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false; // Always fail
    }
}

// Token that always reverts on transfers
contract RevertingToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("Transfer reverted");
    }
}

contract AllowanceManagerTest is Base {
    uint256 constant INITIAL_TOKEN_BALANCE = 1000 * 10 ** 18;
    uint256 constant INITIAL_ETH_BALANCE = 100 ether;

    SmartWallet public aliceSmartWallet;
    MockERC20 public mockToken;
    MockERC20 public mockToken2;
    address public spender;
    address public recipient;
    address public unauthorized;

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

    function _executeApproveWithRelayer(bytes memory data) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(aliceSmartWallet),
            value: 0,
            data: data
        });
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(address(aliceSmartWallet))
        });
        bytes memory validatorData = _constructRelayerSignature(
            address(aliceSmartWallet),
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );
        vm.prank(relayer);
        ISmartWallet(address(aliceSmartWallet)).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function _approveNative(address spenderAddr, uint256 amount) internal {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH,
            spenderAddr,
            amount
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );
    }

    function _approveToken(
        address token,
        address spenderAddr,
        uint256 amount
    ) internal {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            token,
            spenderAddr,
            amount
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );
    }

    function _approveNativeWithRelayer(
        address spenderAddr,
        uint256 amount
    ) internal {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH,
            spenderAddr,
            amount
        );

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );
    }

    function _approveTokenWithRelayer(
        address token,
        address spenderAddr,
        uint256 amount
    ) internal {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            token,
            spenderAddr,
            amount
        );

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );
    }

    function _transferFromNativeCallAsSpender(
        address _recipient,
        uint256 _amount
    ) internal {
        vm.prank(spender);
        IAllowanceManager(address(aliceSmartWallet)).transferFromNative(
            _recipient,
            _amount
        );
    }

    function _transferFromTokenCallAsSpender(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        vm.prank(spender);
        IAllowanceManager(address(aliceSmartWallet)).transferFromToken(
            _token,
            _recipient,
            _amount
        );
    }

    function setUp() public override {
        super.setUp();
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        unauthorized = makeAddr("unauthorized");
        relayer = makeAddr("relayer");

        mockToken = new MockERC20();
        mockToken2 = new MockERC20();
        aliceSmartWallet = SmartWallet(payable(_aliceWallet));

        assertTrue(
            mockToken.transfer(address(aliceSmartWallet), INITIAL_TOKEN_BALANCE)
        );
        assertTrue(
            mockToken2.transfer(
                address(aliceSmartWallet),
                INITIAL_TOKEN_BALANCE
            )
        );
        vm.deal(address(aliceSmartWallet), INITIAL_ETH_BALANCE);
    }

    // ============ Native ETH Tests ============

    function test_RevertWhen_ApproveNative_DirectCallByNonOwner() public {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH,
            spender,
            1 ether
        );
        bytes4 err = BaseAuthorization.NotFromSelf.selector;

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(err));
        aliceSmartWallet.batchApproveToken(approvals);

        vm.prank(_bob);
        vm.expectRevert(abi.encodeWithSelector(err));
        aliceSmartWallet.batchApproveToken(approvals);
    }

    function test_ApproveNative_ByOwnerViaExecute_Success() public {
        uint256 amount = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            Static.NATIVE_ETH,
            spender,
            amount
        );
        _approveNative(spender, amount);
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function test_TransferFromNative_Success() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;

        // Set up allowance through execute
        _approveNative(spender, allowanceAmount);

        uint256 initialBalance = recipient.balance;

        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.TransferFromNative(
            address(aliceSmartWallet),
            spender,
            recipient,
            transferAmount
        );

        vm.prank(spender);
        bool success = aliceSmartWallet.transferFromNative(
            recipient,
            transferAmount
        );

        assertTrue(success);

        assertEq(recipient.balance, initialBalance + transferAmount);
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount - transferAmount
        );
    }

    function test_RevertWhen_TransferFromNative_InsufficientAllowance() public {
        uint256 allowanceAmount = 1 ether;
        uint256 transferAmount = 2 ether;

        // Should fail since there is no allowance set
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            0
        );
        vm.expectRevert(IAllowanceManager.NativeAllowanceExceeded.selector);
        _transferFromNativeCallAsSpender(recipient, transferAmount);

        // Set up insufficient allowance through execute
        _approveNative(spender, allowanceAmount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount
        );
        vm.expectRevert(IAllowanceManager.NativeAllowanceExceeded.selector);
        _transferFromNativeCallAsSpender(recipient, transferAmount);
    }

    function test_TransferFromNative_ZeroAmount() public {
        _transferFromNativeCallAsSpender(recipient, 0);
    }

    function test_TransferFromNative_UnlimitedAllowance() public {
        uint256 transferAmount = 1 ether;

        // Set up unlimited allowance through execute
        _approveNative(spender, type(uint256).max);

        uint256 initialBalance = recipient.balance;

        _transferFromNativeCallAsSpender(recipient, transferAmount);

        assertEq(recipient.balance, initialBalance + transferAmount);
        // Unlimited allowance should remain unchanged
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            type(uint256).max
        );
    }

    // ============ ERC20 Token Tests ============

    function test_ApproveToken_Success() public {
        uint256 amount = 100 * 10 ** 18;

        // Test 1: Should fail for unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo({
            token: address(mockToken),
            spender: spender,
            amount: amount
        });
        aliceSmartWallet.batchApproveToken(approvals);

        // Test 2: Should fail for external address (Bob)
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        IAllowanceManager.ApprovalInfo[]
            memory approvals2 = new IAllowanceManager.ApprovalInfo[](1);
        approvals2[0] = IAllowanceManager.ApprovalInfo({
            token: address(mockToken),
            spender: spender,
            amount: amount
        });
        aliceSmartWallet.batchApproveToken(approvals2);

        // Test 3: Should succeed for wallet owner (Alice) through execute
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken),
            spender,
            amount
        );

        _approveToken(address(mockToken), spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount
        );
    }

    function test_TransferFromToken_Success() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Set up allowance through execute
        _approveToken(address(mockToken), spender, allowanceAmount);

        uint256 initialBalance = mockToken.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.TransferFromToken(
            address(aliceSmartWallet),
            spender,
            address(mockToken),
            recipient,
            transferAmount
        );

        _transferFromTokenCallAsSpender(
            address(mockToken),
            recipient,
            transferAmount
        );

        assertEq(
            mockToken.balanceOf(recipient),
            initialBalance + transferAmount
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            allowanceAmount - transferAmount
        );
    }

    function test_RevertWhen_TransferFromToken_InsufficientAllowance() public {
        uint256 allowanceAmount = 100 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;

        // Should fail since there is no allowance set
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            0
        );
        vm.expectRevert(IAllowanceManager.TokenAllowanceExceeded.selector);
        _transferFromTokenCallAsSpender(
            address(mockToken),
            recipient,
            transferAmount
        );
        // Set up insufficient allowance through execute
        _approveToken(address(mockToken), spender, allowanceAmount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            allowanceAmount
        );
        vm.expectRevert(IAllowanceManager.TokenAllowanceExceeded.selector);
        _transferFromTokenCallAsSpender(
            address(mockToken),
            recipient,
            transferAmount
        );
    }

    function test_TransferFromToken_ZeroAmount() public {
        _transferFromTokenCallAsSpender(address(mockToken), recipient, 0);
    }

    function test_TransferFromToken_UnlimitedAllowance() public {
        uint256 transferAmount = 100 * 10 ** 18;

        // Set up unlimited allowance through execute
        _approveToken(address(mockToken), spender, type(uint256).max);

        uint256 initialBalance = mockToken.balanceOf(recipient);

        _transferFromTokenCallAsSpender(
            address(mockToken),
            recipient,
            transferAmount
        );

        assertEq(
            mockToken.balanceOf(recipient),
            initialBalance + transferAmount
        );
        // Unlimited allowance should remain unchanged
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            type(uint256).max
        );
    }

    // ============ Edge Cases and Integration Tests ============

    function test_MultipleSpenders_Success() public {
        address spender2 = makeAddr("spender2");
        uint256 amount1 = 50 * 10 ** 18;
        uint256 amount2 = 75 * 10 ** 18;

        // Approve different amounts for different spenders through execute
        _approveToken(address(mockToken), spender, amount1);

        _approveToken(address(mockToken), spender2, amount2);

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender2),
            amount2
        );
    }

    function test_MultipleTokens_Success() public {
        // mockToken2 is already deployed in setUp()
        // Just mint tokens to wallet
        mockToken2.mint(address(aliceSmartWallet), INITIAL_TOKEN_BALANCE);

        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;

        // Approve different amounts for different tokens through execute
        _approveToken(address(mockToken), spender, amount1);

        _approveToken(address(mockToken2), spender, amount2);

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken2), spender),
            amount2
        );
    }

    function test_OverwriteAllowances_Success() public {
        uint256 initialAmount = 100 * 10 ** 18;
        uint256 newAmount = 200 * 10 ** 18;

        // Set initial allowance through execute
        _approveToken(address(mockToken), spender, initialAmount);

        // Overwrite with new amount through execute
        _approveToken(address(mockToken), spender, newAmount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            newAmount
        );
    }

    // ============ Unified Mapping Tests ============

    function test_UnifiedMapping_NativeAndTokenIndependent_Success() public {
        uint256 nativeAmount = 5 ether;
        uint256 tokenAmount = 300 * 10 ** 18;

        // Set up both native and token allowances through execute
        _approveNative(spender, nativeAmount);

        _approveToken(address(mockToken), spender, tokenAmount);

        // Verify they are stored independently in the unified mapping
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            tokenAmount
        );

        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
    }

    function test_UnifiedMapping_DifferentSpenders_Success() public {
        address spender2 = makeAddr("spender2");
        uint256 nativeAmount1 = 3 ether;
        uint256 nativeAmount2 = 7 ether;
        uint256 tokenAmount1 = 150 * 10 ** 18;
        uint256 tokenAmount2 = 250 * 10 ** 18;

        // Set up allowances for different spenders through execute
        _approveNative(spender, nativeAmount1);
        _approveNative(spender2, nativeAmount2);

        _approveToken(address(mockToken), spender, tokenAmount1);
        _approveToken(address(mockToken), spender2, tokenAmount2);

        // Verify all allowances are stored correctly in the unified mapping
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount1
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender2),
            nativeAmount2
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            tokenAmount1
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender2),
            tokenAmount2
        );
    }

    // ============ Fuzz Tests ============

    function testFuzz_ApproveNative(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _approveNative(spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function testFuzz_ApproveToken(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _approveToken(address(mockToken), spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
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
        _approveToken(address(mockToken), spender, allowanceAmount);

        _transferFromTokenCallAsSpender(
            address(mockToken),
            recipient,
            transferAmount
        );

        assertEq(mockToken.balanceOf(recipient), transferAmount);

        if (allowanceAmount < type(uint256).max) {
            assertEq(
                aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
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
        _approveNative(spender, allowanceAmount);

        _transferFromNativeCallAsSpender(recipient, transferAmount);

        assertEq(recipient.balance, transferAmount);

        if (allowanceAmount < type(uint256).max) {
            assertEq(
                aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
                allowanceAmount - transferAmount
            );
            assertEq(
                aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
                allowanceAmount - transferAmount
            );
        }
    }

    // ============ Transfer Failure Tests ============

    function test_RevertWhen_TransferNativeFailed() public {
        uint256 allowanceAmount = 2 ether;
        uint256 transferAmount = 1 ether;

        // Set up allowance through execute
        _approveNative(spender, allowanceAmount);

        // Deploy a contract that rejects ETH transfers
        ETHRejectingContract rejectingContract = new ETHRejectingContract();

        vm.expectRevert(IAllowanceManager.TransferNativeFailed.selector);
        _transferFromNativeCallAsSpender(
            address(rejectingContract),
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            allowanceAmount
        );
    }

    function test_RevertWhen_TokenTransferFailed() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Create a token that always fails transfers
        FailingToken failingToken = new FailingToken();

        // Mint tokens directly to the wallet
        failingToken.mint(address(aliceSmartWallet), INITIAL_TOKEN_BALANCE);

        // Approve allowance for the failing token through execute
        _approveToken(address(failingToken), spender, allowanceAmount);

        vm.expectRevert();
        _transferFromTokenCallAsSpender(
            address(failingToken),
            recipient,
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(failingToken), spender),
            allowanceAmount
        );
    }

    function test_RevertWhen_TokenTransferReverts() public {
        uint256 allowanceAmount = 200 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Create a token that always reverts on transfers
        RevertingToken revertingToken = new RevertingToken();

        // Mint tokens directly to the wallet
        revertingToken.mint(address(aliceSmartWallet), INITIAL_TOKEN_BALANCE);

        // Approve allowance for the reverting token through execute
        _approveToken(address(revertingToken), spender, allowanceAmount);

        // The token transfer should revert, but the AllowanceManager should catch it
        // and revert with SafeERC20FailedOperation
        vm.expectRevert();
        _transferFromTokenCallAsSpender(
            address(revertingToken),
            recipient,
            transferAmount
        );

        // Verify allowance was not consumed
        assertEq(
            aliceSmartWallet.getTokenAllowance(
                address(revertingToken),
                spender
            ),
            allowanceAmount
        );
    }

    // ============ ExecuteWithRelayer Tests ============

    function test_ApproveNative_Success_WithRelayer() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            Static.NATIVE_ETH,
            spender,
            amount
        );

        _approveNativeWithRelayer(spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function test_ApproveToken_Success_WithRelayer() public {
        uint256 amount = 100 * 10 ** 18;

        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken),
            spender,
            amount
        );

        _approveTokenWithRelayer(address(mockToken), spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount
        );
    }

    // ============ Batch Approve Token Tests ============

    function test_BatchApproveToken_Success() public {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](3);

        approvals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            spender,
            100 * 10 ** 18
        );
        approvals[1] = IAllowanceManager.ApprovalInfo(
            address(mockToken2),
            spender,
            200 * 10 ** 18
        );
        approvals[2] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH, // Test native ETH in batch
            recipient,
            1 ether
        );

        // Expect events for each approval
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken),
            spender,
            100 * 10 ** 18
        );
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken2),
            spender,
            200 * 10 ** 18
        );
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            Static.NATIVE_ETH,
            recipient,
            1 ether
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );

        // Verify all allowances were set correctly
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            100 * 10 ** 18
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken2), spender),
            200 * 10 ** 18
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            1 ether
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            1 ether
        );
    }

    function test_BatchApproveToken_WithRelayer() public {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](2);

        approvals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            spender,
            100 * 10 ** 18
        );
        approvals[1] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH, // Test native ETH
            recipient,
            2 ether
        );

        // Expect events for each approval
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken),
            spender,
            100 * 10 ** 18
        );
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            Static.NATIVE_ETH,
            recipient,
            2 ether
        );

        _executeApproveWithRelayer(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );

        // Verify all allowances were set correctly
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            100 * 10 ** 18
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            2 ether
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            2 ether
        );
    }

    function test_BatchApproveToken_EmptyArrays() public {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](0);

        // Should succeed with empty array
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );
    }

    function test_BatchApproveToken_SingleElement() public {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);

        approvals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            spender,
            100 * 10 ** 18
        );

        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken),
            spender,
            100 * 10 ** 18
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            100 * 10 ** 18
        );
    }

    function test_BatchApproveToken_OverwriteExisting() public {
        // Set initial allowances
        _approveToken(address(mockToken), spender, 50 * 10 ** 18);
        _approveNative(recipient, 75 * 10 ** 18);

        // Now batch overwrite them
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](2);

        approvals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            spender,
            150 * 10 ** 18 // New amount
        );
        approvals[1] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH,
            recipient,
            250 * 10 ** 18 // New amount
        );

        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            address(mockToken),
            spender,
            150 * 10 ** 18
        );
        vm.expectEmit(true, true, true, true);
        emit IAllowanceManager.ApproveToken(
            address(aliceSmartWallet),
            Static.NATIVE_ETH,
            recipient,
            250 * 10 ** 18
        );

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );

        // Verify allowances were overwritten
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            150 * 10 ** 18
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            250 * 10 ** 18
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            250 * 10 ** 18
        );
    }

    function test_RevertWhen_BatchApproveToken_InvalidSpender() public {
        // Test with single invalid spender (address(0))
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            address(0), // Invalid spender
            100 * 10 ** 18
        );

        vm.expectRevert(IAllowanceManager.InvalidSpender.selector);
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );

        // Test with multiple approvals where one has invalid spender
        IAllowanceManager.ApprovalInfo[]
            memory multipleApprovals = new IAllowanceManager.ApprovalInfo[](3);
        multipleApprovals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            spender, // Valid spender
            50 * 10 ** 18
        );
        multipleApprovals[1] = IAllowanceManager.ApprovalInfo(
            address(mockToken2),
            address(0), // Invalid spender in the middle
            75 * 10 ** 18
        );
        multipleApprovals[2] = IAllowanceManager.ApprovalInfo(
            Static.NATIVE_ETH,
            recipient, // Valid spender
            1 ether
        );

        vm.expectRevert(IAllowanceManager.InvalidSpender.selector);
        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                multipleApprovals
            )
        );

        // Verify no allowances were set (transaction should revert entirely)
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            0
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken2), address(0)),
            0
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, recipient),
            0
        );
    }

    function test_RevertWhen_BathApproveToken_UnauthorizedAccess() public {
        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](1);
        approvals[0] = IAllowanceManager.ApprovalInfo(
            address(mockToken),
            spender,
            100 * 10 ** 18
        );

        // Try to call directly as unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        aliceSmartWallet.batchApproveToken(approvals);

        // Try to call as external address (Bob)
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector)
        );
        aliceSmartWallet.batchApproveToken(approvals);
    }

    function testFuzz_BatchApproveToken(uint256[] calldata amounts) public {
        vm.assume(amounts.length <= 5); // Reduced upper bound to avoid gas issues
        vm.assume(amounts.length > 0);

        IAllowanceManager.ApprovalInfo[]
            memory approvals = new IAllowanceManager.ApprovalInfo[](
                amounts.length
            );

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] <= type(uint128).max); // Reasonable bounds
            address token = i % 2 == 0
                ? address(mockToken)
                : address(mockToken2);
            address spenderAddr = i % 3 == 0
                ? spender
                : (i % 3 == 1 ? recipient : unauthorized);
            approvals[i] = IAllowanceManager.ApprovalInfo(
                token,
                spenderAddr,
                amounts[i]
            );
        }

        _executeApprove(
            abi.encodeWithSelector(
                IAllowanceManager.batchApproveToken.selector,
                approvals
            )
        );

        // Verify all allowances were set correctly
        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(
                aliceSmartWallet.getTokenAllowance(
                    approvals[i].token,
                    approvals[i].spender
                ),
                approvals[i].amount
            );
        }
    }

    // Note: transferFromNative and transferFromToken should only be called directly by external spenders
    // They are not designed to work through the execution path (execute/executeWithRelayer)
    // because msg.sender becomes the smart wallet in that context, not the spender

    function test_MultipleSpenders_WithRelayer() public {
        address spender2 = makeAddr("spender2");
        uint256 amount1 = 50 * 10 ** 18;
        uint256 amount2 = 75 * 10 ** 18;

        // Approve different amounts for different spenders through relayer
        _approveTokenWithRelayer(address(mockToken), spender, amount1);

        _approveTokenWithRelayer(address(mockToken), spender2, amount2);

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender2),
            amount2
        );
    }

    function test_MultipleTokens_WithRelayer() public {
        // mockToken2 is already deployed in setUp()
        // Just mint tokens to wallet
        mockToken2.mint(address(aliceSmartWallet), INITIAL_TOKEN_BALANCE);

        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;

        // Approve different amounts for different tokens through relayer
        _approveTokenWithRelayer(address(mockToken), spender, amount1);

        _approveTokenWithRelayer(address(mockToken2), spender, amount2);

        // Verify allowances are independent
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount1
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken2), spender),
            amount2
        );
    }

    function test_UnifiedMapping_NativeAndTokenIndependent_WithRelayer()
        public
    {
        uint256 nativeAmount = 5 ether;
        uint256 tokenAmount = 300 * 10 ** 18;

        // Set up both native and token allowances through relayer
        _approveNativeWithRelayer(spender, nativeAmount);

        _approveTokenWithRelayer(address(mockToken), spender, tokenAmount);

        // Verify they are stored independently in the unified mapping
        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            tokenAmount
        );

        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            nativeAmount
        );
    }

    function testFuzz_ApproveNative_WithRelayer(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _approveNativeWithRelayer(spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(Static.NATIVE_ETH, spender),
            amount
        );
    }

    function testFuzz_ApproveToken_WithRelayer(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable bounds

        _approveTokenWithRelayer(address(mockToken), spender, amount);

        assertEq(
            aliceSmartWallet.getTokenAllowance(address(mockToken), spender),
            amount
        );
    }
}
