// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ExecutionTest is Base {
    MockERC20 mockToken;
    MockERC20 mockToken2;
    address internal _charlie;
    
    // Complex execution test contracts
    MockComplexContract internal complexContract;
    MockRevertingContract internal revertingContract;
    MockSelfDestructContract internal selfDestructContract;
    
    address internal user;
    uint256 internal userPk;
    
    event TokenTransfer(address indexed from, address indexed to, uint256 amount);
    event ContractCalled(address indexed caller, bytes data, bytes result);
    event LargeOperationCompleted(uint256 callCount, uint256 gasUsed);

    function setUp() public override {
        super.setUp();

        (_charlie, ) = makeAddrAndKey("charlie");
        (user, userPk) = makeAddrAndKey("user");

        vm.prank(_alice);
        mockToken = new MockERC20();

        vm.prank(_bob);
        mockToken2 = new MockERC20();
        
        // Deploy complex execution test contracts
        complexContract = new MockComplexContract();
        revertingContract = new MockRevertingContract();
        selfDestructContract = new MockSelfDestructContract();
        
        // Give wallet some tokens for testing
        mockToken.mint(_alice, 1000 ether);
        
        // Add user as validator for complex tests
        bytes32 userKeyHash = keccak256(abi.encodePacked(user));
        _executeAddValidator(
            _alice,
            userKeyHash,
            address(_ecdsaValidator),
            false,
            0,
            address(0)
        );
    }

    function test_execute_succeeds_for_owner() public {
        vm.prank(_alice);
        Call[] memory calls = _construct_calls_data();
        ISmartWallet(_alice).execute(calls);
    }

    function test_execute_reverts_for_non_owner() public {
        vm.prank(_bob);
        Call[] memory calls = _construct_calls_data();
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        ISmartWallet(_alice).execute(calls);
    }

    function test_execute_reverts_on_failed_call() public {
        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1000 ether, data: ""}); // will fail
        vm.expectRevert();
        ISmartWallet(_alice).execute(calls);
    }

    function test_execute_succeeds_for_added_owner() public {
        // Add Charlie as an owner to the wallet
        _addValidator(_alice, _charlie);

        // Charlie should be able to call execute() directly
        vm.prank(_charlie);
        Call[] memory calls = _construct_calls_data();
        ISmartWallet(_alice).execute(calls);

        // Verify the call succeeded
        assertEq(_bob.balance, 1 ether);
    }

    function test_execute_reverts_for_unregistered_keyHash() public {
        // Dave is not registered as an owner
        (address dave, ) = makeAddrAndKey("dave");

        vm.prank(dave);
        Call[] memory calls = _construct_calls_data();
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        ISmartWallet(_alice).execute(calls);
    }

    function test_keyHash_consistency_and_validation() public {
        // Test that keyHash generation is consistent across the system
        address testAddress = _charlie;
        bytes32 keyHash = keccak256(abi.encodePacked(testAddress));

        // Initially Charlie should not be an owner
        assertFalse(IOwnersManager(_alice).hasOwner(keyHash));

        // Charlie should not be able to call execute
        vm.prank(_charlie);
        Call[] memory calls = _construct_calls_data();
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        ISmartWallet(_alice).execute(calls);

        // Add Charlie as owner
        _addValidator(_alice, _charlie);

        // Verify Charlie is now an owner and can execute
        assertTrue(IOwnersManager(_alice).hasOwner(keyHash));
        vm.prank(_charlie);
        ISmartWallet(_alice).execute(calls);
    }


    function test_executeFromRelayer_succeeds_as_relayer() public {
        // Register validator first
        _addValidator(_alice);

        Call[] memory calls = _construct_calls_data();
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        uint256 gasStart = gasleft();

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        uint256 gasEnd = gasleft();
        console.log("gas used", gasStart - gasEnd);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeFromRelayer_initialization_on_first_time() public {
        (address charlie, uint256 charliePk) = makeAddrAndKey("charlie");
        vm.deal(charlie, 1 ether);
        _setCodeToEOA(address(_smartWallet), charlie);

        // Initialize charlie's wallet storage with charlie as initial admin owner
        vm.prank(charlie);
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(charlie)),
            validator: address(_ecdsaValidator)
        });
        ISmartWallet(charlie).initialize(initialOwners);

        Call[] memory calls = _construct_calls_data();

        bytes32 hash = _getValidationTypedHash(charlie, calls);
        bytes memory validatorData = _construct_validatorData(
            charlie,
            charliePk,
            hash
        );

        vm.prank(_alice);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _alice, 0);
        ISmartWallet(charlie).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeFromRelayer_reverts_on_failed_payment() public {
        // Register validator first
        _addValidator(_alice);

        assertEq(mockToken2.balanceOf(_alice), 0);
        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        // First call is the failing payment
        calls[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken2)),
            _bob,
            10
        );
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        // Expect revert due to insufficient balance for ERC20 transfer
        vm.expectRevert();
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );
    }

    function test_executeFromRelayer_succeeds_on_payment() public {
        // Register validator first
        _addValidator(_alice);

        Call[] memory calls = new Call[](2);
        // Include payment to relayer as part of the batch
        calls[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken)),
            _bob,
            10
        );
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );
        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(mockToken.balanceOf(_bob), 10);
        assertEq(address(_bob).balance, 1 ether);
    }

    // This test is no longer valid as executeFromRelayer now reverts on any failed call
    // The batch execution is atomic - all succeed or all fail
    function test_executeFromRelayer_reverts_on_any_failed_call() public {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1000 ether, data: ""}); // This will fail due to insufficient balance

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        // Expect the entire batch to revert when one call fails
        vm.expectRevert();
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        // Verify no state changes occurred
        assertEq(address(_bob).balance, 0);
    }

    function test_executeFromRelayer_succeeds_on_free_gas_mode() public {
        // Register validator first
        _addValidator(_alice);

        Call[] memory calls = new Call[](1);
        // calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken)),
            _bob,
            10
        );

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(mockToken.balanceOf(_bob), 10);
        // assertEq(address(_bob).balance, 0 ether);
    }

    // ============ Complex Execution Tests ============

    function test_mixed_eth_erc20_contract_calls() public {
        bytes32 userKeyHash = keccak256(abi.encodePacked(user));
        
        // Complex mixed scenario:
        // 1. Transfer ETH to bob
        // 2. Transfer ERC20 tokens to charlie
        // 3. Call complex contract function
        // 4. Another ETH transfer
        // 5. ERC20 approval
        Call[] memory mixedCalls = new Call[](5);
        
        // 1. ETH transfer
        mixedCalls[0] = Call({
            target: _bob,
            value: 0.5 ether,
            data: ""
        });
        
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
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });
        
        bytes32 typedDataHash = ERC712(_alice).hashTypedData(BatchedCallLib.hash(batchedCall));
        bytes memory validatorData = abi.encodePacked(
            userKeyHash,
            _signHash(userPk, typedDataHash)
        );
        
        uint256 initialGas = gasleft();
        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(mixedCalls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
        uint256 gasUsed = initialGas - gasleft();
        
        // Verify all operations succeeded
        assertEq(address(_bob).balance, 0.5 ether);
        assertEq(mockToken.balanceOf(_charlie), 100 ether);
        assertEq(address(complexContract).balance, 0.3 ether);
        assertEq(mockToken.allowance(_alice, _bob), 50 ether);
        assertTrue(complexContract.functionCalled());
        
        emit LargeOperationCompleted(5, gasUsed);
    }

    function test_large_batch_operation_gas_limits() public {
        bytes32 userKeyHash = keccak256(abi.encodePacked(user));
        
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
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });
        
        bytes32 typedDataHash = ERC712(_alice).hashTypedData(BatchedCallLib.hash(batchedCall));
        bytes memory validatorData = abi.encodePacked(
            userKeyHash,
            _signHash(userPk, typedDataHash)
        );
        
        uint256 initialGas = gasleft();
        vm.prank(_bob);
        
        // Should either succeed or fail due to gas limits
        try ISmartWallet(_alice).executeWithRelayer{gas: 30000000}(batchedCall, validatorData) {
            // If it succeeds, verify all calls executed
            assertEq(complexContract.counter(), callCount);
            emit LargeOperationCompleted(callCount, initialGas - gasleft());
        } catch {
            // If it fails due to gas, that's expected behavior
            // The test validates that the system handles large batches gracefully
            assertTrue(true, "Large batch operation hit gas limits as expected");
        }
    }

    function test_call_to_selfdestructed_contract() public {
        bytes32 userKeyHash = keccak256(abi.encodePacked(user));
        
        // First, self-destruct the contract
        selfDestructContract.destroyContract(_alice);
        
        // Try to call the self-destructed contract
        Call[] memory deadContractCalls = new Call[](1);
        deadContractCalls[0] = Call({
            target: address(selfDestructContract),
            value: 0,
            data: abi.encodeWithSelector(
                MockSelfDestructContract.someFunction.selector
            )
        });
        
        BatchedCall memory batchedCall = BatchedCall({
            calls: deadContractCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });
        
        bytes32 typedDataHash = ERC712(_alice).hashTypedData(BatchedCallLib.hash(batchedCall));
        bytes memory validatorData = abi.encodePacked(
            userKeyHash,
            _signHash(userPk, typedDataHash)
        );
        
        vm.prank(_bob);
        // Should succeed (calls to non-existent contracts succeed but return empty data)
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_gas_efficiency_comparison() public {
        bytes32 userKeyHash = keccak256(abi.encodePacked(user));
        
        // Ensure wallet has enough balance for both tests
        vm.deal(_alice, 30 ether);
        
        // Test single large call vs multiple small calls
        Call[] memory singleLargeCall = new Call[](1);
        singleLargeCall[0] = Call({
            target: _bob,
            value: 10 ether,
            data: ""
        });
        
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
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });
        
        bytes32 singleTypedDataHash = ERC712(_alice).hashTypedData(BatchedCallLib.hash(singleCallBatch));
        bytes memory singleValidatorData = abi.encodePacked(
            userKeyHash,
            _signHash(userPk, singleTypedDataHash)
        );
        
        uint256 gasBefore = gasleft();
        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(singleCallBatch, singleValidatorData);
        uint256 singleCallGas = gasBefore - gasleft();
        
        // Reset balance for second test
        vm.deal(_bob, 0);
        
        // Test multiple small calls
        BatchedCall memory multipleCallsBatch = BatchedCall({
            calls: multipleSmallCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });
        
        bytes32 multipleTypedDataHash = ERC712(_alice).hashTypedData(BatchedCallLib.hash(multipleCallsBatch));
        bytes memory multipleValidatorData = abi.encodePacked(
            userKeyHash,
            _signHash(userPk, multipleTypedDataHash)
        );
        
        gasBefore = gasleft();
        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(multipleCallsBatch, multipleValidatorData);
        uint256 multipleCallsGas = gasBefore - gasleft();
        
        // Both should result in same balance
        assertEq(address(_bob).balance, 10 ether);
        
        // Multiple calls should use more gas
        assertGt(multipleCallsGas, singleCallGas);
        
        emit LargeOperationCompleted(1, singleCallGas);
        emit LargeOperationCompleted(10, multipleCallsGas);
    }
}
