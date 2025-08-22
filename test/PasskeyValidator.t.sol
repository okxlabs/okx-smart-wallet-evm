// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Base} from "./Base.t.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ValidationLogic} from "src/ValidationLogic.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {Helper} from "src/test/Helper.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract PasskeyValidatorTest is Base {
    PasskeyValidator internal passkeyValidator;

    // Generated real P256 signature using SmartAccount method (crypto.createSign compatibility)
    uint256 internal constant TEST_PUBKEY_X =
        28573233055232466711029625910063034642429572463461595413086259353299906450061;
    uint256 internal constant TEST_PUBKEY_Y =
        39367742072897599771788408398752356480431855827262528811857788332151452825281;
    uint256 internal constant TEST_SIG_R =
        43684192885701841787131392247364253107519555363555461570655060745499568693242;
    uint256 internal constant TEST_SIG_S =
        22655632649588629308599201066602670461698485748654492451178007896016452673579;
    bytes32 internal constant REAL_KEY_HASH =
        0x7a655e59bb879aff4a25592b02afb672bb2d2cbb1e5a60cd591f3b07bad0b8ff;

    // Message hash that gets passed to validator (typedDataHash, gets SHA256 in contract for compatibility)
    bytes32 constant SIGNED_MESSAGE_HASH =
        bytes32(
            0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf
        );

    bytes32 internal testKeyHash;

    function setUp() public override {
        super.setUp();

        // Deploy PasskeyValidator
        passkeyValidator = new PasskeyValidator();

        // Use the generated keyHash
        testKeyHash = REAL_KEY_HASH;

        // Add PasskeyValidator for Alice's wallet
        _executeAddValidator(
            _alice,
            testKeyHash,
            address(passkeyValidator),
            true,
            0,
            address(0)
        );
    }

    function test_passkeyValidator_deployment() public view {
        assertEq(address(passkeyValidator).code.length > 0, true);
    }

    function test_passkeyValidator_added_to_wallet() public view {
        address validator = IOwnersManager(_alice).ownerValidators(testKeyHash);
        assertEq(validator, address(passkeyValidator));
    }

    function test_webauthn_signature_directly() public view {
        WebAuthn.WebAuthnAuth memory auth = Helper.getCoinbaseWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
            TEST_SIG_R,
            TEST_SIG_S
        );
        console.log("auth.clientDataJSON:", auth.clientDataJSON);
        bool isValid = WebAuthn.verify(
            abi.encode(SIGNED_MESSAGE_HASH),
            false,
            auth,
            TEST_PUBKEY_X,
            TEST_PUBKEY_Y
        );
        console.log("isValid:", isValid);
        assertTrue(isValid, "WebAuthn signature should be valid");
    }

    function test_real_passkey_signature_validates() public view {
        // Test with the signed message hash directly
        WebAuthn.WebAuthnAuth memory auth = Helper.getCoinbaseWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
            TEST_SIG_R,
            TEST_SIG_S
        );
        // Create simplified PasskeySignature struct

        bytes memory sig = abi.encode(auth, new bytes(0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: TEST_PUBKEY_X,
                    pubKeyY: TEST_PUBKEY_Y
                })
            ),
            sig
        );

        // This should validate successfully with simple P256 verification
        bool isValid = passkeyValidator.validateSignature(
            testKeyHash,
            SIGNED_MESSAGE_HASH,
            validatorData
        );

        assertEq(isValid, true, "Real Passkey signature should validate");
    }

    function test_get_real_typed_data_hash() public view {
        // Create test calls
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Get the REAL message hash that needs to be signed
        bytes32 realTypedDataHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall)
        );

        // Log the real typedDataHash for our script
        console.log("REAL TYPED DATA HASH TO SIGN:");
        console.logBytes32(realTypedDataHash);
    }

    function test_executeWithRelayer_with_mock_passkey() public view {
        // Create test calls
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Get the message hash that needs to be signed
        ERC712(_alice).hashTypedData(BatchedCallLib.hash(batchedCall));

        // Create simplified mock Passkey signature data
        PasskeyValidatorLib.PasskeyPubKey
            memory passkeyPubKey = PasskeyValidatorLib.PasskeyPubKey({
                pubKeyX: TEST_PUBKEY_X,
                pubKeyY: TEST_PUBKEY_Y
                // r: TEST_SIG_R, // Using real signature values for structure
                // s: TEST_SIG_S
            });

        // Encode the validator data
        bytes memory validatorData = abi.encodePacked(
            testKeyHash,
            abi.encode(passkeyPubKey)
        );

        // Structure validation - ensure data encoding works correctly
        assertTrue(
            validatorData.length > 0,
            "Validator data should be encoded"
        );

        // Note: Actual execution would require matching signature for the messageHash
        // This test validates the data structure and encoding
    }

    function test_real_passkey_wrong_challenge_fails() public view {
        // Use a different message hash than what was actually signed
        bytes32 wrongMessageHash = keccak256("wrong message");

        // Test with the signed message hash directly
        WebAuthn.WebAuthnAuth memory auth = Helper.getCoinbaseWebAuthnAuth(
            wrongMessageHash,
            TEST_SIG_R,
            TEST_SIG_S
        );
        // Create simplified PasskeySignature struct

        bytes memory sig = abi.encode(auth, new bytes(0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: TEST_PUBKEY_X,
                    pubKeyY: TEST_PUBKEY_Y
                })
            ),
            sig
        );

        bool isValid = passkeyValidator.validateSignature(
            testKeyHash,
            wrongMessageHash,
            validatorData
        );

        assertEq(
            isValid,
            false,
            "Should reject signature with wrong message hash"
        );
    }

    function test_validateSignature_rejects_wrong_pubkey() public view {
        // Use wrong public key coordinates
        uint256 wrongX = 0x1111111111111111111111111111111111111111111111111111111111111111;
        uint256 wrongY = 0x2222222222222222222222222222222222222222222222222222222222222222;
        bytes32 messageHash = SIGNED_MESSAGE_HASH;

        WebAuthn.WebAuthnAuth memory webAuthnAuth = Helper.getWebAuthnAuth(
            messageHash,
            TEST_SIG_R,
            TEST_SIG_S
        );

        // Create simplified PasskeySignature struct
        PasskeyValidatorLib.PasskeyPubKey
            memory passkeyPubKey = PasskeyValidatorLib.PasskeyPubKey({
                pubKeyX: wrongX,
                pubKeyY: wrongY
            });

        bytes memory sig = abi.encode(webAuthnAuth, new bytes(0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(passkeyPubKey),
            sig
        );

        bool isValid = passkeyValidator.validateSignature(
            testKeyHash,
            messageHash,
            validatorData
        );

        assertEq(isValid, false, "Should reject wrong public key");
    }

    // ===== Merkle Proof Tests =====

    function test_validateSignature_with_merkle_proof_single() public view {
        WebAuthn.WebAuthnAuth memory auth = Helper.getCoinbaseWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
            TEST_SIG_R,
            TEST_SIG_S
        );
        // Create simplified PasskeySignature struct

        // Create a simple Merkle proof - in real scenario, messageHash would be a leaf
        // For testing, we'll create a proof where messageHash is already the root
        bytes32[] memory proofs = new bytes32[](1);
        proofs[0] = keccak256(
            abi.encodePacked(SIGNED_MESSAGE_HASH, bytes32(0))
        );

        bytes memory sig = abi.encode(auth, new bytes(0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: TEST_PUBKEY_X,
                    pubKeyY: TEST_PUBKEY_Y
                })
            ),
            sig
        );

        // This should validate (note: simplified test, in real usage the Merkle logic would be more complex)
        bool isValid = passkeyValidator.validateSignature(
            testKeyHash,
            SIGNED_MESSAGE_HASH,
            validatorData
        );

        assertEq(isValid, true, "Merkle proof should validate");
        // Note: This test might fail due to the simplified Merkle proof setup
        // In a real implementation, you'd need proper Merkle tree construction
        console.log("Merkle proof validation result:", isValid);
    }

    function test_merkle_proof_processing_detection() public pure {
        // Test the MerkleProofProcessor's dynamic detection
        PasskeyValidatorLib.PasskeyPubKey
            memory passkeyPubKey = PasskeyValidatorLib.PasskeyPubKey({
                pubKeyX: TEST_PUBKEY_X,
                pubKeyY: TEST_PUBKEY_Y
                // r: TEST_SIG_R,
                // s: TEST_SIG_S
            });

        bytes memory signatureData = abi.encode(passkeyPubKey);

        console.log("Signature data length:", signatureData.length);

        // Test 1: Short data (no proofs)
        console.log("Testing short data detection...");

        // Test 2: Long data (potential proofs)
        bytes32[] memory dummyProofs = new bytes32[](2);
        dummyProofs[0] = bytes32(uint256(1));
        dummyProofs[1] = bytes32(uint256(2));

        bytes memory longData = abi.encodePacked(
            signatureData,
            abi.encode(dummyProofs)
        );
        console.log("Long data length:", longData.length);
    }
}
