// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IValidator {
    /// @notice Validates a signature for a specific key hash and message
    /// @dev Implementation varies by validator type (ECDSA, PASSKEY, etc.)
    /// @param keyHash The hash of the signer's public key or identifier
    /// @param messageHash The hash of the message being validated
    /// @param validatorData Validator-specific data containing signature and optional parameters
    /// @return True if the signature is valid, false otherwise
    function validateSignature(
        bytes32 keyHash,
        bytes32 messageHash,
        bytes calldata validatorData
    ) external view returns (bool);
}
