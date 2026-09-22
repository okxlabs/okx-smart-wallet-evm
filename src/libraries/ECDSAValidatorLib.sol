// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title ECDSAValidatorLib
/// @notice Library for ECDSA signature validation with Merkle proof support
/// @dev Provides static validation functions for ECDSA signatures
library ECDSAValidatorLib {
    using ECDSA for bytes32;

    uint256 constant ECDSA_SIGNATURE_LENGTH = 65;

    /// @notice Validates a signature by checking if the recovered signer's hash matches keyHash
    /// @dev Uses ECDSA recovery to verify the signature matches the message hash
    /// @param keyHash The hash of the expected public key/address
    /// @param messageHash The hash of the message being validated
    /// @param validatorData The ECDSA signature to verify
    /// @return bool True if recovered address hash matches keyHash
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) internal pure returns (bool) {
        if (validatorData.length < ECDSA_SIGNATURE_LENGTH) {
            return false;
        }

        if (validatorData.length > ECDSA_SIGNATURE_LENGTH) {
            bytes32[] memory proofs = abi.decode(
                validatorData[ECDSA_SIGNATURE_LENGTH:],
                (bytes32[])
            );
            messageHash = MerkleProof.processProof(proofs, messageHash);
        }

        // Recover signer and verify against keyHash
        (address recoveredSigner, , ) = messageHash.tryRecoverCalldata(validatorData[:ECDSA_SIGNATURE_LENGTH]);
        if (recoveredSigner == address(0)) {
            return false;
        }
        return keccak256(abi.encodePacked(recoveredSigner)) == keyHash;
    }
}
