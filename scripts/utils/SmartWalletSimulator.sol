// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {SmartWallet} from "../../src/SmartWallet.sol";
import {BatchedCall} from "../../src/Types.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Static} from "../../src/libraries/Static.sol";
import {ChainlessLib} from "../../src/libraries/ChainlessLib.sol";
import {ERC712} from "../../src/ERC712.sol";
import {ISmartWalletSimulator} from "../../src/interfaces/ISmartWalletSimulator.sol";
import {BatchedCallLib} from "../../src/libraries/BatchedCallLib.sol";

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
    /// @param validator Validator address intended to be used for validation during execution
    /// @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        address validator,
        bytes calldata validatorData
    ) external {
        // Start measuring execution gas (everything except intrinsic gas)
        uint256 executionGasStart = gasleft();
        
        // Extract validation components from new format
        // Format: pubkeyHash (32) + validUntil (6) + signatures
        bytes32 pubKeyHash = bytes32(validatorData[:32]);
        uint48 validUntil = uint48(bytes6(validatorData[32:38]));

        // Check transaction expiry
        if (_isExpired(validUntil)) {
            // revert Errors.ExpiryPassed(validUntil);
        }

        // Validate and update nonce
        if (!validateAndUpdateNonce(batchedCall.nonce)) {
            // revert Errors.InvalidNonce(batchedCall.nonce);
        }

        uint256 nonceKey = batchedCall.nonce >> 64;
        bytes32 dataHash = batchedCall.hash(validUntil, IMPLEMENTATION);

        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // Validate all calls are allowed to skip chain ID validation
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                // revert Errors.InvalidNonceKey(nonceKey);
            }
            dataHash = hashTypedDataSansChainId(dataHash);
        } else {
            dataHash = hashTypedData(dataHash);
        }

        // Validate validator
        address mockValidator = getVerifiedValidator(pubKeyHash);
        // Use mockValidator to avoid unused variable warning since it is only used for gas measurement
        mockValidator;

        if (validator == address(0)) {
            // revert Errors.InvalidKeyHash(pubKeyHash);
        }

        // Validate signature
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
        revert Errors.SimulateExecution(executionGas, intrinsicGas, totalGas);
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
            for {} lt(ptr, end) {
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
