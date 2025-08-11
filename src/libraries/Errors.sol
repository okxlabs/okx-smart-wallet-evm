// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

library Errors {
    // Storage related
    error InvalidExecutor();
    error InvalidSession();
    error InvalidSessionId();
    error InvalidOwner();

    // Account related
    error NotFromSelf();

    // Call related
    error CallFailed(uint256 index, uint256 originalLength, bytes returnData);

    // ValidationLogic related
    error InvalidValidator(address validator);
    error InvalidValidatorImpl(address validatorImpl);
    error InvalidValidatorData();
    error ValidatorAlreadyExists();
    error NotEnoughGas();

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
    error NoncompliantValidator();
}
