// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";

interface ISmartWallet is IERC165 {
    /// @notice Initializes the wallet with initial owners during proxy deployment
    /// @dev Only callable once via initializer modifier, sets up initial owners with admin privileges
    /// @param initialOwners Array of initial owner configurations with keyHash and validator pairs
    function initialize(InitialOwner[] calldata initialOwners) external;

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Only callable by registered owners or the wallet itself
    /// @param calls Array of Call structs containing target, value, and calldata
    function execute(Call[] calldata calls) external;

    /// @notice Executes batched calls through a relayer with signature validation
    /// @dev Validates the signature and executes calls on behalf of the owner
    /// @param batchedCall Batched call data including calls and validator information
    /// @param validatorData Additional data for signature validation (signature and optional Merkle proofs)
    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external;

    /// @notice Validates a signature according to EIP-1271
    /// @dev Supports both EOA signatures (65 bytes) and validator-based signatures
    /// @param hash The hash of the message to validate
    /// @param signature The signature to validate (format depends on signer type)
    /// @return EIP-1271 magic value (0x1626ba7e) if valid, 0xffffffff otherwise
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);

    /// @notice Returns the implementation contract address for proxy pattern
    /// @dev Used to identify the logic contract in proxy deployments
    /// @return Address of the implementation contract
    function IMPLEMENTATION() external view returns (address);

    /// @notice Performs a delegatecall and always reverts with the result
    /// @dev Used for gas estimation and simulation without state changes
    /// @param target The contract to delegatecall to
    /// @param data The calldata to pass to the target
    function delegateAndRevert(address target, bytes calldata data) external;
}
