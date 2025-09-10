// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {InitialOwner, Call, BatchedCall} from "src/Types.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {Static} from "src/libraries/Static.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "../utils/Helper.sol";

/// @title CreateAccountWithAddOwner
/// @notice Creates a SmartWallet with initial Passkey owner and immediately adds a random EOA owner using Merkle proof
/// @dev Uses createAccountWithCall to perform both operations in a single transaction
contract CreateAccountWithAddOwner is Script {
    function run() external {
        // Get environment variables
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        address deployer = vm.addr(deployerPk);
        console.log("Deployer address: ", deployer);
        console.log("Factory address: ", vm.envAddress("SMART_WALLET_FACTORY"));
        console.log("Implementation address: ", vm.envAddress("SMART_WALLET"));
        console.log("PasskeyValidator: ", vm.envAddress("PASSKEY_VALIDATOR"));

        console.log(
            "\n=== Creating account with initial Passkey and adding EOA via createAccountWithCall ==="
        );

        // Execute the account creation
        address newAccount = _executeAccountCreation(deployer);

        console.log("\n==============================");
        console.log("SmartWallet account created at: ", newAccount);
        console.log("==============================\n");

        console.log("Account created with:");
        console.log("- Initial Passkey owner");
        console.log("- Added EOA owner via Merkle proof");
        console.log("\nCompleted CreateAccountWithAddOwner script");

        vm.stopBroadcast();
    }

    function _executeAccountCreation(
        address deployer
    ) private returns (address) {
        // 1. Prepare initial owner (only Passkey)
        uint256 passkeyPubX = vm.envUint("PASSKEY_PUB_X");
        uint256 passkeyPubY = vm.envUint("PASSKEY_PUB_Y");
        bytes32 passkeyKeyHash = keccak256(
            abi.encodePacked(passkeyPubX, passkeyPubY)
        );

        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: passkeyKeyHash,
            validator: vm.envAddress("PASSKEY_VALIDATOR")
        });

        console.log("Initial Passkey owner:");
        console.log("  PubKey X: ", passkeyPubX);
        console.log("  PubKey Y: ", passkeyPubY);
        console.log("  KeyHash: ");
        console.logBytes32(passkeyKeyHash);

        // 2. Generate random salt
        uint256 salt = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    deployer,
                    "SMART_WALLET_WITH_CALL"
                )
            )
        );
        console.log("Using salt: ", salt);

        // 3. Predict the account address
        address predictedAddress = SmartWalletFactory(
            vm.envAddress("SMART_WALLET_FACTORY")
        ).getAddress(initialOwners, salt);
        console.log("Predicted account address: ", predictedAddress);

        // 4. Generate random EOA owner to be added
        address randomEoaAddress = vm.addr(
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        deployer,
                        "RANDOM_EOA_OWNER"
                    )
                )
            )
        );
        bytes32 eoaKeyHash = bytes32(uint256(uint160(randomEoaAddress)));

        console.log("\nEOA owner to be added:");
        console.log("  Address: ", randomEoaAddress);
        console.log("  KeyHash: ");
        console.logBytes32(eoaKeyHash);

        // 5. Create BatchedCall for addOwner with hook
        BatchedCall memory batchedCall = BatchedCall({
            calls: _createAddOwnerCall(predictedAddress, eoaKeyHash),
            nonce: (uint256(Static.CHAIN_LESS_NONCE_KEY) << 64) | 0
        });

        // 6. Create Merkle tree with 2 leaves
        bytes32 typedHash = _computeTypedHashSansChainId(
            BatchedCallLib.hash(batchedCall, 0, vm.envAddress("SMART_WALLET")),
            predictedAddress
        );

        bytes32 leaf2 = keccak256(
            abi.encodePacked(
                "random leaf for merkle tree demo",
                block.timestamp
            )
        );

        console.log("\nMerkle tree construction:");
        console.log("Leaf1 (addOwner operation):");
        console.logBytes32(typedHash);
        console.log("Leaf2 (random):");
        console.logBytes32(leaf2);

        bytes32 merkleRoot = _computeMerkleRoot(typedHash, leaf2);
        console.log("Merkle root:");
        console.logBytes32(merkleRoot);

        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = leaf2;

        // 7. Create Passkey signature for Merkle root
        bytes memory validatorData = _createPasskeySignatureWithMerkle(
            vm.envUint("PASSKEY_PRIVATE_KEY"),
            passkeyPubX,
            passkeyPubY,
            merkleRoot,
            0, // validUntil
            merkleProof
        );

        console.log("\nSignature data length:", validatorData.length);

        // 8. Execute createAccountWithCall
        console.log("\nExecuting createAccountWithCall...");
        return
            SmartWalletFactory(vm.envAddress("SMART_WALLET_FACTORY"))
                .createAccountWithCall(
                    initialOwners,
                    salt,
                    batchedCall,
                    validatorData
                );
    }

    function _createAddOwnerCall(
        address userWallet,
        bytes32 newOwnerKeyHash
    ) private pure returns (Call[] memory) {
        // Pack settings with hook (same as test 4)
        // Manual implementation of packSettings
        uint256 settings = 0;
        settings |= 1; // isAdmin = true (bit 0)
        // packHook: hook address in bits 96-255
        settings |=
            uint256(uint160(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)) <<
            96;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: userWallet, // self-call
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                settings // settings with hook
            )
        });
        return calls;
    }

    function _computeTypedHashSansChainId(
        bytes32 structHash,
        address predictedWallet
    ) private pure returns (bytes32) {
        // Calculate domain typehash (without chainId)
        bytes32 domainTypehash = keccak256(
            "EIP712Domain(string name,string version,address verifyingContract)"
        );

        // Build domain separator with predicted wallet address as verifyingContract
        bytes32 domainSeparator = keccak256(
            abi.encode(
                domainTypehash,
                keccak256(bytes("SmartWallet")),
                keccak256(bytes("1.0.0")),
                predictedWallet // Use predicted wallet address
            )
        );

        // Return EIP-712 formatted hash
        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
    }

    function _computeMerkleRoot(
        bytes32 leaf1,
        bytes32 leaf2
    ) private pure returns (bytes32) {
        // Sort leaves for consistent hashing (OpenZeppelin standard)
        if (leaf1 <= leaf2) {
            return keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            return keccak256(abi.encodePacked(leaf2, leaf1));
        }
    }

    function _createPasskeySignatureWithMerkle(
        uint256 signerPrivateKey,
        uint256 signerPubX,
        uint256 signerPubY,
        bytes32 merkleRoot,
        uint48 validUntil,
        bytes32[] memory merkleProof
    ) private pure returns (bytes memory) {
        // Generate Passkey signature for the Merkle root
        (string memory clientDataJson, , bytes32 passkeyMessageHash) = HelperLib
            .getPasskeyMessageHash(merkleRoot);

        // Sign with P256 curve
        (bytes32 r, bytes32 s) = vm.signP256(
            signerPrivateKey,
            passkeyMessageHash
        );

        // Create WebAuthnAuth structure
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: HelperLib.AUTHENTICATOR_DATA,
            clientDataJSON: clientDataJson,
            typeIndex: HelperLib.TYPE_INDEX,
            challengeIndex: HelperLib.CHALLENGE_LOCATION,
            r: uint256(r),
            s: uint256(s)
        });

        // Encode the signature with Merkle proofs
        bytes memory sig = abi.encode(auth, merkleProof);

        // Calculate keyHash for the signing Passkey
        bytes32 signerKeyHash = keccak256(
            abi.encodePacked(signerPubX, signerPubY)
        );

        // Create the complete signature data
        return
            _packSignatureWithMerkle(
                signerKeyHash,
                validUntil,
                signerPubX,
                signerPubY,
                sig
            );
    }

    function _packSignatureWithMerkle(
        bytes32 signerKeyHash,
        uint48 validUntil,
        uint256 pubX,
        uint256 pubY,
        bytes memory sig
    ) private pure returns (bytes memory) {
        // For Merkle proof, the validatorData format is:
        // PasskeyPubKey (encoded) + WebAuthnAuth with merkleProof (already in sig)
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: pubX,
                    pubKeyY: pubY
                })
            ),
            sig
        );

        // Return format: keyHash + validUntil + validatorData
        return abi.encodePacked(signerKeyHash, validUntil, validatorData);
    }
}
