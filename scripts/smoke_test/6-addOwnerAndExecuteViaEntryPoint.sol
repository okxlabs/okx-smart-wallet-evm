// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/interfaces/ISmartWallet.sol";
import "src/SmartWallet.sol";
import "src/interfaces/IOwnerManager.sol";
import "src/libraries/BatchedCallLib.sol";
import "src/libraries/PasskeyValidatorLib.sol";
import "src/Types.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "../utils/Helper.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Static} from "src/libraries/Static.sol";

/// @title AddOwnerAndExecuteViaEntryPoint
/// @notice A script for adding an owner and executing transactions using Passkey signature through ERC-4337 EntryPoint
contract AddOwnerAndExecuteViaEntryPoint is Script {
    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    // Merkle tree helper functions
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
    
    function run() external {
        // Get first Passkey credentials (already an owner)
        uint256 passkeyPrivateKey1 = vm.envUint("PASSKEY_PRIVATE_KEY");
        uint256 passkeyPubX1 = vm.envUint("PASSKEY_PUB_X");
        uint256 passkeyPubY1 = vm.envUint("PASSKEY_PUB_Y");
        
        // Get second Passkey credentials (to be added as owner)
        uint256 passkeyPrivateKey2 = vm.envUint("PASSKEY_PRIVATE_KEY_2");
        uint256 passkeyPubX2 = vm.envUint("PASSKEY_PUB_X_2");
        uint256 passkeyPubY2 = vm.envUint("PASSKEY_PUB_Y_2");
        
        address passkeyValidator = vm.envAddress("PASSKEY_VALIDATOR");
        
        // Get user wallet address (the SmartWallet account)
        address payable userWallet = payable(vm.envAddress("USER_WALLET"));
        
        // Use deployer to broadcast the transaction as bundler
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        
        vm.startBroadcast(deployerPk);
        
        console.log("User wallet: ", userWallet);
        console.log("Bundler (deployer): ", deployer);
        console.log("PasskeyValidator: ", passkeyValidator);
        
        // Deploy EntryPoint if on local test network
        IEntryPoint entryPoint = _ensureEntryPoint();
        
        console.log("\n=== Step 1: Add second Passkey as owner via EntryPoint ===");
        
        // First, add second Passkey as an owner using first Passkey's signature via EntryPoint
        _addPasskeyOwnerViaEntryPoint(
            entryPoint,
            userWallet,
            passkeyPrivateKey1,
            passkeyPubX1,
            passkeyPubY1,
            passkeyPubX2,
            passkeyPubY2,
            passkeyValidator,
            deployer
        );
        
        console.log("\n=== Step 2: Send transaction using second Passkey via EntryPoint ===");
        
        // Then execute transaction with second Passkey signature via EntryPoint
        _executeWithPasskeyViaEntryPoint(
            entryPoint,
            userWallet,
            passkeyPrivateKey2,
            passkeyPubX2,
            passkeyPubY2,
            deployer
        );
        
        console.log("\nCompleted AddOwnerAndExecuteViaEntryPoint script");
        vm.stopBroadcast();
    }
    
    function _ensureEntryPoint() private returns (IEntryPoint) {
        // Only deploy EntryPoint on local test network (anvil)
        if (block.chainid == 31337) {
            // Check if EntryPoint already exists
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(ENTRYPOINT_ADDRESS)
            }
            
            if (codeSize == 0) {
                console.log("Deploying EntryPoint for local testing...");
                EntryPoint entryPointImpl = new EntryPoint();
                vm.etch(ENTRYPOINT_ADDRESS, address(entryPointImpl).code);
                vm.deal(ENTRYPOINT_ADDRESS, 100 ether); // Fund for gas payments
                console.log("EntryPoint deployed at:", ENTRYPOINT_ADDRESS);
            } else {
                console.log("EntryPoint already exists at:", ENTRYPOINT_ADDRESS);
            }
        } else {
            console.log("Using existing EntryPoint at:", ENTRYPOINT_ADDRESS);
        }
        
        return IEntryPoint(ENTRYPOINT_ADDRESS);
    }
    
    function _addPasskeyOwnerViaEntryPoint(
        IEntryPoint entryPoint,
        address payable userWallet,
        uint256 signerPrivateKey,
        uint256 signerPubX,
        uint256 signerPubY,
        uint256 newOwnerPubX,
        uint256 newOwnerPubY,
        address validator,
        address bundler
    ) private {
        // Calculate new owner keyHash
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwnerPubX, newOwnerPubY));
        console.log("Adding new Passkey owner with keyHash:");
        console.logBytes32(newOwnerKeyHash);
        
        // Create calls for adding owner
        Call[] memory calls = _createAddOwnerCall(userWallet, newOwnerKeyHash, validator);
        
        // Get chainless nonce
        uint256 nonce = _getChainlessNonce(entryPoint, userWallet);
        
        // Create UserOperation and get hash with Merkle proof
        (PackedUserOperation memory userOp, bytes32 merkleRoot, bytes32[] memory merkleProof) = 
            _prepareUserOpWithMerkle(userWallet, nonce, calls);
        
        // Create signature for the Merkle root
        userOp.signature = _createPasskeySignatureWithMerkle(
            signerPrivateKey,
            signerPubX,
            signerPubY,
            merkleRoot,
            0, // validUntil
            merkleProof
        );
        
        // Submit UserOperation
        console.log("Submitting UserOp with Merkle proof to EntryPoint...");
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        entryPoint.handleOps(ops, payable(bundler));
        
        console.log("Successfully added second Passkey as owner via EntryPoint using Merkle proof!");
    }
    
    function _prepareUserOpWithMerkle(
        address payable userWallet,
        uint256 nonce,
        Call[] memory calls
    ) private view returns (
        PackedUserOperation memory userOp,
        bytes32 merkleRoot,
        bytes32[] memory merkleProof
    ) {
        // Create base UserOperation (without signature)
        userOp = PackedUserOperation({
            sender: userWallet,
            nonce: nonce,
            initCode: "",
            callData: abi.encodeWithSelector(
                IERC4337Account.executeUserOp.selector,
                calls
            ),
            accountGasLimits: bytes32(uint256(2000000) << 128 | uint256(400000)),
            preVerificationGas: 21000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(10 gwei)),
            paymasterAndData: "",
            signature: ""
        });
        
        // Get userOp hash
        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(userOp);
        
        // Process chainless hash if needed
        uint256 nonceKey = nonce >> 64;
        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            userOpHash = SmartWallet(userWallet).getUserOpHashWithoutChainId(userOp);
        }
        
        // Add validUntil and IMPLEMENTATION to get the final hash (leaf1)
        bytes32 leaf1 = keccak256(
            abi.encode(
                userOpHash,
                uint48(0), // validUntil
                SmartWallet(userWallet).IMPLEMENTATION()
            )
        );
        
        // Create a random second leaf
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
    
    function _createAddOwnerCall(
        address userWallet,
        bytes32 newOwnerKeyHash,
        address validator
    ) private pure returns (Call[] memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: userWallet,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                validator,
                0  // default settings
            )
        });
        return calls;
    }
    
    function _getChainlessNonce(
        IEntryPoint entryPoint,
        address userWallet
    ) private view returns (uint256) {
        uint192 chainlessKey = uint192(Static.CHAIN_LESS_NONCE_KEY);
        uint256 sequentialNonce = entryPoint.getNonce(userWallet, chainlessKey);
        return (uint256(chainlessKey) << 64) | sequentialNonce;
    }
    
    
    function _executeWithPasskeyViaEntryPoint(
        IEntryPoint entryPoint,
        address payable userWallet,
        uint256 passkeyPrivateKey,
        uint256 pubX,
        uint256 pubY,
        address bundler
    ) private {
        // Create transfer call
        Call[] memory calls = _createTransferCall();
        
        // Get regular nonce (not chainless) for external calls
        uint256 nonce = entryPoint.getNonce(userWallet, 0);
        
        // Create UserOperation
        PackedUserOperation memory userOp = _createUserOperation(
            userWallet,
            nonce,
            calls,
            passkeyPrivateKey,
            pubX,
            pubY
        );
        
        console.log("Submitting UserOp to EntryPoint...");
        
        // Submit to EntryPoint
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        entryPoint.handleOps(ops, payable(bundler));
        
        console.log("Transaction executed successfully via EntryPoint with Passkey!");
    }
    
    function _createTransferCall() private pure returns (Call[] memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60),
            value: 0.00001 ether,
            data: ""
        });
        return calls;
    }
    
    function _createUserOperation(
        address payable userWallet,
        uint256 nonce,
        Call[] memory calls,
        uint256 passkeyPrivateKey,
        uint256 pubX,
        uint256 pubY
    ) private view returns (PackedUserOperation memory) {
        // Create the callData for executeUserOp
        bytes memory callData = abi.encodeWithSelector(
            IERC4337Account.executeUserOp.selector,
            calls
        );
        
        // Create PackedUserOperation
        PackedUserOperation memory userOp;
        userOp.sender = userWallet;
        userOp.nonce = nonce;
        userOp.initCode = ""; // Account already deployed
        userOp.callData = callData;
        
        // Pack gas limits (verificationGasLimit << 128 | callGasLimit)
        uint128 verificationGasLimit = 2000000;
        uint128 callGasLimit = 400000;
        userOp.accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit));
        
        userOp.preVerificationGas = 21000;
        
        // Pack gas fees (maxPriorityFeePerGas << 128 | maxFeePerGas)
        uint128 maxPriorityFeePerGas = 1 gwei;
        uint128 maxFeePerGas = 10 gwei;
        userOp.gasFees = bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas));
        
        userOp.paymasterAndData = ""; // No paymaster
        
        // Get the userOp hash
        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(userOp);
        
        // For chainless nonce, we need to get the chainless hash
        uint256 nonceKey = userOp.nonce >> 64;
        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // Get the chainless hash (without chainId) to match what validateUserOp expects
            userOpHash = SmartWallet(userWallet).getUserOpHashWithoutChainId(userOp);
            console.log("Using chainless mode for UserOp");
        }
        
        // Create the signature
        userOp.signature = _createPasskeySignature(
            userWallet,
            passkeyPrivateKey,
            pubX,
            pubY,
            userOpHash
        );
        
        return userOp;
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
        
        // Create the complete signature data
        return _packSignatureWithMerkle(
            signerKeyHash,
            validUntil,
            signerPubX,
            signerPubY,
            sig
        );
    }
    
    function _createPasskeySignature(
        address payable userWallet,
        uint256 signerPrivateKey,
        uint256 signerPubX,
        uint256 signerPubY,
        bytes32 userOpHash
    ) private view returns (bytes memory) {
        // Use validUntil = 0 for no expiration
        uint48 validUntil = 0;
        
        // Note: userOpHash already has chainless processing applied if needed (in _createUserOperation)
        // Now add validUntil and IMPLEMENTATION as per validateUserOp spec
        bytes32 hashWithValidUntil = keccak256(
            abi.encode(
                userOpHash,
                validUntil,
                SmartWallet(userWallet).IMPLEMENTATION()
            )
        );
        console.log("UserOp hash with validUntil and implementation:");
        console.logBytes32(hashWithValidUntil);
        
        // Generate Passkey signature
        (string memory clientDataJson, , bytes32 passkeyMessageHash) = 
            HelperLib.getPasskeyMessageHash(hashWithValidUntil);
        
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
        
        // Encode the signature
        bytes memory sig = abi.encode(auth, new bytes32[](0));
        
        // Calculate keyHash for the signing Passkey
        bytes32 signerKeyHash = keccak256(abi.encodePacked(signerPubX, signerPubY));
        
        // Create the complete signature data using helper function
        return _packSignature(
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
    
    function _packSignature(
        bytes32 signerKeyHash,
        uint48 validUntil,
        uint256 pubX,
        uint256 pubY,
        bytes memory sig
    ) private pure returns (bytes memory) {
        // Create validatorData: PasskeyPubKey + sig (without validUntil)
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