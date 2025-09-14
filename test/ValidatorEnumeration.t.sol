// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";

contract ValidatorEnumerationTest is Base {
    function test_ValidatorEnumeration_Functions_Success() public {
        // Alice starts with 1 validator from initialization
        assertEq(IOwnerManager(_aliceWallet).ownerCount(), 1);
        assertTrue(
            IOwnerManager(_aliceWallet).hasOwner(
                keccak256(abi.encodePacked(_alice))
            )
        );

        // Alice already has a validator from initialization
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        assertEq(IOwnerManager(_aliceWallet).ownerCount(), 1);
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(aliceKeyHash));
        assertEq(IOwnerManager(_aliceWallet).ownerAt(0), aliceKeyHash);

        // Add second validator (charlie)
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(_ecdsaValidator),
            0
        );

        assertEq(IOwnerManager(_aliceWallet).ownerCount(), 2);
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(charlieKeyHash));

        // Add third validator
        bytes32 daveKeyHash = keccak256(abi.encodePacked(_dave));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            daveKeyHash,
            address(_ecdsaValidator),
            0
        );

        assertEq(IOwnerManager(_aliceWallet).ownerCount(), 3);
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(daveKeyHash));

        // Get all validators
        bytes32[] memory allKeys = IOwnerManager(_aliceWallet).getOwnerKeys();
        assertEq(allKeys.length, 3);

        // Verify all keys are present (order may vary)
        bool foundAlice = false;
        bool foundCharlie = false;
        bool foundDave = false;

        for (uint256 i = 0; i < allKeys.length; i++) {
            if (allKeys[i] == aliceKeyHash) foundAlice = true;
            if (allKeys[i] == charlieKeyHash) foundCharlie = true;
            if (allKeys[i] == daveKeyHash) foundDave = true;
        }

        assertTrue(foundAlice);
        assertTrue(foundCharlie);
        assertTrue(foundDave);

        // Remove a validator and check count
        _executeRemoveValidator(_aliceWallet, charlieKeyHash);

        assertEq(IOwnerManager(_aliceWallet).ownerCount(), 2);
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(charlieKeyHash));
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(aliceKeyHash));
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(daveKeyHash));
    }

    function test_RevertWhen_OwnerAt_OutOfBounds() public {
        // Alice already has one validator from initialization
        // This should work
        IOwnerManager(_aliceWallet).ownerAt(0);

        // This should revert (out of bounds)
        vm.expectRevert();
        IOwnerManager(_aliceWallet).ownerAt(1);
    }

    function test_ValidatorEnumeration_WithValidatorSettings_Success() public {
        // Add validators with different settings
        bytes32 keyHash1 = keccak256(abi.encodePacked(_charlie));
        bytes32 keyHash2 = keccak256(abi.encodePacked(_dave));

        // Add first validator with settings
        uint256 settings1 = OwnerManager(_aliceWallet).packSettings(
            true,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash1,
            address(_ecdsaValidator),
            settings1
        );

        // Add second validator with settings
        uint256 settings2 = OwnerManager(_aliceWallet).packSettings(
            false,
            uint40(block.timestamp + 3600),
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            keyHash2,
            address(_ecdsaValidator),
            settings2
        );

        // Check enumeration (alice + 2 new validators = 3 total)
        assertEq(IOwnerManager(_aliceWallet).ownerCount(), 3);
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(keyHash1));
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(keyHash2));

        // Verify settings are preserved
        assertTrue(_isSignerAdmin(_aliceWallet, keyHash1));
        assertFalse(_isSignerAdmin(_aliceWallet, keyHash2));
    }
}
