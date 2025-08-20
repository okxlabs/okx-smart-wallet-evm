// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {OwnersManager} from "src/OwnersManager.sol";

contract ValidationTest is Base {
    event NonceConsumed(uint192 key, uint64 nonce);

    function setUp() public override {
        super.setUp();
    }

    function test_executeFromRelayer_reverts_for_default_validator_invalid_signer()
        public
    {
        // Register validator first so we can test signature validation
        _addValidator(_alice);

        Call[] memory calls = _construct_calls_data();

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _bobPk, // Wrong private key for invalid signature test
            hash
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        IWalletCore(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );
        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_invalid_signature() public {
        Call[] memory calls = _construct_calls_data();
        _addValidator(_alice);

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _bobPk, // Wrong private key for invalid signature test
            hash
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        IWalletCore(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_invalid_nonce() public {
        Call[] memory calls = _construct_calls_data();

        // Use a keyHash that doesn't exist (bob's keyHash, but bob is not a validator)
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _bob, // Use bob's address for keyHash
            _bobPk, // Use bob's private key for signing
            hash
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidKeyHash.selector, bobKeyHash)
        );
        IWalletCore(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_removed_validator() public {
        Call[] memory calls = _construct_calls_data();
        _addValidator(_alice);

        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        _executeRemoveValidator(_alice, keyHash);

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidKeyHash.selector, keyHash)
        );
        IWalletCore(_alice).executeWithRelayer(
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
        Call[] memory calls = _construct_calls_data();

        vm.expectEmit();
        emit NonceConsumed(uint192(0), uint64(nonce));

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        vm.prank(_alice);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _alice, 0);
        IWalletCore(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_isValidSignature_fails_with_invalid_signer() public view {
        bytes32 hash = keccak256("test");

        // Wrong signer
        bytes memory signature = abi.encodePacked(_signDigest(hash, _bobPk));

        // Call isValidSignature
        bytes4 result = IWalletCore(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_for_removed_validator() public {
        // Add validator
        _addValidator(_alice);

        // Remove validator
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        _executeRemoveValidator(_alice, keyHash);

        bytes32 hash = keccak256("test");
        bytes memory sig = _signDigest(hash, _alicePk);
        bytes memory signature = abi.encodePacked(keyHash, sig);

        // Call isValidSignature
        bytes4 result = IWalletCore(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_short_signature() public view {
        bytes32 hash = keccak256("test");

        // signature shorter than 20 bytes
        bytes memory signature = bytes("");

        // Call isValidSignature
        bytes4 result = IWalletCore(_alice).isValidSignature(hash, signature);
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
        bytes4 result = IWalletCore(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_succeeds_with_default_validator()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes memory signature = abi.encodePacked(_signDigest(hash, _alicePk));

        // Call isValidSignature
        bytes4 result = IWalletCore(_alice).isValidSignature(hash, signature);
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
        bytes4 result = IWalletCore(_alice).isValidSignature(hash, signature);
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
        bytes4 result = IWalletCore(_alice).isValidSignature(
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
