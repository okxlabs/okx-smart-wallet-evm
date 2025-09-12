// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SmartWallet} from "../../src/SmartWallet.sol";
import {BatchedCall} from "../../src/Types.sol";
import {Static} from "../../src/libraries/Static.sol";
import {ChainlessLib} from "../../src/libraries/ChainlessLib.sol";
import {ISmartWalletSimulator} from "./ISmartWalletSimulator.s.sol";
import {BatchedCallLib} from "../../src/libraries/BatchedCallLib.sol";
import {DecodeLib} from "../../src/libraries/DecodeLib.sol";

/// @title SmartWalletSimulator
/// @notice A simulation contract that inherits from SmartWallet and implements simulation functionality
/// @dev This contract is used for dry-run testing of SmartWallet operations
///      It allows relayers to simulate transactions without actually executing them
contract SmartWalletSimulator is SmartWallet, ISmartWalletSimulator {
    using BatchedCallLib for BatchedCall;

    /// @notice Simulate a sponsored transaction, measuring gas costs for validation and execution, then reverts with detailed metrics.
    /// @dev Always reverts with `Errors.SimulateExecutionWithGas` containing execution gas and total gas metrics.
    /// 1) If the simulation fails during validation or the sponsor call, those other errors bubble up directly instead.
    /// 2) "Successful simulation" means both validation and the sponsorship call passed.
    ///    Any failure in the user's batch calls is then captured in `errorData` and surfaced inside the `SimulateExecutionWithGas` revert.
    /// @param batchedCall BatchedCall struct containing calls, nonce, and expiry
    /// @param validator Validator address to use for gas estimation
    /// @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        address validator,
        bytes calldata validatorData
    ) external {
        // Start measuring execution gas (everything except intrinsic gas)
        uint256 executionGasStart = gasleft();

        // Validate and extract relayer data using the simulation function with custom validator
        (
            bytes32 pubKeyHash,
            bytes32 dataHash
        ) = _validateAndExtractRelayerDataForSimulation(
                batchedCall,
                validator,
                validatorData
            );

        // Execute the batch calls - any errors will bubble up and be caught by the caller
        _batchCall(batchedCall.calls, pubKeyHash);

        // If we reach here, the call succeeded
        // Emit success event with the intent hash that the user signed
        emit ExecuteSuccessEvent(
            dataHash, // This is the intentHash - the hash of the user's execution intent
            msg.sender,
            batchedCall.nonce
        );

        // Calculate execution gas (everything except intrinsic gas)
        uint256 executionGas = executionGasStart - gasleft();

        // Calculate calldata intrinsic gas for executeWithRelayer call
        uint256 calldataIntrinsicGas = _intrinsicGas(
            abi.encodeWithSelector(
                this.executeWithRelayer.selector,
                batchedCall,
                validatorData
            )
        );

        // Calculate total intrinsic gas (base + calldata)
        uint256 intrinsicGas = 21000 + calldataIntrinsicGas; // Base intrinsic gas + calldata intrinsic gas

        // Calculate total gas (execution gas + intrinsic gas)
        uint256 totalGas = executionGas + intrinsicGas;

        // Revert with gas metrics
        revert ISmartWalletSimulator.SimulateExecution(executionGas, intrinsicGas, totalGas);
    }

    /// @notice Validate and extract relayer data for simulation with custom validator
    /// @dev All reverts are commented out to allow simulation to continue
    /// @param batchedCall The batched call data
    /// @param validator Custom validator address for simulation
    /// @param validatorData The validator data containing pubKeyHash, validUntil, and signature
    /// @return pubKeyHash The extracted public key hash
    /// @return dataHash The computed data hash for event emission
    function _validateAndExtractRelayerDataForSimulation(
        BatchedCall calldata batchedCall,
        address validator,
        bytes calldata validatorData
    ) internal returns (bytes32 pubKeyHash, bytes32 dataHash) {
        // Step 1: Validate and consume nonce
        if (!validateAndUpdateNonce(batchedCall.nonce)) {
            // revert Errors.InvalidNonce(batchedCall.nonce);
        }

        // Step 2: Extract validation components from validatorData
        uint48 validUntil;
        (pubKeyHash, validUntil) = DecodeLib.decodeSignatureComponents(
            validatorData
        );

        // Step 3: Verify transaction hasn't expired
        if (_isExpired(validUntil)) {
            // revert Errors.ExpiryPassed(validUntil);
        }

        // Step 4: Verify validator exists and is not expired
        address actualValidator = ownerValidators[pubKeyHash];
        if (actualValidator == address(0)) {
            // revert Errors.InvalidKeyHash(pubKeyHash);
        }

        uint256 settings = ownerSettings[pubKeyHash];
        if (settings != 0 && isSettingsExpired(settings)) {
            // revert Errors.ValidatorExpired(pubKeyHash);
        }

        // Step 5: Compute the data hash based on nonce type
        uint256 nonceKey = batchedCall.nonce >> 64;
        bytes32 intentHash = batchedCall.hash(validUntil, IMPLEMENTATION);

        // Step 6: Handle chainless execution if applicable
        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // Validate all calls are allowed for chainless execution
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                // revert Errors.InvalidNonceKey(nonceKey);
            }
            // Hash without chain ID for cross-chain compatibility
            dataHash = hashTypedDataSansChainId(intentHash);
        } else {
            // Standard hash with chain ID
            dataHash = hashTypedData(intentHash);
        }

        // Step 7: Validate the signature (use passed validator parameter for gas estimation)
        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                dataHash,
                validatorData[38:]
            )
        ) {
            // revert Errors.InvalidSignature();
        }
    }

    /// @notice Compute intrinsic calldata-expansion gas: 16 per non-zero byte, 4 per zero byte
    /// @param data The memory blob you want to cost
    /// @return gasCost The total intrinsic gas for that calldata
    function _intrinsicGas(
        bytes memory data
    ) internal pure returns (uint256 gasCost) {
        uint256 len = data.length;
        uint256 zeroCount;
        assembly {
            // pointer to first byte of `data` in memory
            let ptr := add(data, 0x20)
            let end := add(ptr, len)
            let word

            // scan 32 bytes at a time
            for {

            } lt(ptr, end) {
                ptr := add(ptr, 0x20)
            } {
                word := mload(ptr)
                // count zeros in this 32-byte word
                for {
                    let j := 0
                } lt(j, 0x20) {
                    j := add(j, 0x01)
                } {
                    zeroCount := add(zeroCount, iszero(byte(j, word)))
                }
            }

            // adjust for any overshoot past the end
            let overshoot := sub(ptr, end)
            if gt(overshoot, 0) {
                // subtract erroneous zero counts beyond `len`
                for {
                    let i := 0
                } lt(i, overshoot) {
                    i := add(i, 0x01)
                } {
                    let b := byte(sub(0x1f, i), word)
                    zeroCount := sub(zeroCount, iszero(b))
                }
            }
        }

        // every byte costs 16; zero bytes save 12
        gasCost = len * 16 - zeroCount * 12;
    }
}
