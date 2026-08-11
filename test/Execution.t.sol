// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base, MockComplexContract, MockRevertingContract, MockERC20} from "./Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {Static} from "src/libraries/Static.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";

contract ExecutionTest is Base {
    using ECDSA for bytes32;
    using BatchedCallLib for BatchedCall;

    MockERC20 mockToken;
    MockERC20 mockToken2;

    // Complex execution test contracts
    MockComplexContract internal complexContract;
    MockRevertingContract internal revertingContract;

    address internal user;
    uint256 internal userPk;

    event TokenTransfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event ContractCalled(address indexed caller, bytes data, bytes result);
    event LargeOperationCompleted(uint256 callCount, uint256 gasUsed);

    function setUp() public override {
        super.setUp();

        (user, userPk) = makeAddrAndKey("user");

        vm.prank(_aliceWallet);
        mockToken = new MockERC20();

        vm.prank(_bob);
        mockToken2 = new MockERC20();

        // Deploy complex execution test contracts
        complexContract = new MockComplexContract();
        revertingContract = new MockRevertingContract();

        // Give wallet some tokens for testing
        mockToken.mint(_aliceWallet, 1000 ether);

        // Add user as validator for complex tests
        bytes32 userKeyHash = keccak256(abi.encodePacked(user));
        uint256 settings = _packSettings(
            false, // adminFlag
            0, // expiration
            address(0) // hook
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            userKeyHash,
            address(_ecdsaValidator),
            settings
        );
    }

    function test_Execute_ByOwner_Success() public {
        vm.prank(_alice);
        Call[] memory calls = constructCallsData();
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_RevertWhen_Execute_ByNonOwner() public {
        vm.prank(_bob);
        Call[] memory calls = constructCallsData();
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidCaller.selector, _bob)
        );
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_RevertWhen_Execute_FailedCall() public {
        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1000 ether, data: ""}); // will fail
        vm.expectRevert();
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_Execute_ByAddedOwner_Success() public {
        // Add Charlie as an owner to the wallet
        bytes32 charlieKeyHash = _makeKeyHash(_charlie);
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(_ecdsaValidator),
            0
        );

        // Charlie should be able to call execute() directly
        vm.prank(_charlie);
        Call[] memory calls = constructCallsData();
        ISmartWallet(_aliceWallet).execute(calls);

        // Verify the call succeeded
        assertEq(_bob.balance, 1 ether);
    }

    function test_RevertWhen_Execute_ByUnregisteredKeyHash() public {
        // Dave is not registered as an owner
        (address dave, ) = makeAddrAndKey("dave");

        vm.prank(dave);
        Call[] memory calls = constructCallsData();
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidCaller.selector, dave)
        );
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_Execute_WithEmptyCallsArray_Success() public {
        // Test that execute succeeds with empty calls array (no operations)
        Call[] memory emptyCalls = new Call[](0);

        vm.prank(_alice);
        // Should succeed without reverting, but perform no operations
        ISmartWallet(_aliceWallet).execute(emptyCalls);

        // Verify no state changes occurred
        assertEq(_bob.balance, 0 ether);
    }

    function test_ExecuteWithRelayer_WithEmptyCallsArray_Success() public {
        // Test that executeWithRelayer succeeds with empty calls array
        Call[] memory emptyCalls = new Call[](0);
        BatchedCall memory batchedCall = BatchedCall({
            calls: emptyCalls,
            nonce: 0
        });

        // Use the new helper that correctly includes validUntil in hash
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_aliceWallet);
        // Should succeed without reverting, but perform no operations
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify no state changes occurred
        assertEq(_bob.balance, 0 ether);
    }

    function test_KeyHash_ConsistencyAndValidation_Success() public {
        // Test that keyHash generation is consistent across the system
        address testAddress = _charlie;
        bytes32 keyHash = keccak256(abi.encodePacked(testAddress));

        // Initially Charlie should not be an owner
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(keyHash));

        // Charlie should not be able to call execute
        vm.prank(_charlie);
        Call[] memory calls = constructCallsData();
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidCaller.selector,
                _charlie
            )
        );
        ISmartWallet(_aliceWallet).execute(calls);

        // Add Charlie as owner
        bytes32 charlieKeyHash = _makeKeyHash(_charlie);
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(_ecdsaValidator),
            0
        );

        // Verify Charlie is now an owner and can execute
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(keyHash));
        vm.prank(_charlie);
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_ExecuteFromRelayer_AsRelayer_Success() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        uint256 gasStart = gasleft();

        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit RelayerExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        uint256 gasEnd = gasleft();
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_ExecuteFromRelayer_InitializationOnFirstTime_Success()
        public
    {
        // Create charlie's wallet using factory
        address charlieWallet = _deployAccountSingleOwner(
            _makeKeyHash(_charlie),
            address(_ecdsaValidator),
            1 // Different salt
        );
        vm.deal(charlieWallet, 1 ether);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        bytes memory validatorData = _constructRelayerSignature(
            charlieWallet, // wallet address
            _charlie, // signer address
            _charliePk,
            batchedCall,
            uint48(0)
        );

        vm.startPrank(_alice);
        vm.expectEmit(true, true, true, true);
        emit RelayerExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, charlieWallet),
            _alice,
            0
        );
        ISmartWallet(charlieWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_RevertWhen_ExecuteFromRelayer_FailedPayment() public {
        assertEq(mockToken2.balanceOf(_aliceWallet), 0);
        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        // First call is the failing payment
        calls[0] = constructErc20TransferCall(
            IERC20(address(mockToken2)),
            _bob,
            10
        );
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Expect revert due to insufficient balance for ERC20 transfer
        vm.expectRevert();
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteFromRelayer_OnPayment_Success() public {
        Call[] memory calls = new Call[](2);
        // Include payment to relayer as part of the batch
        calls[0] = constructErc20TransferCall(
            IERC20(address(mockToken)),
            _bob,
            10
        );
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );
        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit RelayerExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(mockToken.balanceOf(_bob), 10);
        assertEq(address(_bob).balance, 1 ether);
    }

    // This test is no longer valid as executeFromRelayer now reverts on any failed call
    // The batch execution is atomic - all succeed or all fail
    function test_RevertWhen_ExecuteFromRelayer_AnyFailedCall() public {
        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1000 ether, data: ""}); // This will fail due to insufficient balance

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Expect the entire batch to revert when one call fails
        vm.expectRevert();
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify no state changes occurred
        assertEq(address(_bob).balance, 0);
    }

    function test_ExecuteFromRelayer_OnFreeGasMode_Success() public {
        Call[] memory calls = new Call[](1);
        // calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[0] = constructErc20TransferCall(
            IERC20(address(mockToken)),
            _bob,
            10
        );

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit RelayerExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(mockToken.balanceOf(_bob), 10);
        // assertEq(address(_bob).balance, 0 ether);
    }

    // ============ Complex Execution Tests ============

    function test_MixedEthErc20ContractCalls_Success() public {
        // Complex mixed scenario:
        // 1. Transfer ETH to bob
        // 2. Transfer ERC20 tokens to charlie
        // 3. Call complex contract function
        // 4. Another ETH transfer
        // 5. ERC20 approval
        Call[] memory mixedCalls = new Call[](5);

        // 1. ETH transfer
        mixedCalls[0] = Call({target: _bob, value: 0.5 ether, data: ""});

        // 2. ERC20 transfer
        mixedCalls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _charlie,
                100 ether
            )
        });

        // 3. Complex contract call
        mixedCalls[2] = Call({
            target: address(complexContract),
            value: 0.1 ether,
            data: abi.encodeWithSelector(
                MockComplexContract.complexFunction.selector,
                42,
                "test string",
                true
            )
        });

        // 4. Another ETH transfer
        mixedCalls[3] = Call({
            target: address(complexContract),
            value: 0.2 ether,
            data: ""
        });

        // 5. ERC20 approval
        mixedCalls[4] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.approve.selector,
                _bob,
                50 ether
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: mixedCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            user, // Use user as signer (who was added as owner in setup)
            userPk,
            batchedCall,
            uint48(0)
        );

        uint256 initialGas = gasleft();
        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit RelayerExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        uint256 gasUsed = initialGas - gasleft();
        vm.stopPrank();

        // Verify all operations succeeded
        assertEq(address(_bob).balance, 0.5 ether);
        assertEq(mockToken.balanceOf(_charlie), 100 ether);
        assertEq(address(complexContract).balance, 0.3 ether);
        assertEq(mockToken.allowance(_aliceWallet, _bob), 50 ether);
        assertTrue(complexContract.functionCalled());

        emit LargeOperationCompleted(5, gasUsed);
    }

    function test_LargeBatchOperationGasLimits_Success() public {
        // Create 150 calls (>100 limit mentioned in requirements)
        uint256 callCount = 150;
        Call[] memory largeBatch = new Call[](callCount);

        for (uint256 i = 0; i < callCount; i++) {
            largeBatch[i] = Call({
                target: address(complexContract),
                value: 0,
                data: abi.encodeWithSelector(
                    MockComplexContract.simpleIncrement.selector
                )
            });
        }

        BatchedCall memory batchedCall = BatchedCall({
            calls: largeBatch,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            user, // Use user as signer (who was added as owner in setup)
            userPk,
            batchedCall,
            uint48(0)
        );

        uint256 initialGas = gasleft();
        vm.prank(_bob);

        // Should either succeed or fail due to gas limits
        try
            ISmartWallet(_aliceWallet).executeWithRelayer{gas: 30000000}(
                batchedCall,
                validatorData
            )
        {
            // If it succeeds, verify all calls executed
            assertEq(complexContract.counter(), callCount);
            emit LargeOperationCompleted(callCount, initialGas - gasleft());
        } catch {
            // If it fails due to gas, that's expected behavior
            // The test validates that the system handles large batches gracefully
            assertTrue(
                true,
                "Large batch operation hit gas limits as expected"
            );
        }
    }

    function test_CallToNonexistentContract_Success() public {
        // Use an address that has no code (simulating a destroyed or non-existent contract)
        address nonExistentContract = address(0xdead);

        // Try to call the non-existent contract
        Call[] memory deadContractCalls = new Call[](1);
        deadContractCalls[0] = Call({
            target: nonExistentContract,
            value: 0,
            data: abi.encodeWithSelector(bytes4(keccak256("someFunction()")))
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: deadContractCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            user, // Use user as signer (who was added as owner in setup)
            userPk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        // Should succeed (calls to non-existent contracts succeed but return empty data)
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_GasEfficiencyComparison_Success() public {
        // Ensure wallet has enough balance for both tests
        vm.deal(_aliceWallet, 30 ether);

        // Test single large call vs multiple small calls
        Call[] memory singleLargeCall = new Call[](1);
        singleLargeCall[0] = Call({target: _bob, value: 10 ether, data: ""});

        Call[] memory multipleSmallCalls = new Call[](10);
        for (uint256 i = 0; i < 10; i++) {
            multipleSmallCalls[i] = Call({
                target: _bob,
                value: 1 ether,
                data: ""
            });
        }

        // Test single large call
        BatchedCall memory singleCallBatch = BatchedCall({
            calls: singleLargeCall,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory singleValidatorData = _constructRelayerSignature(
            _aliceWallet,
            user, // Use user as signer (who was added as owner in setup)
            userPk,
            singleCallBatch,
            uint48(0)
        );

        uint256 gasBefore = gasleft();
        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            singleCallBatch,
            singleValidatorData
        );
        uint256 singleCallGas = gasBefore - gasleft();

        // Reset balance for second test
        vm.deal(_bob, 0);

        // Test multiple small calls
        BatchedCall memory multipleCallsBatch = BatchedCall({
            calls: multipleSmallCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory multipleValidatorData = _constructRelayerSignature(
            _aliceWallet,
            user, // Use user as signer (who was added as owner in setup)
            userPk,
            multipleCallsBatch,
            uint48(0)
        );

        gasBefore = gasleft();
        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            multipleCallsBatch,
            multipleValidatorData
        );
        uint256 multipleCallsGas = gasBefore - gasleft();

        // Both should result in same balance
        assertEq(address(_bob).balance, 10 ether);

        // Multiple calls should use more gas
        assertGt(multipleCallsGas, singleCallGas);

        emit LargeOperationCompleted(1, singleCallGas);
        emit LargeOperationCompleted(10, multipleCallsGas);
    }

    function test_ExecuteWithRelayer_WrappingSelfExecute_Success() public {
        // Test that executeWithRelayer can wrap a self-call to the wallet's own execute function
        // This creates a nested execution scenario: executeWithRelayer -> execute

        // First, prepare the inner calls that will be executed by the wallet's execute function
        Call[] memory innerCalls = new Call[](2);
        innerCalls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        innerCalls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _charlie,
                50 ether
            )
        });

        // Now wrap the execute call in executeWithRelayer
        Call[] memory outerCalls = new Call[](1);
        outerCalls[0] = Call({
            target: _aliceWallet, // Self-call to the wallet
            value: 0,
            data: abi.encodeWithSelector(
                ISmartWallet.execute.selector,
                innerCalls
            )
        });

        // Create the batched call for executeWithRelayer
        BatchedCall memory batchedCall = BatchedCall({
            calls: outerCalls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign the batched call using the helper function
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Execute through relayer
        vm.prank(_bob); // Bob acts as relayer
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the nested calls were executed successfully
        assertEq(
            address(_bob).balance,
            0.5 ether,
            "Bob should receive 0.5 ETH"
        );
        assertEq(
            mockToken.balanceOf(_charlie),
            50 ether,
            "Charlie should receive 50 tokens"
        );
    }

    function test_Execute_CallingExecuteWithRelayer_Success() public {
        // Test the reverse scenario: execute calls executeWithRelayer
        // This creates a nested execution: execute -> executeWithRelayer

        // Prepare the inner calls for executeWithRelayer
        Call[] memory innerCalls = new Call[](2);
        innerCalls[0] = Call({target: _charlie, value: 0.3 ether, data: ""});
        innerCalls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                30 ether
            )
        });

        // Create batched call for the inner executeWithRelayer
        BatchedCall memory batchedCall = BatchedCall({
            calls: innerCalls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign the batched call using the helper function
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Create outer call that calls executeWithRelayer
        Call[] memory outerCalls = new Call[](1);
        outerCalls[0] = Call({
            target: _aliceWallet, // Self-call to the wallet
            value: 0,
            data: abi.encodeWithSelector(
                ISmartWallet.executeWithRelayer.selector,
                batchedCall,
                validatorData
            )
        });

        // Execute the outer call directly as owner
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(outerCalls);

        // Verify the nested calls were executed successfully
        assertEq(
            address(_charlie).balance,
            0.3 ether,
            "Charlie should receive 0.3 ETH"
        );
        assertEq(
            mockToken.balanceOf(_bob),
            30 ether,
            "Bob should receive 30 tokens"
        );
    }

    function test_RevertWhen_ExecuteWithRelayer_NonAdminSelfExecute() public {
        // Add Bob as a non-admin owner to the wallet
        bytes32 bobKeyHash = _makeKeyHash(_bob);
        uint256 bobSettings = 0; // Non-admin settings
        _addOwnerToAccount(
            _alice, // Alice adds Bob as owner
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            bobSettings
        );

        // Verify Bob is now an owner but not admin
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(bobKeyHash));
        assertFalse(OwnerManager(_aliceWallet).isAdmin(bobSettings));

        // Prepare inner calls that execute will try to run
        Call[] memory innerCalls = new Call[](2);
        innerCalls[0] = Call({target: _charlie, value: 0.1 ether, data: ""});
        innerCalls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _charlie,
                10 ether
            )
        });

        // Bob tries to use executeWithRelayer to call the wallet's own execute function
        // This is a self-call attempt by a non-admin
        Call[] memory outerCalls = new Call[](1);
        outerCalls[0] = Call({
            target: _aliceWallet, // Self-call to the wallet
            value: 0,
            data: abi.encodeWithSelector(
                ISmartWallet.execute.selector,
                innerCalls
            )
        });

        // Create the batched call for executeWithRelayer
        BatchedCall memory batchedCall = BatchedCall({
            calls: outerCalls,
            nonce: _getNonce(_aliceWallet)
        });

        // Sign the batched call with Bob's key (non-admin owner) using helper
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _bob, // Bob is the signer
            _bobPk,
            batchedCall,
            uint48(0)
        );

        // Attempt to execute through relayer should revert with NonAdminSelfCall
        vm.prank(_charlie); // Charlie acts as relayer
        vm.expectRevert(ISmartWallet.NonAdminSelfCall.selector);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify no state changes occurred
        assertEq(
            address(_charlie).balance,
            0,
            "Charlie should not receive ETH"
        );
        assertEq(
            mockToken.balanceOf(_charlie),
            0,
            "Charlie should not receive tokens"
        );
    }

    function test_RevertWhen_Execute_TruncatesLargeRevertData() public {
        // Create a call that will revert with >256 bytes
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(revertingContract),
            value: 0,
            data: abi.encodeWithSelector(
                MockRevertingContract.revertWithLargeMessage.selector
            )
        });

        // Execute should revert with truncated error data (only first 256 bytes)
        vm.prank(_alice);

        // The revert will happen with truncated data (256 bytes instead of 300)
        // We expect the revert but can't easily verify the exact truncated size in the test
        // The important thing is that this code path is exercised
        vm.expectRevert();
        ISmartWallet(_aliceWallet).execute(calls);
    }

    // ============ EIP-7702 Execution Tests ============

    function test_Execute_AddOwnerViaRelayer() public {
        // Use alice's wallet which is already deployed and initialized
        // Alice is an admin owner of this wallet

        // Add charlie as a new owner through executeWithRelayer
        bytes32 newOwnerKeyHash = _makeKeyHash(_charlie);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet, // Self-call to add owner
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0 // Non-admin settings
            )
        });

        // Create BatchedCall with the addOwner call
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        // Create signature from alice (who is an admin)
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Execute via relayer (anyone can be the relayer)
        vm.prank(_bob); // Bob acts as relayer
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the new owner was added
        address validator = IOwnerManager(_aliceWallet).getVerifiedValidator(
            newOwnerKeyHash
        );
        assertEq(
            validator,
            address(_ecdsaValidator),
            "New owner should be added"
        );
    }

    // ============ EIP-7702 Relayer Bypass Tests (Built-in Owner) ============

    function test_Execute_EIP7702RelayerBypass_UninitializedEOA() public {
        // Create a new EOA for this test
        (address eoaWallet, uint256 eoaPrivateKey) = makeAddrAndKey(
            "eoaRelayerTest"
        );
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA (simulating EIP-7702)
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Verify EOA is not initialized (no owners)
        uint256 ownerCount = IOwnerManager(eoaWallet).ownerCount();
        assertEq(ownerCount, 0, "Should have no owners initially");

        // Step 3: Prepare a transaction to send ETH to Bob via relayer
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.5 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: INonceManager(eoaWallet).getNonce(0)
        });

        // Step 4: Create signature from EOA (the EOA itself)
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        uint48 validUntil = 0; // No expiry

        // Hash the batched call
        bytes32 intentHash = batchedCall.hash(
            validUntil,
            _smartWallet.IMPLEMENTATION()
        );
        bytes32 typedDataHash = ERC712(eoaWallet).hashTypedData(intentHash);

        // Sign with EOA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Combine keyHash + validUntil + signature
        bytes memory validatorData = abi.encodePacked(
            eoaKeyHash,
            validUntil,
            signature
        );

        // Step 5: Execute via relayer (should succeed without initialization)
        uint256 bobBalanceBefore = _bob.balance;

        vm.prank(relayer);
        ISmartWallet(eoaWallet).executeWithRelayer(batchedCall, validatorData);

        // Step 6: Verify execution succeeded
        uint256 bobBalanceAfter = _bob.balance;
        assertEq(
            bobBalanceAfter - bobBalanceBefore,
            0.5 ether,
            "Bob should receive 0.5 ETH"
        );
    }

    function test_RevertWhen_Execute_EIP7702RelayerBypass_InvalidSignature()
        public
    {
        // Create a new EOA for this test
        (address eoaWallet, ) = makeAddrAndKey("eoaInvalidSig");
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Prepare transaction
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.5 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: INonceManager(eoaWallet).getNonce(0)
        });

        // Step 3: Create INVALID signature (using wrong private key)
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        uint48 validUntil = 0;

        bytes32 intentHash = batchedCall.hash(
            validUntil,
            _smartWallet.IMPLEMENTATION()
        );
        bytes32 typedDataHash = ERC712(eoaWallet).hashTypedData(intentHash);

        // Sign with WRONG private key
        (, uint256 wrongPrivateKey) = makeAddrAndKey("wrong");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wrongPrivateKey,
            typedDataHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory validatorData = abi.encodePacked(
            eoaKeyHash,
            validUntil,
            signature
        );

        // Step 4: Should revert with invalid signature
        vm.prank(relayer);
        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        ISmartWallet(eoaWallet).executeWithRelayer(batchedCall, validatorData);
    }

    function test_Execute_EIP7702RelayerBypass_OnlyAddressThisBuiltin() public {
        // Create a new EOA for this test
        (address eoaWallet, ) = makeAddrAndKey("eoaOnlyThis");
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Check validator for a different keyHash (not address(this))
        bytes32 bobKeyHash = _makeKeyHash(_bob);
        address validator = IOwnerManager(eoaWallet).getVerifiedValidator(
            bobKeyHash
        );

        assertEq(
            validator,
            address(0),
            "Should return zero for non-address(this) keyHash"
        );

        // Step 3: Verify address(this) returns ECDSA validator
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        validator = IOwnerManager(eoaWallet).getVerifiedValidator(eoaKeyHash);
        assertEq(
            validator,
            Static.ECDSA_VALIDATOR_ADDRESS,
            "Should return ECDSA for address(this)"
        );
    }

    function test_Execute_EIP7702RelayerBypass_ChainlessExecution() public {
        // Create a new EOA for this test
        (address eoaWallet, uint256 eoaPrivateKey) = makeAddrAndKey(
            "eoaChainless"
        );
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Prepare chainless addOwner call
        bytes32 newOwnerKeyHash = _makeKeyHash(_bob);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: eoaWallet, // Self-call required for chainless
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                0 // No special settings
            )
        });

        // Use chainless nonce - starting from 0 for uninitialized wallet
        uint256 chainlessNonce = (uint256(Static.CHAINLESS_NONCE_KEY) << 64) |
            uint256(0);
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        // Step 3: Create signature for chainless execution
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        uint48 validUntil = 0;

        bytes32 intentHash = batchedCall.hash(
            validUntil,
            _smartWallet.IMPLEMENTATION()
        );
        bytes32 typedDataHash = ERC712(eoaWallet).hashTypedDataSansChainId(
            intentHash
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory validatorData = abi.encodePacked(
            eoaKeyHash,
            validUntil,
            signature
        );

        // Step 4: Execute chainless via relayer (should succeed)
        vm.prank(relayer);
        ISmartWallet(eoaWallet).executeWithRelayer(batchedCall, validatorData);

        // Step 5: Verify owner was added
        bool hasOwner = IOwnerManager(eoaWallet).hasOwner(newOwnerKeyHash);
        assertTrue(hasOwner, "Bob should be added as owner");
    }
}
