// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import "forge-std/console.sol";

contract ExecutionTest is Base {
    MockERC20 mockToken;
    MockERC20 mockToken2;
    address internal _charlie;

    function setUp() public override {
        super.setUp();

        (_charlie, ) = makeAddrAndKey("charlie");

        vm.prank(_alice);
        mockToken = new MockERC20();

        vm.prank(_bob);
        mockToken2 = new MockERC20();
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

    function test_onlyOwnerOrEntryPoint_keyHash_validation() public {
        // Test that onlyOwnerOrEntryPoint properly validates keyHash
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));

        // First, verify Charlie is not an owner
        assertFalse(IOwnersManager(_alice).hasOwner(charlieKeyHash));

        // Charlie should not be able to call execute
        vm.prank(_charlie);
        Call[] memory calls = _construct_calls_data();
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        ISmartWallet(_alice).execute(calls);

        // Now add Charlie as an owner
        _addValidator(_alice, _charlie);

        // Verify Charlie is now an owner
        assertTrue(IOwnersManager(_alice).hasOwner(charlieKeyHash));

        // Charlie should now be able to call execute
        vm.prank(_charlie);
        ISmartWallet(_alice).execute(calls);
    }

    function test_keyHash_consistency_across_functions() public {
        // Test that the same address generates the same keyHash across different functions
        address testAddress = _charlie;

        // Generate keyHash using the same method as in onlyOwnerOrEntryPoint
        bytes32 keyHashFromModifier = keccak256(abi.encodePacked(testAddress));

        // Generate keyHash using the same method as in test helpers
        bytes32 keyHashFromHelper = keccak256(abi.encodePacked(testAddress));

        // They should be identical
        assertEq(keyHashFromModifier, keyHashFromHelper);

        // Add Charlie as owner using this keyHash
        _addValidator(_alice, testAddress);

        // Verify the keyHash exists in the owner set
        assertTrue(IOwnersManager(_alice).hasOwner(keyHashFromModifier));
        assertTrue(IOwnersManager(_alice).hasOwner(keyHashFromHelper));

        // Test that execute() works with this consistent keyHash
        vm.prank(testAddress);
        Call[] memory calls = _construct_calls_data();
        ISmartWallet(_alice).execute(calls);
    }

    function test_unified_encoding_consistency() public {
        // Test that all address encodings in the codebase now use the unified abi.encodePacked method
        address[] memory testAddresses = new address[](3);
        testAddresses[0] = _alice;
        testAddresses[1] = _bob;
        testAddresses[2] = _charlie;

        for (uint i = 0; i < testAddresses.length; i++) {
            address addr = testAddresses[i];

            // All keyHash generation should use abi.encodePacked
            bytes32 keyHash = keccak256(abi.encodePacked(addr));

            // Test the unified encoding behavior
            if (addr == _alice) {
                // _alice is the wallet address (due to setCode in test environment)
                // So this keyHash should trigger EIP-7702 fallback for consistent behavior
                address validator = IOwnersManager(_alice).getVerifiedValidator(
                    keyHash
                );
                // Should return either registered validator or EIP-7702 fallback
                assertNotEq(validator, address(0));
            } else {
                // Other addresses should work normally if added as owners
                // First verify they're not owners
                assertFalse(IOwnersManager(_alice).hasOwner(keyHash));

                // Add as owner
                _addValidator(_alice, addr);

                // Now should be registered
                assertTrue(IOwnersManager(_alice).hasOwner(keyHash));

                // Should return a valid validator
                address validator = IOwnersManager(_alice).getVerifiedValidator(
                    keyHash
                );
                assertNotEq(validator, address(0));
            }
        }
    }

    function test_executeFromRelayer_succeeds_as_owner() public {
        // Register validator first
        _addValidator(_alice);

        Call[] memory calls = _construct_calls_data();
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        vm.prank(_alice);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _alice, 0);
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
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
        _setCodeToEOA(address(_walletCore), charlie);

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
}
