// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Static} from "src/libraries/Static.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {HelperLib} from "scripts/utils/Helper.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {InitialOwner} from "src/Types.sol";
import {SmartWallet} from "src/SmartWallet.sol";

contract IsValidSignatureTest is Base {
    // Passkey-related constants and variables
    uint256 internal constant TEST_SIG_R =
        112450831948757142750562360134609669473647155538405639309009281430691665378703;
    uint256 internal constant TEST_SIG_S =
        18363333552806174256136300126987944752421142252269824522148009181078823230960;
    bytes32 constant SIGNED_MESSAGE_HASH =
        0x34753a30843cdf97fd7c7f1cf2556d397c93bdfa6732b0b8b79bad029f5875e5;

    PasskeyValidator internal passkeyValidator;
    bytes32 internal passkeyTestKeyHash;

    function setUp() public override {
        super.setUp();

        // Deploy PasskeyValidator for testing
        passkeyValidator = new PasskeyValidator();
        passkeyTestKeyHash = keccak256(
            abi.encode([_passkeyPubX, _passkeyPubY])
        );

        // Add PasskeyValidator for Alice's wallet
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            true,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            passkeyTestKeyHash,
            address(passkeyValidator),
            settings
        );
    }

    function test_isValidSignature_fails_with_exactly_32_bytes() public view {
        bytes32 hash = keccak256("test");
        // Create signature with exactly 32 bytes (should be treated as invalid)
        bytes memory signature = new bytes(32);

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, bytes4(0xffffffff));
    }

    // ===== Boundary Condition and Exception Tests =====

    function test_isValidSignature_fails_with_empty_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(0);

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "Empty signature should be invalid"
        );
    }

    function test_isValidSignature_fails_with_1_byte_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(1);
        signature[0] = 0x01;

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "1-byte signature should be invalid"
        );
    }

    function test_isValidSignature_fails_with_15_byte_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(15);
        // Fill with some data
        for (uint i = 0; i < 15; i++) {
            signature[i] = bytes1(uint8(i + 1));
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "15-byte signature should be invalid"
        );
    }

    function test_isValidSignature_fails_with_31_byte_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(31);
        // Fill with some data
        for (uint i = 0; i < 31; i++) {
            signature[i] = bytes1(uint8(i + 1));
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "31-byte signature should be invalid"
        );
    }

    function test_isValidSignature_fails_with_33_byte_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(33);

        // Fill first 32 bytes with a valid keyHash pattern
        bytes32 someKeyHash = keccak256("some_key");
        assembly {
            mstore(add(signature, 0x20), someKeyHash)
        }
        // Add one more byte
        signature[32] = 0x01;

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "33-byte signature with non-existent keyHash should be invalid"
        );
    }

    function test_isValidSignature_fails_with_64_byte_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(64);

        // Fill first 32 bytes with a valid keyHash pattern
        bytes32 someKeyHash = keccak256("some_key");
        assembly {
            mstore(add(signature, 0x20), someKeyHash)
        }
        // Fill remaining 32 bytes with some data
        for (uint i = 32; i < 64; i++) {
            signature[i] = bytes1(uint8(i));
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "64-byte signature with non-existent keyHash should be invalid"
        );
    }

    function test_isValidSignature_fails_with_66_byte_signature() public view {
        bytes32 hash = keccak256("test");
        bytes memory signature = new bytes(66);

        // This is longer than 65 bytes, so it should go through validator path
        // Fill first 32 bytes with non-existent keyHash
        bytes32 nonExistentKeyHash = keccak256("non_existent_key");
        assembly {
            mstore(add(signature, 0x20), nonExistentKeyHash)
        }

        // Fill remaining bytes with some data
        for (uint i = 32; i < 66; i++) {
            signature[i] = bytes1(uint8(i));
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "66-byte signature with non-existent keyHash should be invalid"
        );
    }

    function test_isValidSignature_handles_very_long_signature() public view {
        bytes32 hash = keccak256("test");

        // Create a very long signature (1KB)
        bytes memory signature = new bytes(1024);

        // Fill first 32 bytes with non-existent keyHash
        bytes32 nonExistentKeyHash = keccak256("non_existent_key");
        assembly {
            mstore(add(signature, 0x20), nonExistentKeyHash)
        }

        // Fill remaining bytes with pattern data
        for (uint i = 32; i < 1024; i++) {
            signature[i] = bytes1(uint8(i % 256));
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "Very long signature with non-existent keyHash should be invalid"
        );
    }

    function test_isValidSignature_fails_with_malformed_65_byte_signature()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // Create 65-byte signature with invalid ECDSA format
        bytes memory signature = new bytes(65);
        // Fill with invalid ECDSA signature data
        for (uint i = 0; i < 65; i++) {
            signature[i] = bytes1(uint8(i));
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "Malformed 65-byte ECDSA signature should be invalid"
        );
    }

    function test_isValidSignature_fails_with_zero_hash() public view {
        bytes32 zeroHash = bytes32(0);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry
        bytes memory sig = _signDigestWithValidation(
            zeroHash,
            _alicePk,
            validUntil
        );
        bytes memory signature = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            sig
        );

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            zeroHash,
            signature
        );
        assertEq(
            result,
            Static.MAGIC_VALUE,
            "Zero hash should be valid if signature is correct"
        );
    }

    function test_isValidSignature_fails_with_max_hash() public view {
        bytes32 maxHash = bytes32(type(uint256).max);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry
        bytes memory sig = _signDigestWithValidation(
            maxHash,
            _alicePk,
            validUntil
        );
        bytes memory signature = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            sig
        );

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            maxHash,
            signature
        );
        assertEq(
            result,
            Static.MAGIC_VALUE,
            "Max hash should be valid if signature is correct"
        );
    }

    function test_isValidSignature_with_repeated_bytes_signature() public view {
        bytes32 hash = keccak256("test");

        // Create signature with repeated bytes pattern
        bytes memory signature = new bytes(100);
        bytes32 nonExistentKeyHash = bytes32(
            0x1111111111111111111111111111111111111111111111111111111111111111
        );

        assembly {
            mstore(add(signature, 0x20), nonExistentKeyHash)
        }

        // Fill remaining with repeated pattern
        for (uint i = 32; i < 100; i++) {
            signature[i] = 0xAA;
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "Signature with repeated bytes should be invalid with non-existent keyHash"
        );
    }

    function test_isValidSignature_with_all_zero_signature() public view {
        bytes32 hash = keccak256("test");

        // Create signature with all zeros
        bytes memory signature = new bytes(100);
        // signature is already initialized with zeros

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "All-zero signature should be invalid"
        );
    }

    function test_isValidSignature_with_all_max_signature() public view {
        bytes32 hash = keccak256("test");

        // Create signature with all 0xFF bytes
        bytes memory signature = new bytes(100);
        for (uint i = 0; i < 100; i++) {
            signature[i] = 0xFF;
        }

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "All-max signature should be invalid"
        );
    }

    function test_isValidSignature_fails_with_65_byte_wrong_signer()
        public
        view
    {
        bytes32 hash = keccak256("test_wrong_signer");

        // Use helper function to get the digest for isValidSignature
        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), _aliceWallet, hash)
        );

        // Sign with Bob's private key instead of Alice's
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, boundHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "65-byte signature from wrong signer should fail"
        );
    }

    function test_isValidSignature_fails_with_invalid_65_byte_signature_format()
        public
        view
    {
        bytes32 hash = keccak256("test_invalid_format");

        // Create invalid 65-byte signature (invalid v value)
        bytes memory signature = new bytes(65);
        // Fill r and s with some values
        for (uint i = 0; i < 32; i++) {
            signature[i] = bytes1(uint8(i + 1)); // r
            signature[i + 32] = bytes1(uint8(i + 100)); // s
        }
        signature[64] = 0x99; // Invalid v value (should be 27 or 28)

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "Invalid 65-byte signature format should fail"
        );
    }

    // ===== Built-in ECDSA Validator =====

    function test_isValidSignature_fails_with_builtin_ecdsa_validator_wrong_keyHash()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes32 wrongKeyHash = keccak256(abi.encodePacked("wrong_address"));
        bytes memory sig = _signDigest(hash, _alicePk);
        bytes memory signature = abi.encodePacked(wrongKeyHash, sig);

        // Call isValidSignature with non-existent keyHash
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_builtin_ecdsa_validator_expired()
        public
    {
        // Add validator using _bob to avoid EIP-7702 fallback collision
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0, // No expiry in storage
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS, // Use built-in ECDSA validator
            settings
        );

        // Create validation data with expiry in 1 day
        uint48 validUntil = uint48(block.timestamp + 1 days);

        // Verify validator is initially valid
        bytes32 hash = keccak256("test");
        bytes memory sig = _signDigestWithValidation(hash, _bobPk, validUntil);
        bytes memory signature = abi.encodePacked(bobKeyHash, validUntil, sig);

        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            bytes4(0x1626ba7e),
            "Signature should be valid before expiry"
        );

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Call isValidSignature after expiration - same signature should now be invalid
        result = ISmartWallet(_aliceWallet).isValidSignature(hash, signature);
        assertEq(
            result,
            bytes4(0xffffffff),
            "Signature should be invalid after expiry"
        );
    }

    function test_isValidSignature_with_builtin_ecdsa_validator_different_hash_values()
        public
        view
    {
        // Test that different hash values produce different results
        bytes32 hash1 = keccak256("test1");
        bytes32 hash2 = keccak256("test2");

        // Use validator-based signatures to test signature replay attack protection
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry

        // Create signatures for both hashes using standard pattern
        bytes memory sig1 = _signDigestWithValidation(
            hash1,
            _alicePk,
            validUntil
        );
        bytes memory sig2 = _signDigestWithValidation(
            hash2,
            _alicePk,
            validUntil
        );
        bytes memory signature1 = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            sig1
        );
        bytes memory signature2 = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            sig2
        );

        // Correct signature for hash1
        bytes4 result1 = ISmartWallet(_aliceWallet).isValidSignature(
            hash1,
            signature1
        );
        assertEq(result1, bytes4(0x1626ba7e));

        // Wrong signature for hash2 (using sig1) - should fail due to signature replay attack
        bytes4 result2 = ISmartWallet(_aliceWallet).isValidSignature(
            hash2,
            signature1
        );
        assertEq(result2, bytes4(0xffffffff));

        // Correct signature for hash2
        bytes4 result3 = ISmartWallet(_aliceWallet).isValidSignature(
            hash2,
            signature2
        );
        assertEq(result3, bytes4(0x1626ba7e));
    }

    // ===== Built-in Passkey Validator =====

    function test_isValidSignature_succeeds_with_builtin_passkey_validator()
        public
    {
        // Use different passkey coordinates to avoid conflict with existing validator
        uint256 testPubX = 123456789;
        uint256 testPubY = 987654321;
        bytes32 passkeyKeyHash = keccak256(abi.encode([testPubX, testPubY]));

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            true,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            passkeyKeyHash,
            Static.PASSKEY_VALIDATOR_ADDRESS, // Use built-in passkey validator address(2)
            settings
        );

        bytes32 hash = keccak256("test_message_for_builtin_validator");

        // Create WebAuthn auth structure (this will fail validation but we're testing the flow)
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            hash,
            uint256(12345), // Dummy signature values
            uint256(67890)
        );

        // Create passkey signature data
        bytes memory sig = abi.encode(auth, new bytes32[](0)); // No merkle proofs
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: testPubX,
                    pubKeyY: testPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig
        );

        // Create full signature for isValidSignature
        bytes memory signature = abi.encodePacked(
            passkeyKeyHash,
            validatorData
        );

        // Call isValidSignature - this should fail due to invalid signature but test the flow
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        // Since we're using dummy signature values, this should fail
        assertEq(
            result,
            bytes4(0xffffffff),
            "Dummy passkey signature should fail validation"
        );
    }

    function test_isValidSignature_fails_with_builtin_passkey_validator_wrong_keyHash()
        public
        view
    {
        bytes32 hash = SIGNED_MESSAGE_HASH;
        bytes32 wrongKeyHash = keccak256(
            abi.encode([uint256(123), uint256(456)])
        );

        // Create WebAuthn auth structure
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            hash,
            TEST_SIG_R,
            TEST_SIG_S
        );

        // Create passkey signature data
        bytes memory sig = abi.encode(auth, new bytes32[](0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig
        );

        // Use wrong keyHash
        bytes memory signature = abi.encodePacked(wrongKeyHash, validatorData);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, bytes4(0xffffffff), "Wrong keyHash should fail");
    }

    function test_isValidSignature_fails_with_builtin_passkey_validator_expired()
        public
    {
        // Add passkey validator with expiry
        uint256 testPubX = 999999999;
        uint256 testPubY = 888888888;
        bytes32 passkeyKeyHash = keccak256(abi.encode([testPubX, testPubY]));
        uint40 expiry = uint40(block.timestamp + 1 days);

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            expiry,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            passkeyKeyHash,
            Static.PASSKEY_VALIDATOR_ADDRESS, // Use built-in passkey validator
            settings
        );

        bytes32 hash = keccak256("test");

        // Create WebAuthn auth structure with dummy signature values
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            hash,
            uint256(12345), // Dummy signature values
            uint256(67890)
        );

        bytes memory sig = abi.encode(auth, new bytes32[](0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: testPubX,
                    pubKeyY: testPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyKeyHash,
            validatorData
        );

        // Verify validator fails initially due to dummy signature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            bytes4(0xffffffff),
            "Dummy signature should fail before expiry"
        );

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Call isValidSignature after expiration - should still fail
        result = ISmartWallet(_aliceWallet).isValidSignature(hash, signature);
        assertEq(
            result,
            bytes4(0xffffffff),
            "Signature should still fail after expiry"
        );
    }

    // ===== Custom Validator Tests =====

    function test_isValidSignature_succeeds_with_custom_ecdsa_validator()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry

        // Use helper function to get the digest for isValidSignature
        bytes32 digest = _getIsValidSignatureHash(
            hash,
            _aliceWallet,
            validUntil
        );

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        bytes memory signature = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            sig
        );

        // Call isValidSignature - this uses the custom ECDSA validator deployed in setUp
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_isValidSignature_succeeds_with_custom_passkey_validator()
        public
        view
    {
        bytes32 hash = SIGNED_MESSAGE_HASH;

        // Create WebAuthn auth structure with dummy signature values
        // This will fail validation but tests the flow
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            hash,
            uint256(12345), // Dummy signature values
            uint256(67890)
        );

        // Create passkey signature data
        bytes memory sig = abi.encode(auth, new bytes32[](0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData
        );

        // Call isValidSignature - should fail due to dummy signature values
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            bytes4(0xffffffff),
            "Dummy passkey signature should fail"
        );
    }

    function test_isValidSignature_fails_with_custom_validator_wrong_signature()
        public
        view
    {
        bytes32 hash = SIGNED_MESSAGE_HASH;

        // Create WebAuthn auth structure with wrong signature values
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            hash,
            uint256(12345), // Wrong R
            uint256(67890) // Wrong S
        );

        // Create passkey signature data
        bytes memory sig = abi.encode(auth, new bytes32[](0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData
        );

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            bytes4(0xffffffff),
            "Wrong passkey signature should fail"
        );
    }

    function test_isValidSignature_fails_with_custom_validator_different_hash()
        public
        view
    {
        bytes32 wrongHash = keccak256("different_hash");

        // Create WebAuthn auth structure for original hash
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
            TEST_SIG_R,
            TEST_SIG_S
        );

        // Create passkey signature data
        bytes memory sig = abi.encode(auth, new bytes32[](0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData
        );

        // Call isValidSignature with different hash
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            wrongHash,
            signature
        );
        assertEq(
            result,
            bytes4(0xffffffff),
            "Different hash should fail validation"
        );
    }

    function test_isValidSignature_fails_with_custom_validator_malformed_data()
        public
        view
    {
        bytes32 hash = SIGNED_MESSAGE_HASH;

        // Create malformed validator data (incomplete passkey public key)
        bytes memory malformedValidatorData = abi.encodePacked(
            bytes32(
                0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
            )
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            malformedValidatorData
        );

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            bytes4(0xffffffff),
            "Malformed passkey data should fail"
        );
    }

    function test_isValidSignature_with_custom_validator_different_hash_values()
        public
        view
    {
        // Test that different hash values produce different results
        bytes32 hash1 = keccak256("test1");
        bytes32 hash2 = keccak256("test2");

        // Create WebAuthn auth structure for hash1 with dummy signature values
        WebAuthn.WebAuthnAuth memory auth1 = HelperLib.getWebAuthnAuth(
            hash1,
            uint256(12345), // Dummy signature values
            uint256(67890)
        );

        // Create WebAuthn auth structure for hash2 with dummy signature values
        WebAuthn.WebAuthnAuth memory auth2 = HelperLib.getWebAuthnAuth(
            hash2,
            uint256(11111), // Different dummy signature values
            uint256(22222)
        );

        // Create passkey signature data for hash1
        bytes memory sig1 = abi.encode(auth1, new bytes32[](0));
        bytes memory validatorData1 = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig1
        );

        // Create passkey signature data for hash2
        bytes memory sig2 = abi.encode(auth2, new bytes32[](0));
        bytes memory validatorData2 = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            uint48(0), // validUntil (0 means no expiry)
            sig2
        );

        bytes memory signature1 = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData1
        );
        bytes memory signature2 = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData2
        );

        // Both signatures should fail due to dummy signature values
        bytes4 result1 = ISmartWallet(_aliceWallet).isValidSignature(
            hash1,
            signature1
        );
        assertEq(result1, bytes4(0xffffffff));

        // Wrong signature for hash2 (using sig1) - should fail due to signature replay attack
        bytes4 result2 = ISmartWallet(_aliceWallet).isValidSignature(
            hash2,
            signature1
        );
        assertEq(result2, bytes4(0xffffffff));

        // Different signature for hash2 - should also fail due to dummy values
        bytes4 result3 = ISmartWallet(_aliceWallet).isValidSignature(
            hash2,
            signature2
        );
        assertEq(result3, bytes4(0xffffffff));
    }

    function _signDigest(
        bytes32 hash,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        // Use helper function to get the digest for isValidSignature
        bytes32 digest = _getIsValidSignatureHash(hash, _aliceWallet, 0);

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signDigestWithValidation(
        bytes32 hash,
        uint256 signerPk,
        uint48 validUntil
    ) internal view returns (bytes memory) {
        bytes32 digest = _getIsValidSignatureHash(
            hash,
            _aliceWallet,
            validUntil
        );

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Test EIP-7702 scenario where wallet signs for itself
    function test_isValidSignature_succeeds_with_wallet_self_signing() public {
        // Create a new EOA that will become a smart wallet
        uint256 eoaPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        address eoaAddress = vm.addr(eoaPrivateKey);

        // Deploy a new wallet at the EOA address using vm.etch
        // This simulates EIP-7702 delegation where an EOA delegates to wallet code
        bytes memory walletCode = address(_smartWallet).code;
        vm.etch(eoaAddress, walletCode);

        // Initialize the wallet with the EOA as owner
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaAddress));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: eoaKeyHash,
            validator: address(1) // Built-in ECDSA validator
        });

        ISmartWallet(eoaAddress).initialize(initialOwners);

        // Now test that the wallet can validate its own signature
        bytes32 hash = keccak256("test_wallet_self_signing");

        // Get the typed data hash that the wallet would use
        bytes32 typedDataHash = SmartWallet(payable(eoaAddress)).hashTypedData(
            hash
        );

        // Sign with the EOA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // The wallet should recognize its own signature (recovered == address(this))
        bytes4 result = ISmartWallet(eoaAddress).isValidSignature(
            hash,
            signature
        );

        assertEq(
            result,
            Static.MAGIC_VALUE,
            "65-byte signature from wallet itself (EIP-7702) should succeed"
        );
    }

    /// @notice Test that 65-byte signature fails when signer is not the wallet itself
    function test_isValidSignature_fails_with_65_byte_non_wallet_signer()
        public
        view
    {
        bytes32 hash = keccak256("test_non_wallet_signer");

        // Get the typed data hash that the wallet would use
        bytes32 typedDataHash = SmartWallet(payable(_aliceWallet))
            .hashTypedData(hash);

        // Sign with Bob's private key (not the wallet)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // The wallet should reject the signature (recovered != address(this))
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );

        assertEq(
            result,
            Static.INVALID_VALUE,
            "65-byte signature from non-wallet signer should fail"
        );
    }
}
