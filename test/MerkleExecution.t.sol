// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Base} from "./Base.t.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {ValidateManager} from "src/ValidateManager.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";

contract MerkleExecutionTest is Base {
    // Test data for Merkle tree construction
    bytes32[] internal merkleLeaves;
    bytes32 internal merkleRoot;
    bytes32[] internal merkleProof;

    // Test addresses
    address internal charlie;
    uint256 internal charliePk;
    address internal eve;
    uint256 internal evePk;

    function setUp() public override {
        super.setUp();

        (charlie, charliePk) = makeAddrAndKey("charlie");
        (eve, evePk) = makeAddrAndKey("eve");

        // Alice already has a validator from initialization

        // Now setup Charlie as a validator
        _addValidator(_alice, charlie);

        // Setup Merkle tree for testing
        _setupMerkleTree();
    }

    function _getValidationTypedHash(
        address account,
        BatchedCall memory batchedCall
    ) internal view returns (bytes32) {
        return ERC712(account).hashTypedData(BatchedCallLib.hash(batchedCall));
    }

    function _setupMerkleTree() internal {
        // Create test BatchedCall data
        Call[] memory calls1 = constructCallsData();
        Call[] memory calls2 = constructCallsData();
        Call[] memory calls3 = constructCallsData();

        // Create BatchedCall structs
        BatchedCall memory batchedCall1 = _construct_batchedCall(
            calls1,
            _alice
        );
        BatchedCall memory batchedCall2 = _construct_batchedCall(
            calls2,
            _alice
        );
        BatchedCall memory batchedCall3 = _construct_batchedCall(
            calls3,
            _alice
        );

        // Create leaf hashes using getValidationTypedHash
        merkleLeaves = new bytes32[](3);
        merkleLeaves[0] = _getValidationTypedHash(_alice, batchedCall1);
        merkleLeaves[1] = _getValidationTypedHash(_alice, batchedCall2);
        merkleLeaves[2] = _getValidationTypedHash(_alice, batchedCall3);

        // For simplicity, let's use a single leaf tree for now
        // This will avoid the complexity of merkle tree construction
        merkleRoot = _computeMerkleRootOpenZeppelin(merkleLeaves);
        merkleProof = _generateMerkleProof(merkleLeaves, 0); // Empty proof for single leaf
    }

    function _generateMerkleProof(
        bytes32[] memory leaves,
        uint256 leafIndex
    ) internal pure returns (bytes32[] memory) {
        require(leafIndex < leaves.length, "Invalid leaf index");

        if (leaves.length == 1) return new bytes32[](0);

        bytes32[] memory proof = new bytes32[](0);
        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = leafIndex;

        while (currentLevel.length > 1) {
            if (currentIndex % 2 == 0) {
                // Even index, need right sibling
                if (currentIndex + 1 < currentLevel.length) {
                    bytes32[] memory newProof = new bytes32[](proof.length + 1);
                    for (uint256 i = 0; i < proof.length; i++) {
                        newProof[i] = proof[i];
                    }
                    newProof[proof.length] = currentLevel[currentIndex + 1];
                    proof = newProof;
                }
            } else {
                // Odd index, need left sibling
                bytes32[] memory newProof = new bytes32[](proof.length + 1);
                for (uint256 i = 0; i < proof.length; i++) {
                    newProof[i] = proof[i];
                }
                newProof[proof.length] = currentLevel[currentIndex - 1];
                proof = newProof;
            }

            // Move to next level
            bytes32[] memory nextLevel = new bytes32[](
                (currentLevel.length + 1) / 2
            );
            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    if (currentLevel[i] <= currentLevel[i + 1]) {
                        nextLevel[i / 2] = keccak256(
                            abi.encodePacked(
                                currentLevel[i],
                                currentLevel[i + 1]
                            )
                        );
                    } else {
                        nextLevel[i / 2] = keccak256(
                            abi.encodePacked(
                                currentLevel[i + 1],
                                currentLevel[i]
                            )
                        );
                    }
                } else {
                    nextLevel[i / 2] = currentLevel[i];
                }
            }

            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
        }

        return proof;
    }

    function _sortLeaves() internal {
        // Simple bubble sort for deterministic ordering
        for (uint256 i = 0; i < merkleLeaves.length - 1; i++) {
            for (uint256 j = 0; j < merkleLeaves.length - i - 1; j++) {
                if (merkleLeaves[j] > merkleLeaves[j + 1]) {
                    bytes32 temp = merkleLeaves[j];
                    merkleLeaves[j] = merkleLeaves[j + 1];
                    merkleLeaves[j + 1] = temp;
                }
            }
        }
    }

    function _computeMerkleRootOpenZeppelin(
        bytes32[] memory leaves
    ) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];

        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[](
                (currentLevel.length + 1) / 2
            );

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    // OpenZeppelin uses sorted order for consistent hashing
                    if (currentLevel[i] <= currentLevel[i + 1]) {
                        nextLevel[i / 2] = keccak256(
                            abi.encodePacked(
                                currentLevel[i],
                                currentLevel[i + 1]
                            )
                        );
                    } else {
                        nextLevel[i / 2] = keccak256(
                            abi.encodePacked(
                                currentLevel[i + 1],
                                currentLevel[i]
                            )
                        );
                    }
                } else {
                    nextLevel[i / 2] = currentLevel[i];
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    function _construct_batchedCall(
        Call[] memory calls,
        address account
    ) internal view returns (BatchedCall memory) {
        return
            BatchedCall({
                calls: calls,
                nonce: _getNonce(account),
                expiry: uint48(block.timestamp + 1 hours)
            });
    }

    function _construct_simple_validator_data(
        address signer,
        uint256 privateKey,
        bytes32 messageHash
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = constructSignature(privateKey, messageHash);

        // For simple ECDSA validation: keyHash + signature (65 bytes)
        // ECDSAValidator will see validatorData.length <= 65 and do simple validation
        return abi.encodePacked(keyHash, signature);
    }

    function _construct_merkle_validator_data(
        address signer,
        uint256 privateKey,
        bytes32 hashToSign,
        bytes32[] memory proofs
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        bytes memory signature = constructSignature(privateKey, hashToSign);

        return abi.encodePacked(keyHash, signature, abi.encode(proofs));
    }

    // ============ POSITIVE TEST CASES ============

    function test_executeWithMerkle_succeeds_with_valid_proof() public {
        // Create a valid BatchedCall that matches our first leaf
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        // Use merkle validation with proofs
        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        // Execute with merkle validation
        vm.prank(_bob); // Bob is the relayer
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify execution succeeded
        assertEq(address(_bob).balance, 1 ether);
    }

    // ============ SECURITY TEST CASES ============

    function test_executeWithMerkle_reverts_with_invalid_proof() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            evePk, // Use Eve's private key to create invalid signature
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithMerkle_reverts_with_wrong_root() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        // Use wrong message hash for signature
        bytes32 wrongMerkleRoot = bytes32(uint256(0x1234));
        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            charliePk,
            wrongMerkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithMerkle_reverts_with_invalid_validator() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        bytes memory validatorData = _construct_merkle_validator_data(
            eve,
            evePk,
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidKeyHash.selector,
                keccak256(abi.encodePacked(eve))
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithMerkle_reverts_with_invalid_nonce() public {
        Call[] memory calls = constructCallsData();

        // Create BatchedCall with wrong nonce
        uint192 nonceKey = uint192(0);
        uint64 wrongNonce = uint64(_getNonce(_alice)) + 1; // Wrong nonce
        uint256 nonce = (uint256(nonceKey) << 64) | uint256(wrongNonce);

        BatchedCall memory invalidNonceBatchedCall = BatchedCall({
            calls: calls,
            nonce: nonce,
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidNonce.selector, nonce)
        );
        ISmartWallet(_alice).executeWithRelayer(
            invalidNonceBatchedCall,
            validatorData
        );
    }

    function test_executeWithMerkle_reverts_with_replay_attack() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        // First execution should succeed
        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Second execution with same nonce should fail
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonce.selector,
                batchedCall.nonce
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithMerkle_reverts_with_manipulated_batchedCall()
        public
    {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        // Create manipulated BatchedCall with different calls
        Call[] memory manipulatedCalls = new Call[](1);
        manipulatedCalls[0] = Call({target: eve, value: 2 ether, data: ""}); // Different target and value

        BatchedCall memory manipulatedBatchedCall = BatchedCall({
            calls: manipulatedCalls,
            nonce: batchedCall.nonce,
            expiry: batchedCall.expiry
        });

        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
            manipulatedBatchedCall,
            validatorData
        );
    }

    function test_executeWithMerkle_reverts_with_insufficient_signature_length()
        public
    {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        // Create signature that's too short (missing signature part)
        bytes memory shortValidatorData = abi.encodePacked(
            keccak256(abi.encodePacked(charlie)),
            uint256(0)
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
            batchedCall,
            shortValidatorData
        );
    }

    // ============ EDGE CASES ============

    function test_executeWithMerkle_handles_large_proof_arrays() public {
        // Create a larger Merkle tree for testing
        uint256 numLeaves = 16;
        bytes32[] memory largeLeaves = new bytes32[](numLeaves);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _construct_batchedCall(calls, _alice);

        for (uint256 i = 0; i < numLeaves; i++) {
            largeLeaves[i] = _getValidationTypedHash(_alice, batchedCall);
        }

        bytes32 largeMerkleRoot = _computeMerkleRootOpenZeppelin(largeLeaves);
        bytes32[] memory largeMerkleProof = _generateMerkleProof(
            largeLeaves,
            0
        );

        bytes memory validatorData = _construct_merkle_validator_data(
            charlie,
            charliePk,
            largeMerkleRoot,
            largeMerkleProof
        );

        vm.prank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _bob, 0);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        assertEq(address(_bob).balance, 1 ether);
    }
}
