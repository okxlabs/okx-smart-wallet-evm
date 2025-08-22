// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";

contract ValidationTest is Base {
    event NonceConsumed(uint192 key, uint64 nonce);

    function setUp() public override {
        super.setUp();
    }

    function test_executeFromRelayer_reverts_for_invalid_signature() public {
        Call[] memory calls = constructCallsData();
        _addValidator(_alice);

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _bobPk, // Wrong private key for invalid signature test
            hash
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_invalid_keyHash() public {
        Call[] memory calls = constructCallsData();

        // Use a keyHash that doesn't exist (bob's keyHash, but bob is not a validator)
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _bob, // Use bob's address for keyHash
            _bobPk, // Use bob's private key for signing
            hash
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidKeyHash.selector, bobKeyHash)
        );
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_removed_validator() public {
        Call[] memory calls = constructCallsData();

        // Use _bob instead of _alice to avoid EIP-7702 fallback collision
        // (In test environment, address(this) == _alice due to setCode)
        _addValidator(_alice, _bob);

        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _executeRemoveValidator(_alice, bobKeyHash);

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _bob, // Using _bob's address
            _bobPk, // Using _bob's private key
            hash
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidKeyHash.selector, bobKeyHash)
        );
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_emits_nonce_consumed() public {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_alice);
        uint256 nonce = _getNonce(_alice);
        Call[] memory calls = constructCallsData();

        vm.expectEmit();
        emit NonceConsumed(uint192(0), uint64(nonce));

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
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

    function test_nonce_unchanged_after_invalid_signature_revert() public {
        // Add validator
        _addValidator(_alice);

        // Get initial nonce
        uint192 nonceKey = uint192(
            uint256(keccak256(abi.encodePacked(_alice))) >> 64
        );
        uint64 initialNonce = INonceManager(_alice).getNonce(nonceKey);

        // Construct call data
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: (uint256(nonceKey) << 64) | uint256(initialNonce),
            expiry: 0
        });

        // Create validatorData with invalid signature
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes memory invalidSignature = new bytes(65); // All zeros - invalid signature
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash,
            invalidSignature
        );

        // Execute transaction that should revert
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify nonce hasn't changed
        uint64 nonceAfterRevert = INonceManager(_alice).getNonce(nonceKey);
        assertEq(
            nonceAfterRevert,
            initialNonce,
            "Nonce should not change after reverted transaction"
        );
    }

    function test_isValidSignature_fails_with_invalid_signer() public view {
        bytes32 hash = keccak256("test");

        // Wrong signer
        bytes memory signature = abi.encodePacked(_signDigest(hash, _bobPk));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_signature_length_boundaries() public view {
        bytes32 hash = keccak256("test");

        // Test empty signature
        bytes memory emptySignature = bytes("");
        bytes4 result = ISmartWallet(_alice).isValidSignature(
            hash,
            emptySignature
        );
        assertEq(result, bytes4(0xffffffff));

        // Test oversized signature (100 bytes)
        bytes memory oversizedSignature = bytes(new bytes(100));
        result = ISmartWallet(_alice).isValidSignature(
            hash,
            oversizedSignature
        );
        assertEq(result, bytes4(0xffffffff));
    }

    function test_execute_reverts_for_expired_owner() public {
        // Add Bob as owner with 1 day expiration
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 1 days);

        _executeAddValidator(
            _alice,
            bobKeyHash,
            address(_ecdsaValidator),
            false,
            expiry,
            address(0)
        );

        // Create a simple call
        Call[] memory calls = constructCallsData();

        // Bob can execute before expiration
        vm.prank(_bob);
        ISmartWallet(_alice).execute(calls);
        assertEq(address(_bob).balance, 1 ether);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Bob should be rejected after expiration
        vm.prank(_bob);
        vm.expectRevert(Errors.OwnerExpired.selector);
        ISmartWallet(_alice).execute(calls);
    }

    function test_execute_allows_non_expired_owner() public {
        // Add Bob as owner with 7 days expiration
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 7 days);

        _executeAddValidator(
            _alice,
            bobKeyHash,
            address(_ecdsaValidator),
            false,
            expiry,
            address(0)
        );

        // Fast forward but still within expiration
        vm.warp(block.timestamp + 6 days);

        // Create a simple call
        Call[] memory calls = constructCallsData();

        // Bob should still be able to execute
        vm.prank(_bob);
        ISmartWallet(_alice).execute(calls);
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_isValidSignature_fails_for_removed_validator() public {
        // Add validator using _bob to avoid EIP-7702 fallback collision
        // (In test environment, address(this) == _alice due to setCode)
        _addValidator(_alice, _bob);

        // Remove validator
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _executeRemoveValidator(_alice, bobKeyHash);

        bytes32 hash = keccak256("test");
        bytes memory sig = _signDigest(hash, _bobPk); // Use _bob's private key
        bytes memory signature = abi.encodePacked(bobKeyHash, sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_short_signature() public view {
        bytes32 hash = keccak256("test");

        // signature shorter than 20 bytes
        bytes memory signature = bytes("");

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_longer_than_85_bytes_signature()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // signature have 100 bytes
        bytes memory signature = bytes(new bytes(100));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_succeeds_with_default_validator()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes memory signature = abi.encodePacked(_signDigest(hash, _alicePk));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_isValidSignature_succeeds_with_valid_validator_signer()
        public
    {
        // Add validator
        _addValidator(_alice);

        bytes32 hash = keccak256("test");
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        bytes memory sig = _signDigest(hash, _alicePk);
        bytes memory signature = abi.encodePacked(keyHash, sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_isValidSignature_for_premit() public view {
        bytes32 hash = keccak256("721 struct data");

        // Create bound hash like isValidSignature does
        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), address(_alice), hash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

        // Sign the bound digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, digest);

        // Signature
        bytes memory validatorData = abi.encodePacked(r, s, v);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(
            hash,
            validatorData
        );
        assertEq(result, bytes4(0x1626ba7e));
    }

    function _signDigest(
        bytes32 hash,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), address(_alice), hash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        return abi.encodePacked(r, s, v);
    }
}
