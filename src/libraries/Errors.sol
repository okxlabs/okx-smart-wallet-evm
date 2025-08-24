// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

library Errors {
    // Storage related
    error InvalidNonce(uint256 nonce);
    error ExpiryPassed(uint48 expiry);

    // Account related
    error NotFromSelf();
    error OwnerExpired();

    // Call related
    error CallFailed(uint256 index, uint256 originalLength, bytes returnData);
    error NonAdminSelfCall();

    // ValidationLogic related
    error InvalidKeyHash(bytes32 keyHash);
    error InvalidValidatorImpl(address validatorImpl);
    error ValidatorAlreadyExists();
    error ValidatorNotFound();

    // ECDSAValidator related
    error InvalidSignature();

    // Simulation related
    error SimulateExecution();

    error InvalidOwnersAndValidatorsLength();

    error NotEntryPoint();

    error InvalidNonceKey(uint256 nonce);

    error InvalidCaller(address owner);

}
