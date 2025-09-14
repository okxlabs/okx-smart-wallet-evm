// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";

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
        uint256 adminSettings = OwnerManager(_aliceWallet).packSettings(
            true, // isAdmin = true
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            adminKeyHash,
            address(_ecdsaValidator),
            adminSettings
        );

        // Add non-admin user without admin privileges
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));
        uint256 nonAdminSettings = OwnerManager(_aliceWallet).packSettings(
            false, // isAdmin = false
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            nonAdminKeyHash,
            address(_ecdsaValidator),
            nonAdminSettings
        );
    }

    // ============ Self-Call Restriction Tests ============

    function test_RevertWhen_AddOwner_ByNonAdmin_SelfCall() public {
        // Construct self-call (wallet calling itself)
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("malicious"),
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            nonAdminUser,
            nonAdminUserPk,
            batchedCall,
            uint48(0)
        );

        // Non-admin should not be able to make self-calls
        vm.prank(_bob);
        vm.expectRevert(); // Should revert due to self-call restriction
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_AddOwner_ByAdmin_SelfCall_Success() public {
        // Construct self-call (wallet calling itself)
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("newValidator"),
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            batchedCall,
            uint48(0)
        );

        // Admin should be able to make self-calls
        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the self-call succeeded
        assertTrue(
            IOwnerManager(_aliceWallet).hasOwner(keccak256("newValidator"))
        );
    }

    function test_Transfer_ByNonAdmin_ExternalCall_Success() public {
        // Construct external call (not self-call)
        Call[] memory externalCalls = constructCallsData(); // Transfers to _bob

        BatchedCall memory batchedCall = BatchedCall({
            calls: externalCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            nonAdminUser,
            nonAdminUserPk,
            batchedCall,
            uint48(0)
        );

        // Non-admin should be able to make external calls
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

        // Verify external call succeeded
        assertEq(address(_bob).balance, 1 ether);
    }

    // ============ Admin Privilege Tests ============

    function test_AddOwner_ByAdmin_Success() public {
        bytes32 newValidatorKeyHash = keccak256("testValidator");

        Call[] memory addValidatorCalls = new Call[](1);
        addValidatorCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newValidatorKeyHash,
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: addValidatorCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        assertTrue(IOwnerManager(_aliceWallet).hasOwner(newValidatorKeyHash));
    }

    function test_RemoveOwner_ByAdmin_Success() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Admin removes non-admin validator
        Call[] memory removeValidatorCalls = new Call[](1);
        removeValidatorCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                nonAdminKeyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: removeValidatorCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        assertFalse(IOwnerManager(_aliceWallet).hasOwner(nonAdminKeyHash));
    }

    function test_UpdateOwner_ByAdmin_Success() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Admin updates non-admin validator to have expiry
        uint256 newSettings = IOwnerManager(_aliceWallet).packSettings(
            false,
            uint40(block.timestamp + 1 days),
            address(0)
        );

        Call[] memory updateValidatorCalls = new Call[](1);
        updateValidatorCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                nonAdminKeyHash,
                address(_ecdsaValidator),
                newSettings
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: updateValidatorCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify settings were updated
        (, , uint40 expiration, , ) = IOwnerManager(_aliceWallet)
            .getOwnerSettings(nonAdminKeyHash);
        assertGt(expiration, block.timestamp);
    }

    // ============ Admin Rights Dynamic Changes ============

    function test_AddOwner_ByRevokedAdmin_SelfCall_Reverts() public {
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));

        // First, revoke admin rights
        Call[] memory revokeAdminCalls = new Call[](1);
        revokeAdminCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                adminKeyHash,
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0)) // isAdmin = false
            )
        });

        BatchedCall memory revokeBatchedCall = BatchedCall({
            calls: revokeAdminCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory revokeValidatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            revokeBatchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            revokeBatchedCall,
            revokeValidatorData
        );

        // Now try to use former admin to make self-call (should fail)
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("shouldFail"),
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory selfCallBatch = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory selfCallValidatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            selfCallBatch,
            uint48(0)
        );

        vm.prank(_bob);
        vm.expectRevert(); // Should fail because admin rights were revoked
        ISmartWallet(_aliceWallet).executeWithRelayer(
            selfCallBatch,
            selfCallValidatorData
        );
    }

    function test_AddOwner_ByElevatedAdmin_SelfCall_Success() public {
        bytes32 nonAdminKeyHash = keccak256(abi.encodePacked(nonAdminUser));

        // Elevate non-admin to admin
        Call[] memory elevateAdminCalls = new Call[](1);
        elevateAdminCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                nonAdminKeyHash,
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(true, 0, address(0)) // isAdmin = true
            )
        });

        BatchedCall memory elevateBatchedCall = BatchedCall({
            calls: elevateAdminCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory elevateValidatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            elevateBatchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            elevateBatchedCall,
            elevateValidatorData
        );

        // Now the formerly non-admin user should be able to make self-calls
        Call[] memory selfCalls = new Call[](1);
        selfCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("newAdminValidator"),
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory selfCallBatch = BatchedCall({
            calls: selfCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory selfCallValidatorData = _constructRelayerSignature(
            _aliceWallet,
            nonAdminUser,
            nonAdminUserPk,
            selfCallBatch,
            uint48(0)
        );

        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            selfCallBatch,
            selfCallValidatorData
        );

        // Verify the self-call succeeded
        assertTrue(
            IOwnerManager(_aliceWallet).hasOwner(keccak256("newAdminValidator"))
        );
    }

    // ============ Mixed Call Scenarios ============

    function test_MixedCalls_ByAdmin_Success() public {
        // Mix of self-call and external call
        Call[] memory mixedCalls = new Call[](2);
        mixedCalls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        mixedCalls[1] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("mixedValidator"),
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: mixedCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            batchedCall,
            uint48(0)
        );

        // Admin should be able to execute mixed calls including self-calls
        vm.prank(_bob);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify both calls succeeded
        assertEq(address(_bob).balance, 0.5 ether);
        assertTrue(
            IOwnerManager(_aliceWallet).hasOwner(keccak256("mixedValidator"))
        );
    }

    function test_RevertWhen_MixedCalls_ByNonAdmin_SelfCall() public {
        // Mix of self-call and external call
        Call[] memory mixedCalls = new Call[](2);
        mixedCalls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        mixedCalls[1] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("shouldFailValidator"),
                address(_ecdsaValidator),
                IOwnerManager(_aliceWallet).packSettings(false, 0, address(0))
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: mixedCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            nonAdminUser,
            nonAdminUserPk,
            batchedCall,
            uint48(0)
        );

        // Non-admin should fail because of self-call in the batch
        vm.prank(_bob);
        vm.expectRevert(); // Should fail due to self-call restriction
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify no calls executed (atomic failure)
        assertEq(address(_bob).balance, 0 ether);
        assertFalse(
            IOwnerManager(_aliceWallet).hasOwner(
                keccak256("shouldFailValidator")
            )
        );
    }

    // ============ Edge Cases ============

    function test_RemoveOwner_ByAdmin_LastAdmin_Success() public {
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 adminKeyHash = keccak256(abi.encodePacked(adminUser));

        // Try to remove the original admin (alice) when adminUser is the only other admin
        Call[] memory removeAdminCalls = new Call[](1);
        removeAdminCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                aliceKeyHash
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: removeAdminCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            adminUser,
            adminUserPk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        // This should be allowed since there's still one admin left
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify alice was removed but adminUser is still there
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(aliceKeyHash));
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(adminKeyHash));
    }
}
