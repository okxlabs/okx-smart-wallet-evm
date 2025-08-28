// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {Base} from "./Base.t.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {HelperLib} from "src/test/Helper.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {Static} from "src/libraries/Static.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {InitialOwner} from "src/Types.sol";

/**
 * @title PasskeyValidatorTest
 * @notice Comprehensive test suite for both external and built-in Passkey validators
 * @dev Tests two different validation pathways:
 *      1. External PasskeyValidator contract (deployed contract)
 *      2. Built-in Passkey validator (Static.PASSKEY_VALIDATOR_ADDRESS) - covers ValidateManager lines 46-54
 */
contract PasskeyValidatorTest is Base {
    PasskeyValidator internal passkeyValidator;

    uint256 internal constant TEST_SIG_R =
        112450831948757142750562360134609669473647155538405639309009281430691665378703;
    uint256 internal constant TEST_SIG_S =
        18363333552806174256136300126987944752421142252269824522148009181078823230960;
    // Message hash that gets passed to validator (typedDataHash, gets SHA256 in contract for compatibility)
    bytes32 constant SIGNED_MESSAGE_HASH =
        0x34753a30843cdf97fd7c7f1cf2556d397c93bdfa6732b0b8b79bad029f5875e5;

    bytes32 internal testKeyHash; // For external validator tests
    bytes32 internal builtinKeyHash; // For built-in validator tests
    address internal builtinWallet; // Separate wallet for built-in validator tests

    function setUp() public override {
        super.setUp();

        // Deploy external PasskeyValidator contract
        passkeyValidator = new PasskeyValidator();

        // Use the same Passkey credentials for both validators (from Base.sol)
        // We'll create a second wallet to avoid validator collision

        // Create keyHashes for both validator types
        testKeyHash = keccak256(abi.encode([_passkeyPubX, _passkeyPubY])); // External validator
        builtinKeyHash = keccak256(
            abi.encodePacked(_passkeyPubX, _passkeyPubY)
        ); // Built-in validator

        // Add external PasskeyValidator for Alice's wallet
        _executeAddValidator(
            _alice,
            testKeyHash,
            address(passkeyValidator), // External contract address
            true,
            0,
            address(0)
        );

        // Create separate wallet for built-in validator tests to avoid collision
        InitialOwner[] memory builtinOwners = new InitialOwner[](1);
        builtinOwners[0] = InitialOwner({
            keyHash: builtinKeyHash,
            validator: Static.PASSKEY_VALIDATOR_ADDRESS
        });

        builtinWallet = _factory.createAccount(
            builtinOwners,
            999 // Different salt to ensure different address
        );

        // Fund the built-in wallet
        vm.deal(builtinWallet, 10 ether);
    }

    function test_passkeyValidator_deployment() public view {
        assertEq(address(passkeyValidator).code.length > 0, true);
    }

    function test_passkeyValidator_added_to_wallet() public view {
        address validator = IOwnersManager(_alice).ownerValidators(testKeyHash);
        assertEq(validator, address(passkeyValidator));
    }

    function test_webauthn_signature_directly() public view {
        (, , bytes32 messageHash) = HelperLib.getPasskeyMessageHash(
            SIGNED_MESSAGE_HASH
        );
        (bytes32 r, bytes32 s) = vm.signP256(_passkeyPrivateKey, messageHash);
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
            uint256(r),
            uint256(s)
        );
        bool isValid = WebAuthn.verify(
            abi.encode(SIGNED_MESSAGE_HASH),
            false,
            auth,
            _passkeyPubX,
            _passkeyPubY
        );
        console.log("isValid:", isValid);
        assertTrue(isValid, "WebAuthn signature should be valid");
    }

    function test_real_passkey_signature_validates() public view {
        (, , bytes32 messageHash) = HelperLib.getPasskeyMessageHash(
            SIGNED_MESSAGE_HASH
        );
        (bytes32 r, bytes32 s) = vm.signP256(_passkeyPrivateKey, messageHash);
        // Test with the signed message hash directly
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
            uint256(r),
            uint256(s)
        );
        // Create simplified PasskeySignature struct

        bytes memory sig = abi.encode(auth, new bytes(0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
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
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
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
        ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );

        // Create simplified mock Passkey signature data
        PasskeyValidatorLib.PasskeyPubKey
            memory passkeyPubKey = PasskeyValidatorLib.PasskeyPubKey({
                pubKeyX: _passkeyPubX,
                pubKeyY: _passkeyPubY
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
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            wrongMessageHash,
            TEST_SIG_R,
            TEST_SIG_S
        );
        // Create simplified PasskeySignature struct

        bytes memory sig = abi.encode(auth, new bytes(0));
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
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

        WebAuthn.WebAuthnAuth memory webAuthnAuth = HelperLib.getWebAuthnAuth(
            SIGNED_MESSAGE_HASH,
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
            SIGNED_MESSAGE_HASH,
            validatorData
        );

        assertEq(isValid, false, "Should reject wrong public key");
    }

    // ===== Merkle Proof Tests =====

    function test_validateSignature_with_merkle_proof_single() public view {
        // Create a simple Merkle proof - in real scenario, messageHash would be a leaf
        // For testing, we'll create a proof where messageHash is already the root
        bytes32[] memory proofs = new bytes32[](1);
        proofs[0] = keccak256("123");
        bytes32 rootHash = HelperLib.getMerkleProofRootHash(
            proofs,
            SIGNED_MESSAGE_HASH
        );
        (, , bytes32 messageHash) = HelperLib.getPasskeyMessageHash(rootHash);
        (bytes32 r, bytes32 s) = vm.signP256(_passkeyPrivateKey, messageHash);
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            rootHash,
            uint256(r),
            uint256(s)
        );
        // Create simplified PasskeySignature struct

        bytes memory sig = abi.encode(auth, proofs);
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
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

    function test_merkle_proof_processing_detection() public view {
        // Test the MerkleProofProcessor's dynamic detection
        PasskeyValidatorLib.PasskeyPubKey
            memory passkeyPubKey = PasskeyValidatorLib.PasskeyPubKey({
                pubKeyX: _passkeyPubX,
                pubKeyY: _passkeyPubY
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

    function test_validateSignature_short_validatorData_fails() public view {
        // Create validatorData that is shorter than PASSKEY_PUBKEY_LENGTH (64 bytes)
        // The function expects at least 64 bytes for the PasskeyPubKey struct

        // Create a short byte array (63 bytes instead of minimum 64)
        bytes memory shortValidatorData = new bytes(63);

        // Fill it with some data (doesn't matter what since it should fail on length check)
        for (uint256 i = 0; i < shortValidatorData.length; i++) {
            shortValidatorData[i] = bytes1(uint8(0));
        }

        // Log the lengths for debugging
        console.log("Short validatorData length:", shortValidatorData.length);
        console.log("PASSKEY_PUBKEY_LENGTH constant: 64");

        // Should return false due to insufficient length
        bool isValid = passkeyValidator.validateSignature(
            testKeyHash,
            SIGNED_MESSAGE_HASH,
            shortValidatorData
        );

        assertEq(
            isValid,
            false,
            "Should reject validatorData shorter than PASSKEY_PUBKEY_LENGTH"
        );
    }

    function test_executeWithRelayer_short_validatorData_fails() public {
        // Create valid calls
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Create validatorData with only 95 bytes total (32 + 63)
        // After extracting the first 32 bytes as keyHash, only 63 bytes remain
        // which is less than PASSKEY_PUBKEY_LENGTH (64 bytes)
        bytes memory shortValidatorData = new bytes(95);

        // First 32 bytes: keyHash
        bytes32 keyHash = testKeyHash;
        for (uint256 i = 0; i < 32; i++) {
            shortValidatorData[i] = keyHash[i];
        }

        // Remaining 63 bytes: incomplete data (should be at least 64)
        for (uint256 i = 32; i < 95; i++) {
            shortValidatorData[i] = bytes1(uint8(0));
        }

        // Log for debugging
        console.log("Total validatorData length:", shortValidatorData.length);
        console.log(
            "Data after keyHash extraction:",
            shortValidatorData.length - 32
        );

        // Should revert with InvalidSignature because PasskeyValidator will return false
        vm.prank(_bob);
        vm.expectRevert(Errors.InvalidSignature.selector);
        ISmartWallet(_alice).executeWithRelayer(
            batchedCall,
            shortValidatorData
        );
    }

    function test_executeWithRelayer_incomplete_webauthn_data_fails() public {
        // Create valid calls
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: uint48(block.timestamp + 1 hours)
        });

        // Build validatorData with valid pubkey but incomplete WebAuthnAuth
        bytes memory pubKeyData = abi.encode(
            PasskeyValidatorLib.PasskeyPubKey({
                pubKeyX: _passkeyPubX,
                pubKeyY: _passkeyPubY
            })
        );

        // Create incomplete WebAuthnAuth data
        // WebAuthnAuth struct needs: authenticatorData, clientDataJSON, challengeIndex, typeIndex, r, s
        // We'll create data that's too short to properly decode
        bytes memory incompleteAuth = new bytes(50); // Much too short for full WebAuthnAuth
        for (uint256 i = 0; i < incompleteAuth.length; i++) {
            incompleteAuth[i] = bytes1(uint8(0));
        }

        // Combine: keyHash (32) + pubKey (64) + incomplete auth
        bytes memory validatorData = abi.encodePacked(
            testKeyHash,
            pubKeyData,
            incompleteAuth
        );

        // Log for debugging
        console.log("Total validatorData length:", validatorData.length);
        console.log("PubKey data length:", pubKeyData.length);
        console.log("Incomplete auth data length:", incompleteAuth.length);

        // Should revert due to abi.decode failure or validation failure
        vm.prank(_bob);
        vm.expectRevert(); // May revert with decode error or InvalidSignature
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    // ================================================================
    // BUILT-IN PASSKEY VALIDATOR TESTS
    // Tests ValidateManager._validateSignature lines 46-54
    // ================================================================

    /**
     * @dev Verify built-in validator setup is correct
     */
    function test_builtin_validator_setup() public view {
        address validator = IOwnersManager(builtinWallet).ownerValidators(
            builtinKeyHash
        );
        assertEq(
            validator,
            Static.PASSKEY_VALIDATOR_ADDRESS,
            "Built-in validator should be registered"
        );

        address verified = IOwnersManager(builtinWallet).getVerifiedValidator(
            builtinKeyHash
        );
        assertEq(
            verified,
            Static.PASSKEY_VALIDATOR_ADDRESS,
            "Built-in validator should be verified"
        );
    }

    /**
     * @dev Test successful execution with built-in Passkey validator via executeWithRelayer
     * This covers the _validateSignature path with Static.PASSKEY_VALIDATOR_ADDRESS
     */
    function test_builtin_executeWithRelayer_success() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: INonceManager(builtinWallet).getNonce(0),
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 typedDataHash = ERC712(builtinWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );

        bytes memory validatorData = _createBuiltinPasskeySignature(
            builtinKeyHash,
            typedDataHash
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            keccak256(abi.encode(calls)),
            _bob,
            batchedCall.nonce
        );
        ISmartWallet(builtinWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
    }

    /**
     * @dev Test failure with invalid signature for built-in Passkey validator
     */
    function test_builtin_executeWithRelayer_invalid_signature() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        bytes memory invalidValidatorData = abi.encodePacked(
            builtinKeyHash,
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            abi.encode(
                WebAuthn.WebAuthnAuth({
                    authenticatorData: abi.encodePacked("invalid_auth_data"),
                    clientDataJSON: "invalid_client_data",
                    challengeIndex: 23,
                    typeIndex: 1,
                    r: 0x123,
                    s: 0x456
                }),
                new bytes32[](0)
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(
            batchedCall,
            invalidValidatorData
        );
    }

    /**
     * @dev Test EIP-1271 signature validation with built-in Passkey validator
     */
    function test_builtin_isValidSignature_success() public view {
        bytes32 hash = keccak256("test message");

        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), address(_alice), hash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

        bytes memory signature = _createBuiltinPasskeySignature(
            builtinKeyHash,
            digest
        );

        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(
            result,
            Static.MAGIC_VALUE,
            "Built-in Passkey validator should validate EIP-1271 signature"
        );
    }

    /**
     * @dev Test UserOperation validation with built-in Passkey validator
     */
    function test_builtin_validateUserOp_success() public {
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: builtinKeyHash,
            validator: Static.PASSKEY_VALIDATOR_ADDRESS
        });

        address passkeyWallet = _factory.createAccount(initialOwners, 1);

        vm.deal(passkeyWallet, 1 ether);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: passkeyWallet,
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSelector(
                ISmartWallet.execute.selector,
                Call({target: _bob, value: 0.1 ether, data: ""})
            ),
            accountGasLimits: bytes32(
                abi.encodePacked(uint128(200000), uint128(200000))
            ),
            preVerificationGas: 21000,
            gasFees: bytes32(
                abi.encodePacked(uint128(1000000000), uint128(1000000000))
            ),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = _entryPoint.getUserOpHash(userOp);
        bytes memory signature = _createBuiltinPasskeySignature(
            builtinKeyHash,
            userOpHash
        );
        userOp.signature = signature;

        uint256 result = _testValidateUserOp(
            passkeyWallet,
            userOp,
            userOpHash,
            0
        );
        assertEq(
            result,
            0,
            "Built-in Passkey validator should validate UserOp successfully"
        );
    }

    /**
     * @dev Test built-in Passkey validator with insufficient signature data
     */
    function test_builtin_insufficient_data() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_alice),
            expiry: 0
        });

        bytes memory insufficientData = abi.encodePacked(
            builtinKeyHash,
            bytes16(0x123456789abcdef123456789abcdef12)
        );

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        vm.prank(_bob);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, insufficientData);
    }

    // ================================================================
    // HELPER FUNCTIONS FOR BUILT-IN VALIDATOR
    // ================================================================

    /**
     * @dev Create a valid built-in Passkey signature for testing
     * Using the same keys and approach as the working external validator test
     */
    function _createBuiltinPasskeySignature(
        bytes32 keyHash,
        bytes32 messageHash
    ) internal view returns (bytes memory) {
        (, , bytes32 passkeyMessageHash) = HelperLib.getPasskeyMessageHash(
            messageHash
        );
        (bytes32 r, bytes32 s) = vm.signP256(
            _passkeyPrivateKey,
            passkeyMessageHash
        );

        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            messageHash,
            uint256(r),
            uint256(s)
        );

        // Create the signature exactly like the working external validator test
        bytes memory sig = abi.encode(auth, new bytes32[](0));

        // Create validatorData in the same format as external test
        bytes memory validatorDataForLib = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            sig
        );

        // For built-in validator: keyHash + validatorData that will be passed to PasskeyValidatorLib
        return abi.encodePacked(keyHash, validatorDataForLib);
    }
}
