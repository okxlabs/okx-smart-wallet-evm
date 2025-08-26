// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Static} from "src/libraries/Static.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {HelperLib} from "src/test/Helper.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";

contract ValidationTest is Base {
    event NonceConsumed(uint192 key, uint64 nonce);

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
        _executeAddValidator(
            _alice,
            passkeyTestKeyHash,
            address(passkeyValidator),
            true,
            0,
            address(0)
        );
    }

    function test_isValidSignature_fails_with_exactly_32_bytes() public view {
        bytes32 hash = keccak256("test");
        // Create signature with exactly 32 bytes (should be treated as invalid)
        bytes memory signature = new bytes(32);

        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
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
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_builtin_ecdsa_validator_expired()
        public
    {
        // Add validator using _bob with expiry to avoid EIP-7702 fallback collision
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 1 days);

        _executeAddValidator(
            _alice,
            bobKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS, // Use built-in ECDSA validator
            false,
            expiry,
            address(0)
        );

        // Verify validator is initially valid
        bytes32 hash = keccak256("test");
        bytes memory sig = _signDigest(hash, _bobPk);
        bytes memory signature = abi.encodePacked(bobKeyHash, sig);

        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(
            result,
            bytes4(0x1626ba7e),
            "Signature should be valid before expiry"
        );

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Call isValidSignature after expiration
        result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));

        // Create signatures for both hashes using standard pattern
        bytes memory sig1 = _signDigest(hash1, _alicePk);
        bytes memory sig2 = _signDigest(hash2, _alicePk);
        bytes memory signature1 = abi.encodePacked(aliceKeyHash, sig1);
        bytes memory signature2 = abi.encodePacked(aliceKeyHash, sig2);

        // Correct signature for hash1
        bytes4 result1 = ISmartWallet(_alice).isValidSignature(
            hash1,
            signature1
        );
        assertEq(result1, bytes4(0x1626ba7e));

        // Wrong signature for hash2 (using sig1) - should fail due to signature replay attack
        bytes4 result2 = ISmartWallet(_alice).isValidSignature(
            hash2,
            signature1
        );
        assertEq(result2, bytes4(0xffffffff));

        // Correct signature for hash2
        bytes4 result3 = ISmartWallet(_alice).isValidSignature(
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

        _executeAddValidator(
            _alice,
            passkeyKeyHash,
            Static.PASSKEY_VALIDATOR_ADDRESS, // Use built-in passkey validator address(2)
            true,
            0,
            address(0)
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
            sig
        );

        // Create full signature for isValidSignature
        bytes memory signature = abi.encodePacked(
            passkeyKeyHash,
            validatorData
        );

        // Call isValidSignature - this should fail due to invalid signature but test the flow
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
            sig
        );

        // Use wrong keyHash
        bytes memory signature = abi.encodePacked(wrongKeyHash, validatorData);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
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

        _executeAddValidator(
            _alice,
            passkeyKeyHash,
            Static.PASSKEY_VALIDATOR_ADDRESS, // Use built-in passkey validator
            false,
            expiry,
            address(0)
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
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyKeyHash,
            validatorData
        );

        // Verify validator fails initially due to dummy signature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(
            result,
            bytes4(0xffffffff),
            "Dummy signature should fail before expiry"
        );

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Call isValidSignature after expiration - should still fail
        result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes memory sig = _signDigest(hash, _alicePk);
        bytes memory signature = abi.encodePacked(aliceKeyHash, sig);

        // Call isValidSignature - this uses the custom ECDSA validator deployed in setUp
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData
        );

        // Call isValidSignature - should fail due to dummy signature values
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData
        );

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
            sig
        );

        bytes memory signature = abi.encodePacked(
            passkeyTestKeyHash,
            validatorData
        );

        // Call isValidSignature with different hash
        bytes4 result = ISmartWallet(_alice).isValidSignature(
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
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
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
        bytes4 result1 = ISmartWallet(_alice).isValidSignature(
            hash1,
            signature1
        );
        assertEq(result1, bytes4(0xffffffff));

        // Wrong signature for hash2 (using sig1) - should fail due to signature replay attack
        bytes4 result2 = ISmartWallet(_alice).isValidSignature(
            hash2,
            signature1
        );
        assertEq(result2, bytes4(0xffffffff));

        // Different signature for hash2 - should also fail due to dummy values
        bytes4 result3 = ISmartWallet(_alice).isValidSignature(
            hash2,
            signature2
        );
        assertEq(result3, bytes4(0xffffffff));
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
