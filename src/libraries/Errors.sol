// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

library Errors {
    // Storage related
    error InvalidNonce(uint192 key, uint64 expected, uint64 actual);
    error ExpiryPassed(uint256 expiry);

    // Account related
    error NotFromSelf();

    // Call related
    error CallFailed(uint256 index, uint256 originalLength, bytes returnData);
    error NonAdminSelfCall();

    // ValidationLogic related
    error InvalidValidator(address validator);
    error InvalidValidatorImpl(address validatorImpl);
    error ValidatorAlreadyExists();
    error InvalidMerkleProof();

    // ECDSAValidator related
    error InvalidSignature();

    // WalletCore related
    error NameTooLong();
    error VersionTooLong();

    // Simulation related
    error GasEstimates(uint256 executionGas, bytes errorData);
    error SimulateExecution(
        uint256 executionGas,
        uint256 totalGas,
        bytes errorData
    );
}
