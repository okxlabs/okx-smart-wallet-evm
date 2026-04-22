// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {BatchedCall} from "../../src/Types.sol";

interface ISmartWalletSimulator {
    // ERRORS
    error SimulateExecution(
        uint256 executionGas,
        uint256 intrinsicGas,
        uint256 totalGas
    );

    /// @notice Simulate a sponsored transaction, measuring gas costs for validation and execution, then reverts with detailed metrics.
    /// @dev Always reverts with `Errors.SimulateExecution` containing execution gas, intrinsic gas (base + calldata), and total gas metrics.
    /// 1) If the simulation fails during validation or the sponsor call, those other errors bubble up directly instead.
    /// 2) "Successful simulation" means both validation and the sponsorship call passed.
    ///    Any failure in the user's batch calls reverts the simulation.
    /// @param batchedCall BatchedCall struct containing calls, nonce, and expiry
    /// @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external;
}
