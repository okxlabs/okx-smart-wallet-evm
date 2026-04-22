// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SmartWallet} from "src/SmartWallet.sol";
import {BatchedCall} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {ChainlessLib} from "src/libraries/ChainlessLib.sol";
import {ISmartWalletSimulator} from "./ISmartWalletSimulator.s.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {DecodeLib} from "src/libraries/DecodeLib.sol";
import {CalculateCallDataGas} from "./CalculateCallDataGas.sol";


/// @title SmartWalletSimulator
/// @notice A simulation contract that inherits from SmartWallet and implements simulation functionality
/// @dev This contract is used for dry-run testing of SmartWallet operations
///      It allows relayers to simulate transactions without actually executing them
contract SmartWalletSimulator is SmartWallet, ISmartWalletSimulator layout at 0x653ff6dcbda533c3c7d8ffb646da3e510d0de40f237170c4da3f874472aecb00 {
    using BatchedCallLib for BatchedCall;

    // uint256 constant COLD_SLOAD         = 2100;  // ERC1967 read implementation slot 
    // uint256 constant COLD_DELEGATECALL  = 2600;  // cold address DELEGATECALL
    // uint256 constant PROXY_ASSEMBLY     = 200;   // proxy fallback 
    // uint256 constant DISPATCH_OVERHEAD  = 300;   // executeWithRelayer function dispatch
    uint256 constant PROXY_OVERHEAD = 5200;
    uint256 constant EXTERNAL_CALL = 2600;          // validator is external call
    uint256 constant ADJUST = 5000;                 // adjust final result

    /// @notice Simulates SmartWallet's executeWithRelayer, measuring gas costs for validation and execution, then reverts with detailed metrics.
    /// @dev Always reverts with `ISmartWalletSimulator.SimulateExecution` containing execution gas, intrinsic gas, and total gas metrics.
    /// 1) Validation steps run to account for gas costs but reverts are skipped to allow simulation without valid signatures (better simulation UX).
    /// 2) If any user batch call reverts during execution, the entire simulation will revert with that error.
    /// 3) "Successful simulation" means all batch calls executed without reverting.
    /// @param batchedCall BatchedCall struct containing calls, nonce, and expiry
    /// @param validatorData Encoded data containing keyHash and signature: abi.encodePacked(keyHash, signature)
    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external {
        // Start measuring execution gas (everything except intrinsic gas)
        uint256 executionGasStart = gasleft();

        // Validate and extract relayer data using the simulation function with custom validator
        (
            bytes32 pubKeyHash,
            bytes32 dataHash,
            uint256 verficationGas
        ) = _validateAndExtractRelayerData1(
                batchedCall,
                validatorData
            );

        // Execute the batch calls - any errors will bubble up and be caught by the caller
        _batchCall(batchedCall.calls, pubKeyHash);

        // // If we reach here, the call succeeded
        // // Emit success event with the intent hash that the user signed
        emit RelayerExecuteSuccessEvent(
            dataHash, // This is the intentHash - the hash of the user's execution intent
            msg.sender,
            batchedCall.nonce
        );

        // Calculate execution gas (everything except intrinsic gas)
        uint256 executionGas = executionGasStart - gasleft() + verficationGas + PROXY_OVERHEAD - EXTERNAL_CALL - ADJUST;

        // Calculate calldata intrinsic gas for executeWithRelayer call
        uint256 calldataIntrinsicGas = CalculateCallDataGas.intrinsicGas(
            abi.encodeWithSelector(
                this.executeWithRelayer.selector,
                batchedCall,
                validatorData
            )
        );

        // Calculate total intrinsic gas (base + calldata)
        uint256 intrinsicGas = 21000 + calldataIntrinsicGas;

        // Calculate total gas (execution gas + intrinsic gas)
        uint256 totalGas = executionGas + intrinsicGas;

        // Revert with gas metrics
        revert ISmartWalletSimulator.SimulateExecution(
            executionGas,
            intrinsicGas,
            totalGas
        );
    }

    /// @notice Validates and extracts data for relayer execution
    /// @dev Comprehensive validation function for executeWithRelayer
    /// @param batchedCall The batched call data
    /// @param validatorData The validator data containing pubKeyHash, validUntil, and signature
    /// @return pubKeyHash The extracted public key hash
    /// @return dataHash The computed data hash for event emission
    function _validateAndExtractRelayerData1(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) internal returns (bytes32 pubKeyHash, bytes32 dataHash, uint256 verficationGas) {
        // Step 1: Validate and consume nonce
        if (!validateAndUpdateNonce(batchedCall.nonce))
            revert InvalidNonce(batchedCall.nonce);

        // Minimum length check: 32 bytes (pubKeyHash) + 6 bytes (validUntil) = 38 bytes
        if (validatorData.length < 38) {
            revert InvalidValidatorDataLength(
                validatorData.length,
                38
            );
        }
        // Step 2: Extract validation components from validatorData
        uint48 validUntil;
        (pubKeyHash, validUntil) = DecodeLib.decodeSignatureComponents(
            validatorData
        );

        // Step 3: Verify transaction hasn't expired
        if (_isExpired(validUntil))
            revert ExpiryPassed(validUntil);

        // Step 4: Verify validator exists and is not expired
        address validator = getVerifiedValidator(pubKeyHash);
        if (validator == address(0))
            revert InvalidKeyHash(pubKeyHash);

        if(validator == Static.ECDSA_VALIDATOR_ADDRESS) {
            validator = 0x57313F56B9c8c400efE42d4f4A811a8404BDE273;
            verficationGas = 3000;
        } else {
            validator = 0x91f9f193C858e6e67C56F259261c3c2045cAa115;
            verficationGas = 7700;
        }
       
        // Step 5: Compute the data hash based on nonce type
        uint256 nonceKey = batchedCall.nonce >> 64;
        bytes32 intentHash = batchedCall.hash(validUntil, IMPLEMENTATION);

        // Step 6: Handle chainless execution if applicable
        if (nonceKey == Static.CHAINLESS_NONCE_KEY) {
            // Validate all calls are allowed for chainless execution
            if (
                !ChainlessLib.validateChainlessNonceCallData(
                    batchedCall.calls,
                    address(this)
                )
            ) {
                revert InvalidNonceKey(nonceKey);
            }
            // Hash without chain ID for cross-chain compatibility
            dataHash = hashTypedDataSansChainId(intentHash);
        } else {
            // Standard hash with chain ID
            dataHash = hashTypedData(intentHash);
        }

        /// Step 7: Validate the signature
        if (
            !_validateSignature(
                validator,
                pubKeyHash,
                dataHash,
                validatorData[38:]
            )
        ) revert InvalidSignature();
    }
}

