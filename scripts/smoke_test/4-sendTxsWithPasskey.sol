// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/interfaces/ISmartWallet.sol";
import "src/SmartWallet.sol";
import "src/interfaces/IOwnerManager.sol";
import "src/interfaces/INonceManager.sol";
import "src/libraries/BatchedCallLib.sol";
import "src/libraries/PasskeyValidatorLib.sol";
import "src/Types.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "../utils/Helper.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {Static} from "src/libraries/Static.sol";

/// @title SendTxsWithPasskey
/// @notice A script for adding an EOA owner using Passkey signature and Merkle proof through executeWithRelayer
/// @dev This demonstrates Merkle proof validation with Passkey signatures
contract SendTxsWithPasskey is Script {

    function run() external {
        // Get first Passkey credentials (already an owner)
        uint256 passkeyPrivateKey1 = vm.envUint("PASSKEY_PRIVATE_KEY");
        uint256 passkeyPubX1 = vm.envUint("PASSKEY_PUB_X");
        uint256 passkeyPubY1 = vm.envUint("PASSKEY_PUB_Y");
        
        address passkeyValidator = vm.envAddress("PASSKEY_VALIDATOR");
        
        // Get user wallet address (the SmartWallet account)
        address payable userWallet = payable(vm.envAddress("USER_WALLET"));
        
        // Use deployer to broadcast the transaction as relayer
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        
        vm.startBroadcast(deployerPk);
        
        console.log("User wallet: ", userWallet);
        console.log("Relayer (deployer): ", deployer);
        console.log("PasskeyValidator: ", passkeyValidator);
        
        console.log("\n=== Add EOA owner using first Passkey + Merkle ===");
        
        // Generate a random EOA owner address for testing
        address payable newEOAOwner = payable(address(0x1234567890AbcdEF1234567890aBcdef12345678));
        
        // Add EOA owner using Merkle proof via executeWithRelayer
        _addEOAOwnerWithMerkle(
            userWallet,
            newEOAOwner,
            passkeyPrivateKey1,
            passkeyPubX1,
            passkeyPubY1,
            passkeyValidator
        );

        console.log("\nCompleted SendTxsWithPasskey script");
        vm.stopBroadcast();
    }

    function _addEOAOwnerWithMerkle(
        address payable userWallet,
        address payable newEOAOwner,
        uint256 signerPrivateKey,
        uint256 signerPubX,
        uint256 signerPubY,
        address validator
    ) private {
        // Calculate new EOA owner's keyHash
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newEOAOwner));
        console.log("New EOA owner address:", newEOAOwner);
        console.log("New EOA owner keyHash:");
        console.logBytes32(newOwnerKeyHash);
        
        // Create calls for adding owner
        Call[] memory calls = _createAddOwnerCall(userWallet, newOwnerKeyHash, validator);
        
        // Get chainless nonce (matching EntryPoint version)
        uint256 nonce = _getChainlessNonce(userWallet);
        
        // Create BatchedCall and get hash with Merkle proof
        (BatchedCall memory batchedCall, bytes32 merkleRoot, bytes32[] memory merkleProof) = 
            _prepareBatchedCallWithMerkle(userWallet, nonce, calls);
        
        // Create signature for the Merkle root
        bytes memory validatorData = _createPasskeySignatureWithMerkle(
            signerPrivateKey,
            signerPubX,
            signerPubY,
            merkleRoot,
            0, // validUntil (0 means no expiry, matching EntryPoint)
            merkleProof
        );
        
        // Execute with relayer using Passkey signature and Merkle proof
        console.log("Executing addOwner with Passkey signature and Merkle proof via executeWithRelayer...");
        ISmartWallet(userWallet).executeWithRelayer(batchedCall, validatorData);
        
        console.log("Successfully added EOA owner via executeWithRelayer using Merkle proof!");
    }


    function _createAddOwnerCall(
        address userWallet,
        bytes32 newOwnerKeyHash,
        address validator
    ) private pure returns (Call[] memory) {
        uint256 settings = OwnerManager(userWallet).packSettings(
            true, // isAdmin = true
            0,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 //random address as hook
        );
        Call[] memory calls = new Call[](1);
        
        calls[0] = Call({
            target: userWallet,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                validator,
                settings  // settings with hook
            )
        });
        
        return calls;
    }


    function _getChainlessNonce(
        address userWallet
    ) private view returns (uint256) {
        // Get chainless nonce (matching EntryPoint version)
        uint192 chainlessKey = uint192(Static.CHAIN_LESS_NONCE_KEY);
        uint256 sequentialNonce = INonceManager(userWallet).getNonce(chainlessKey);
        return (uint256(chainlessKey) << 64) | sequentialNonce;
    }


    function _prepareBatchedCallWithMerkle(
        address payable userWallet,
        uint256 nonce,
        Call[] memory calls
    ) private view returns (
        BatchedCall memory batchedCall,
        bytes32 merkleRoot,
        bytes32[] memory merkleProof
    ) {
        // Create base BatchedCall (without signature)
        batchedCall = BatchedCall({
            calls: calls,
            nonce: nonce
        });
        
        // Get the hash to sign (matching EntryPoint version)
        bytes32 hashToSign = _getValidationHash(userWallet, batchedCall);
        
        // Create a random second leaf for merkle tree (matching EntryPoint version)
        bytes32 leaf1 = hashToSign;
        bytes32 leaf2 = keccak256(abi.encodePacked("random leaf for merkle tree demo", block.timestamp));
        
        console.log("Merkle tree leaf1 (addOwner):");
        console.logBytes32(leaf1);
        console.log("Merkle tree leaf2 (random):");
        console.logBytes32(leaf2);
        
        // Compute Merkle root
        merkleRoot = _computeMerkleRoot(leaf1, leaf2);
        console.log("Merkle root:");
        console.logBytes32(merkleRoot);
        
        // Generate Merkle proof for leaf1 (index 0)
        merkleProof = _generateMerkleProof(leaf1, leaf2, 0);
    }

    function _getValidationHash(
        address payable userWallet,
        BatchedCall memory batchedCall
    ) private view returns (bytes32) {
        // Get implementation address for hash calculation
        address implementation = vm.envAddress("SMART_WALLET");
        
        // Calculate the hash to sign (matching EntryPoint version)
        bytes32 hash = BatchedCallLib.hash(batchedCall, 0, implementation);
        
        // Since we're using chainless nonce, we need to use hashTypedDataSansChainId
        return SmartWallet(userWallet).hashTypedDataSansChainId(hash);
    }

    // Merkle tree helper functions (matching EntryPoint version exactly)
    function _computeMerkleRoot(bytes32 leaf1, bytes32 leaf2) private pure returns (bytes32) {
        // Sort leaves for consistent hashing (OpenZeppelin standard)
        if (leaf1 <= leaf2) {
            return keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            return keccak256(abi.encodePacked(leaf2, leaf1));
        }
    }
    
    function _generateMerkleProof(
        bytes32 leaf1,
        bytes32 leaf2,
        uint256 leafIndex
    ) private pure returns (bytes32[] memory) {
        require(leafIndex < 2, "Invalid leaf index for 2-leaf tree");
        
        bytes32[] memory proof = new bytes32[](1);
        if (leafIndex == 0) {
            // If proving leaf1, provide leaf2 as proof
            proof[0] = leaf2;
        } else {
            // If proving leaf2, provide leaf1 as proof
            proof[0] = leaf1;
        }
        return proof;
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
        (string memory clientDataJson, , bytes32 passkeyMessageHash) = 
            HelperLib.getPasskeyMessageHash(merkleRoot);
        
        // Sign with P256 curve
        (bytes32 r, bytes32 s) = vm.signP256(signerPrivateKey, passkeyMessageHash);
        
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
        bytes32 signerKeyHash = keccak256(abi.encodePacked(signerPubX, signerPubY));
        
        // Create the complete signature data using helper function
        return _packSignatureWithMerkle(
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