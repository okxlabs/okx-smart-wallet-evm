// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";

contract ValidatorEnumerationTest is Base {
    address internal _charlie;
    uint256 internal _charliePk;
    address internal _dave;
    uint256 internal _davePk;

    function setUp() public override {
        super.setUp();
        (_charlie, _charliePk) = makeAddrAndKey("charlie");
        (_dave, _davePk) = makeAddrAndKey("dave");
    }

    function test_validator_enumeration_functions() public {
        // Alice starts with 1 validator from initialization
        assertEq(IOwnersManager(_alice).ownerCount(), 1);
        assertTrue(
            IOwnersManager(_alice).hasOwner(keccak256(abi.encodePacked(_alice)))
        );

        // _addValidator will return early since alice already has a validator
        _addValidator(_alice);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        assertEq(IOwnersManager(_alice).ownerCount(), 1);
        assertTrue(IOwnersManager(_alice).hasOwner(aliceKeyHash));
        assertEq(IOwnersManager(_alice).ownerAt(0), aliceKeyHash);

        // Add second validator (charlie)
        _addValidator(_alice, _charlie);
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(_charlie));

        assertEq(IOwnersManager(_alice).ownerCount(), 2);
        assertTrue(IOwnersManager(_alice).hasOwner(charlieKeyHash));

        // Add third validator
        _addValidator(_alice, _dave);
        bytes32 daveKeyHash = keccak256(abi.encodePacked(_dave));

        assertEq(IOwnersManager(_alice).ownerCount(), 3);
        assertTrue(IOwnersManager(_alice).hasOwner(daveKeyHash));

        // Get all validators
        bytes32[] memory allKeys = IOwnersManager(_alice).getOwnerKeys();
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
        _executeRemoveValidator(_alice, charlieKeyHash);

        assertEq(IOwnersManager(_alice).ownerCount(), 2);
        assertFalse(IOwnersManager(_alice).hasOwner(charlieKeyHash));
        assertTrue(IOwnersManager(_alice).hasOwner(aliceKeyHash));
        assertTrue(IOwnersManager(_alice).hasOwner(daveKeyHash));
    }

    function test_ownerAt_reverts_on_out_of_bounds() public {
        // Add one validator
        _addValidator(_alice);

        // This should work
        IOwnersManager(_alice).ownerAt(0);

        // This should revert (out of bounds)
        vm.expectRevert();
        IOwnersManager(_alice).ownerAt(1);
    }

    function test_enumeration_with_validator_settings() public {
        // Add validators with different settings
        bytes32 keyHash1 = keccak256(abi.encodePacked(_charlie));
        bytes32 keyHash2 = keccak256(abi.encodePacked(_dave));

        // Add first validator with settings
        _executeAddValidator(
            _alice,
            keyHash1,
            address(_ecdsaValidator),
            true,
            0,
            address(0)
        );

        // Add second validator with settings
        _executeAddValidator(
            _alice,
            keyHash2,
            address(_ecdsaValidator),
            false,
            uint40(block.timestamp + 3600),
            address(0)
        );

        // Check enumeration (alice + 2 new validators = 3 total)
        assertEq(IOwnersManager(_alice).ownerCount(), 3);
        assertTrue(IOwnersManager(_alice).hasOwner(keyHash1));
        assertTrue(IOwnersManager(_alice).hasOwner(keyHash2));

        // Verify settings are preserved
        assertTrue(isSignerAdmin(_alice, keyHash1));
        assertFalse(isSignerAdmin(_alice, keyHash2));
    }
}
