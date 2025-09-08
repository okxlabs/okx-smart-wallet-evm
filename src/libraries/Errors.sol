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
    error NonAdminSelfCall();

    // ValidationLogic related
    error InvalidKeyHash(bytes32 keyHash);
    error InvalidValidatorImpl(address validatorImpl);
    error ValidatorAlreadyExists();
    error ValidatorNotFound();
    error ValidatorExpired(bytes32 keyHash);

    // ECDSAValidator related
    error InvalidSignature();

    // Simulation related
    error SimulateExecution(
        uint256 executionGas,
        uint256 intrinsicGas,
        uint256 totalGas
    );

    error DelegateAndRevert(bool success, bytes ret);

    error NotEntryPoint();

    error InvalidNonceKey(uint256 nonce);

    error InvalidCaller(address owner);
}
