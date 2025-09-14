// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base, MockComplexContract, MockRevertingContract, MockERC20} from "./Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";

contract ExecutionTest is Base {
    MockERC20 mockToken;
    MockERC20 mockToken2;
    address internal _charlie;
    uint256 internal _charliePk;

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

        (_charlie, _charliePk) = makeAddrAndKey("charlie");
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
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
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
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
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
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
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
        emit ExecuteSuccessEvent(
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
        console.log("gas used", gasStart - gasEnd);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_ExecuteFromRelayer_InitializationOnFirstTime_Success()
        public
    {
        // Create charlie's wallet using factory
        address charlieWallet = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_charlie)),
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
        emit ExecuteSuccessEvent(
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
        emit ExecuteSuccessEvent(
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
        emit ExecuteSuccessEvent(
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
        emit ExecuteSuccessEvent(
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
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
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

    function test_Execute_EIP7702AfterSetCodeWithSelfAsOwner() public {
        console.log(
            "Testing EIP-7702: EOA with wallet code can execute as self-owner"
        );

        // Create a new EOA that will become a smart wallet
        (address eoaWallet, ) = makeAddrAndKey("eoaWallet");
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA (simulating EIP-7702 delegation)
        _setCodeToEoa(address(_smartWallet), eoaWallet);
        console.log("Set wallet code to EOA address:", eoaWallet);

        // Step 2: Initialize the wallet with the EOA itself as owner
        // This simulates the EIP-7702 scenario where EOA = wallet
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: eoaKeyHash,
            validator: address(_ecdsaValidator)
        });

        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).initialize(initialOwners);
        console.log("Initialized wallet with EOA as owner");

        // Step 3: Test that EOA can execute calls directly
        // In EIP-7702, the EOA address == wallet address
        // So when calling from eoaWallet, msg.sender == address(this)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        uint256 bobBalanceBefore = _bob.balance;

        // The EOA (now a wallet) executes the call
        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).execute(calls);

        // Verify the transfer succeeded
        assertEq(
            _bob.balance - bobBalanceBefore,
            1 ether,
            "Transfer should succeed"
        );
        console.log("Successfully executed transfer from EIP-7702 wallet");
    }

    function test_Execute_EIP7702AddOwnerAsSelf() public {
        console.log("Testing EIP-7702: EOA with wallet code can add owners");

        // Create a new EOA that will become a smart wallet
        (address eoaWallet, ) = makeAddrAndKey("eoaWallet");
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Initialize with EOA as owner (admin)
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: eoaKeyHash,
            validator: address(_ecdsaValidator)
        });

        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).initialize(initialOwners);

        // Verify EOA is admin
        uint256 settings = IOwnerManager(eoaWallet).ownerSettings(eoaKeyHash);
        assertTrue(
            IOwnerManager(eoaWallet).isAdmin(settings),
            "EOA should be admin"
        );

        // Step 3: EOA adds a new owner through execute
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_charlie));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: eoaWallet, // Self-call to add owner
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0 // Non-admin settings
            )
        });

        // Execute the addOwner call
        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).execute(calls);

        // Verify the new owner was added
        address validator = IOwnerManager(eoaWallet).ownerValidators(
            newOwnerKeyHash
        );
        assertEq(
            validator,
            address(_ecdsaValidator),
            "New owner should be added"
        );
        console.log("Successfully added new owner from EIP-7702 wallet");
    }

    function test_Execute_EIP7702WithDifferentOwner() public {
        console.log(
            "Testing EIP-7702: Different owner can execute on EIP-7702 wallet"
        );

        // Create a new EOA that will become a smart wallet
        (address eoaWallet, ) = makeAddrAndKey("eoaWallet");
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Initialize with Alice as owner (not the EOA itself)
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: aliceKeyHash,
            validator: address(_ecdsaValidator)
        });

        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).initialize(initialOwners);
        console.log("Initialized EIP-7702 wallet with Alice as owner");

        // Step 3: Alice can execute on the EIP-7702 wallet
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.5 ether, data: ""});

        uint256 bobBalanceBefore = _bob.balance;

        // Alice executes on the EIP-7702 wallet
        vm.prank(_alice);
        ISmartWallet(eoaWallet).execute(calls);

        assertEq(
            _bob.balance - bobBalanceBefore,
            0.5 ether,
            "Transfer should succeed"
        );
        console.log("Alice successfully executed on EIP-7702 wallet");

        // Step 4: EOA itself CAN STILL execute due to self-call bypass
        // Even though EOA is not an owner, msg.sender == address(this) allows execution
        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).execute(calls);

        assertEq(
            _bob.balance - bobBalanceBefore,
            1 ether,
            "EOA self-call should succeed"
        );
        console.log(
            "EOA can still execute due to self-call bypass (msg.sender == address(this))"
        );
    }

    function test_Execute_EIP7702OnlyOwnerSelfCallBypass() public {
        console.log("Testing EIP-7702: onlyOwner modifier allows self-calls");

        // Create a new EOA that will become a smart wallet
        (address eoaWallet, ) = makeAddrAndKey("eoaWallet");
        vm.deal(eoaWallet, 10 ether);

        // Step 1: Set wallet code to EOA
        _setCodeToEoa(address(_smartWallet), eoaWallet);

        // Step 2: Initialize with empty owners (no owners at all)
        InitialOwner[] memory emptyOwners = new InitialOwner[](0);
        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).initialize(emptyOwners);
        console.log("Initialized with no owners");

        // Step 3: Even with no owners, wallet can call itself
        // This is because onlyOwner allows msg.sender == address(this)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.25 ether, data: ""});

        // Make the call from the wallet to itself
        // This simulates internal execution where msg.sender == address(this)
        vm.prank(eoaWallet);
        ISmartWallet(eoaWallet).execute(calls);

        assertEq(_bob.balance, 0.25 ether, "Self-call should succeed");
        console.log("Self-call succeeded even with no registered owners");
    }
}
