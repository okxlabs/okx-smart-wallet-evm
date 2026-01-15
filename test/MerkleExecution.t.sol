// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";

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
        bytes32 charlieKeyHash = keccak256(abi.encodePacked(charlie));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            charlieKeyHash,
            address(_ecdsaValidator),
            0
        );

        // Setup Merkle tree for testing
        _setupMerkleTree();
    }

    function _getValidationTypedHash(
        address account,
        BatchedCall memory batchedCall
    ) internal view returns (bytes32) {
        return
            _getExecuteWithRelayerHash(
                batchedCall,
                0, // validUntil = 0 (no expiry)
                account
            );
    }

    function _setupMerkleTree() internal {
        // Create test BatchedCall data
        Call[] memory calls1 = constructCallsData();
        Call[] memory calls2 = constructCallsData();
        Call[] memory calls3 = constructCallsData();

        // Create BatchedCall structs
        BatchedCall memory batchedCall1 = _constructBatchedCall(
            calls1,
            _aliceWallet
        );
        BatchedCall memory batchedCall2 = _constructBatchedCall(
            calls2,
            _aliceWallet
        );
        BatchedCall memory batchedCall3 = _constructBatchedCall(
            calls3,
            _aliceWallet
        );

        // Create leaf hashes using getValidationTypedHash
        merkleLeaves = new bytes32[](3);
        merkleLeaves[0] = _getValidationTypedHash(_aliceWallet, batchedCall1);
        merkleLeaves[1] = _getValidationTypedHash(_aliceWallet, batchedCall2);
        merkleLeaves[2] = _getValidationTypedHash(_aliceWallet, batchedCall3);

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

    function _constructBatchedCall(
        Call[] memory calls,
        address account
    ) internal view returns (BatchedCall memory) {
        return BatchedCall({calls: calls, nonce: _getNonce(account)});
    }

    function _constructSimpleValidatorData(
        address signer,
        uint256 privateKey,
        bytes32 messageHash
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = _constructSignature(privateKey, messageHash);

        // For simple ECDSA validation: keyHash + validUntil + signature
        // ECDSAValidator will see validatorData.length <= 103 and do simple validation
        uint48 validUntil = 0; // 0 means no expiration
        return abi.encodePacked(keyHash, validUntil, signature);
    }

    function _constructMerkleValidatorData(
        address signer,
        uint256 privateKey,
        bytes32 hashToSign,
        bytes32[] memory proofs
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        bytes memory signature = _constructSignature(privateKey, hashToSign);

        return
            abi.encodePacked(
                keyHash,
                uint48(0), // validUntil (0 means no expiry)
                signature,
                abi.encode(proofs)
            );
    }

    // ============ POSITIVE TEST CASES ============

    function test_ExecuteWithMerkle_WithValidProof_Success() public {
        // Create a valid BatchedCall that matches our first leaf
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        // Use merkle validation with proofs
        // The signer signs the merkleRoot, not the individual transaction
        bytes memory validatorData = _constructMerkleValidatorData(
            charlie,
            charliePk,
            merkleRoot, // Sign the Merkle root
            merkleProof // Provide proof that this BatchedCall is in the tree
        );

        // Execute with merkle validation
        vm.startPrank(_bob); // Bob is the relayer
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        // Verify execution succeeded
        assertEq(address(_bob).balance, 1 ether);
    }

    // ============ SECURITY TEST CASES ============

    function test_RevertWhen_ExecuteWithMerkle_InvalidProof() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        bytes memory validatorData = _constructMerkleValidatorData(
            charlie,
            evePk, // Use Eve's private key to create invalid signature
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithMerkle_WrongRoot() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        // Use wrong message hash for signature
        bytes32 wrongMerkleRoot = bytes32(uint256(0x1234));
        bytes memory validatorData = _constructMerkleValidatorData(
            charlie,
            charliePk,
            wrongMerkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithMerkle_InvalidValidator() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        bytes memory validatorData = _constructMerkleValidatorData(
            eve,
            evePk,
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidKeyHash.selector,
                keccak256(abi.encodePacked(eve))
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithMerkle_InvalidNonce() public {
        Call[] memory calls = constructCallsData();

        // Create BatchedCall with wrong nonce
        uint192 nonceKey = uint192(0);
        uint64 wrongNonce = uint64(_getNonce(_aliceWallet)) + 1; // Wrong nonce
        uint256 nonce = (uint256(nonceKey) << 64) | uint256(wrongNonce);

        BatchedCall memory invalidNonceBatchedCall = BatchedCall({
            calls: calls,
            nonce: nonce
        });

        bytes memory validatorData = _constructMerkleValidatorData(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidNonce.selector, nonce)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            invalidNonceBatchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithMerkle_ReplayAttack() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        // Use Merkle validation for batch authorization
        bytes memory validatorData = _constructMerkleValidatorData(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        // First execution should succeed
        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        // Second execution with same nonce should fail (replay protection)
        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonce.selector,
                batchedCall.nonce
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithMerkle_ManipulatedBatchedCall() public {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        // Create manipulated BatchedCall with different calls
        Call[] memory manipulatedCalls = new Call[](1);
        manipulatedCalls[0] = Call({target: eve, value: 2 ether, data: ""}); // Different target and value

        BatchedCall memory manipulatedBatchedCall = BatchedCall({
            calls: manipulatedCalls,
            nonce: batchedCall.nonce
        });

        bytes memory validatorData = _constructMerkleValidatorData(
            charlie,
            charliePk,
            merkleRoot,
            merkleProof
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            manipulatedBatchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithMerkle_InsufficientSignatureLength()
        public
    {
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        // Create signature that's too short (missing signature part)
        bytes memory shortValidatorData = abi.encodePacked(
            keccak256(abi.encodePacked(charlie)), // pubKeyHash (32 bytes)
            uint48(0) // validUntil (6 bytes)
            // Missing actual signature part - total only 38 bytes
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            shortValidatorData
        );
    }

    // ============ EDGE CASES ============

    function test_ExecuteWithMerkle_HandlesLargeProofArrays_Success() public {
        // Create a simple valid BatchedCall for testing
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = _constructBatchedCall(
            calls,
            _aliceWallet
        );

        // Create a large Merkle proof array to test edge case
        bytes32[] memory largeProofs = new bytes32[](10);
        for (uint256 i = 0; i < 10; i++) {
            largeProofs[i] = keccak256(abi.encodePacked("proof", i));
        }

        // Use the helper function with Merkle proof support
        bytes memory validatorData = _constructValidatorDataWithMerkleProof(
            _aliceWallet,
            charlie,
            charliePk,
            batchedCall,
            uint48(0), // no expiry
            largeProofs
        );

        vm.startPrank(_bob);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(batchedCall, 0, _aliceWallet),
            _bob,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        vm.stopPrank();

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_cross_chain_merkle_execution_single_signature() public {
        uint256 bobInitBalance = address(_bob).balance;
        uint256 charlieInitBalance = address(charlie).balance;

        // Phase 1: Prepare Chain A Transaction
        address walletA = _aliceWallet;
        vm.deal(walletA, 10 ether);

        Call[] memory callsA = new Call[](1);
        callsA[0] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchA = BatchedCall({
            calls: callsA,
            nonce: _getNonce(walletA)
        });

        bytes32 leafA = _getExecuteWithRelayerHash(batchA, 0, walletA);

        // Phase 2: Switch to Chain B (reuse existing contracts)
        vm.chainId(42161);

        address walletB = _aliceWallet;
        vm.deal(walletB, 10 ether);

        // After Chain A execution, nonce will be 1
        uint256 nonceB = 1;

        Call[] memory callsB = new Call[](1);
        callsB[0] = Call({target: charlie, value: 2 ether, data: ""});

        BatchedCall memory batchB = BatchedCall({calls: callsB, nonce: nonceB});

        bytes32 leafB = _getExecuteWithRelayerHash(batchB, 0, walletB);

        // Phase 3: Create and Sign Merkle Root
        bytes32 root = _computeMerkleRoot(leafA, leafB);
        bytes memory sig = _constructSignature(_alicePk, root);

        // Phase 4: Execute on Chain A
        vm.chainId(31337);
        _executeWithMerkle(walletA, batchA, leafB, sig);
        assertEq(address(_bob).balance, bobInitBalance + 1 ether);

        // Phase 5: Execute on Chain B
        vm.chainId(42161);
        _executeWithMerkle(walletB, batchB, leafA, sig);
        assertEq(address(charlie).balance, charlieInitBalance + 2 ether);

        // Reset chain
        vm.chainId(31337);
    }

    // Helper to compute sorted Merkle root
    function _computeMerkleRoot(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32) {
        return
            a <= b
                ? keccak256(abi.encodePacked(a, b))
                : keccak256(abi.encodePacked(b, a));
    }

    // Helper to execute with Merkle proof
    function _executeWithMerkle(
        address wallet,
        BatchedCall memory batch,
        bytes32 proof,
        bytes memory sig
    ) private {
        bytes32[] memory proofs = new bytes32[](1);
        proofs[0] = proof;

        bytes memory validatorData = abi.encodePacked(
            keccak256(abi.encodePacked(_alice)),
            uint48(0),
            sig,
            abi.encode(proofs)
        );

        vm.prank(relayer);
        ISmartWallet(wallet).executeWithRelayer(batch, validatorData);
    }
}
