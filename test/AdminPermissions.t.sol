// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";

/**
 * @title AdminPermissionsTest
 * @notice Test Admin vs non-admin execution permission differences
 * @dev Includes self-call restrictions, dynamic permission changes, etc.
 */
contract AdminPermissionsTest is Base {
    address internal adminUser;
    uint256 internal adminUserPk;
    address internal nonAdminUser;
    uint256 internal nonAdminUserPk;

    function setUp() public override {
        super.setUp();

        (adminUser, adminUserPk) = makeAddrAndKey("adminUser");
        (nonAdminUser, nonAdminUserPk) = makeAddrAndKey("nonAdminUser");

        // Add admin user with admin privileges
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));
        _executeAddValidator(
            _alice,
            adminKeyHash,
            address(_ecdsaValidator),
            true, // isAdmin = true
            0,
            address(0)
        );

        // Add non-admin user without admin privileges
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));
        _executeAddValidator(
            _alice,
            nonAdminKeyHash,
            address(_ecdsaValidator),
            false, // isAdmin = false
            0,
            address(0)
        );
    }

    // ============ Self-Call Restriction Tests ============

    function test_non_admin_self_call_restriction() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Construct self-call (wallet calling itself)
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keccak256("malicious"),
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            nonAdminKeyHash,
            _signHash(nonAdminUserPk, typedDataHash)
        );

        // Non-admin should not be able to make self-calls
        vm.prank(_bob);
        vm.expectRevert(); // Should revert due to self-call restriction
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_admin_self_call_allowed() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));

        // Construct self-call (wallet calling itself)
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keccak256("newValidator"),
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)),
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, typedDataHash)
        );

        // Admin should be able to make self-calls
        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify the self-call succeeded
        assertTrue(IOwnersManager(_alice).hasOwner(keccak256("newValidator")));
    }

    function test_non_admin_external_calls_allowed() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Construct external call (not self-call)
        Call[] memory externalCalls = constructCallsData(); // Transfers to _bob

        BatchedCall memory batchedCall = BatchedCall({
            calls: externalCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            nonAdminKeyHash,
            _signHash(nonAdminUserPk, typedDataHash)
        );

        // Non-admin should be able to make external calls
        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(externalCalls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify external call succeeded
        assertEq(address(_bob).balance, 1 ether);
    }

    // ============ Admin Privilege Tests ============

    function test_admin_can_add_validators() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));
        bytes32 newValidatorKeyHash = keccak256("testValidator");

        Call[] memory addValidatorCalls = new Call[](1);
        addValidatorCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newValidatorKeyHash,
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)),
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: addValidatorCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, typedDataHash)
        );

        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        assertTrue(IOwnersManager(_alice).hasOwner(newValidatorKeyHash));
    }

    function test_admin_can_remove_validators() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Admin removes non-admin validator
        Call[] memory removeValidatorCalls = new Call[](1);
        removeValidatorCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeOwner.selector,
                nonAdminKeyHash,
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: removeValidatorCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, typedDataHash)
        );

        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        assertFalse(IOwnersManager(_alice).hasOwner(nonAdminKeyHash));
    }

    function test_admin_can_update_validator_settings() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Admin updates non-admin validator to have expiry
        uint256 newSettings = IOwnersManager(_alice).packSettings(
            false,
            uint40(block.timestamp + 1 days),
            address(0)
        );

        Call[] memory updateValidatorCalls = new Call[](1);
        updateValidatorCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                nonAdminKeyHash,
                address(_ecdsaValidator),
                newSettings,
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: updateValidatorCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, typedDataHash)
        );

        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify settings were updated
        uint256 updatedSettings = IOwnersManager(_alice).ownerSettings(
            nonAdminKeyHash
        );
        assertGt(
            IOwnersManager(_alice).getExpiration(updatedSettings),
            block.timestamp
        );
    }

    // ============ Admin Rights Dynamic Changes ============

    function test_admin_rights_revocation_affects_permissions() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));

        // First, revoke admin rights
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        Call[] memory revokeAdminCalls = new Call[](1);
        revokeAdminCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                adminKeyHash,
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)), // isAdmin = false
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory revokeBatchedCall = BatchedCall({
            calls: revokeAdminCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 revokeTypedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(revokeBatchedCall, address(_smartWallet))
        );
        bytes memory revokeValidatorData = abi.encodePacked(
            aliceKeyHash,
            _signHash(_alicePk, revokeTypedDataHash)
        );

        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(
            revokeBatchedCall,
            revokeValidatorData
        );

        // Now try to use former admin to make self-call (should fail)
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keccak256("shouldFail"),
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)),
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory selfCallBatch = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 selfCallTypedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(selfCallBatch, address(_smartWallet))
        );
        bytes memory selfCallValidatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, selfCallTypedDataHash)
        );

        vm.prank(_bob);
        vm.expectRevert(); // Should fail because admin rights were revoked
        ISmartWallet(_alice).executeWithRelayer(
            selfCallBatch,
            selfCallValidatorData
        );
    }

    function test_admin_rights_elevation_grants_permissions() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));

        // Elevate non-admin to admin
        Call[] memory elevateAdminCalls = new Call[](1);
        elevateAdminCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                nonAdminKeyHash,
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(true, 0, address(0)), // isAdmin = true
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory elevateBatchedCall = BatchedCall({
            calls: elevateAdminCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 elevateTypedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(elevateBatchedCall, address(_smartWallet))
        );
        bytes memory elevateValidatorData = abi.encodePacked(
            aliceKeyHash,
            _signHash(_alicePk, elevateTypedDataHash)
        );

        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(
            elevateBatchedCall,
            elevateValidatorData
        );

        // Now the formerly non-admin user should be able to make self-calls
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keccak256("newAdminValidator"),
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)),
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory selfCallBatch = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 selfCallTypedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(selfCallBatch, address(_smartWallet))
        );
        bytes memory selfCallValidatorData = abi.encodePacked(
            nonAdminKeyHash,
            _signHash(nonAdminUserPk, selfCallTypedDataHash)
        );

        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(
            selfCallBatch,
            selfCallValidatorData
        );

        // Verify the self-call succeeded
        assertTrue(
            IOwnersManager(_alice).hasOwner(keccak256("newAdminValidator"))
        );
    }

    // ============ Mixed Call Scenarios ============

    function test_mixed_self_call_and_external_call_admin_only() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));

        // Mix of self-call and external call
        Call[] memory mixedCalls = new Call[](2);
        mixedCalls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        mixedCalls[1] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keccak256("mixedValidator"),
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)),
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: mixedCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, typedDataHash)
        );

        // Admin should be able to execute mixed calls including self-calls
        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify both calls succeeded
        assertEq(address(_bob).balance, 0.5 ether);
        assertTrue(
            IOwnersManager(_alice).hasOwner(keccak256("mixedValidator"))
        );
    }

    function test_mixed_self_call_and_external_call_non_admin_fails() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Mix of self-call and external call
        Call[] memory mixedCalls = new Call[](2);
        mixedCalls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        mixedCalls[1] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keccak256("shouldFailValidator"),
                address(_ecdsaValidator),
                IOwnersManager(_alice).packSettings(false, 0, address(0)),
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: mixedCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            nonAdminKeyHash,
            _signHash(nonAdminUserPk, typedDataHash)
        );

        // Non-admin should fail because of self-call in the batch
        vm.prank(_bob);
        vm.expectRevert(); // Should fail due to self-call restriction
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify no calls executed (atomic failure)
        assertEq(address(_bob).balance, 0 ether);
        assertFalse(
            IOwnersManager(_alice).hasOwner(keccak256("shouldFailValidator"))
        );
    }

    // ============ Edge Cases ============

    function test_admin_cannot_remove_last_admin() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));

        // Try to remove the original admin (alice) when adminUser is the only other admin
        Call[] memory removeAdminCalls = new Call[](1);
        removeAdminCalls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeOwner.selector,
                aliceKeyHash,
                IOwnersManager(_alice).sequence()
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: removeAdminCalls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = abi.encodePacked(
            adminKeyHash,
            _signHash(adminUserPk, typedDataHash)
        );

        vm.prank(_bob);
        // This should be allowed since there's still one admin left
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify alice was removed but adminUser is still there
        assertFalse(IOwnersManager(_alice).hasOwner(aliceKeyHash));
        assertTrue(IOwnersManager(_alice).hasOwner(adminKeyHash));
    }
}
