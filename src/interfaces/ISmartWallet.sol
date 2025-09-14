// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Call, BatchedCall, InitialOwner} from "../Types.sol";

interface ISmartWallet is IERC165 {
    // ERRORS
    error InvalidCaller(address owner);
    error OwnerExpired();
    error NonAdminSelfCall();
    error InvalidNonce(uint256 nonce);
    error ExpiryPassed(uint48 expiry);
    error InvalidKeyHash(bytes32 keyHash);
    error InvalidNonceKey(uint256 nonce);
    error InvalidSignature();
    error InvalidValidatorDataLength(uint256 actual, uint256 required);
    error DelegateAndRevert(bool success, bytes ret);
    error UnauthorizedInitialization();

    // EVENTS
    event WalletInitialized();
    event ExecuteSuccessEvent(
        bytes32 indexed intentHash,
        address sender,
        uint256 nonce
    );

    /// @notice Initializes the wallet with initial owners during proxy deployment
    /// @dev Only callable once via initializer modifier, sets up initial owners with admin privileges
    /// @param initialOwners Array of initial owner configurations with keyHash and validator pairs
    function initialize(InitialOwner[] calldata initialOwners) external;

    /// @notice Executes multiple contract calls in a single transaction
    /// @dev Only callable by registered owners or the wallet itself. Batches multiple calls for gas efficiency.
    /// @param calls Array of Call structs containing target address, value, and calldata
    function execute(Call[] calldata calls) external;

    /// @notice Executes batched calls through a relayer with signature validation
    /// @dev Validates signature and nonce before executing calls. Supports chainless execution for specific operations.
    /// @param batchedCall BatchedCall struct containing calls and nonce
    /// @param validatorData Encoded validation data: pubKeyHash (32) + validUntil (6) + signature
    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external;

    /// @notice Validates a signature according to EIP-1271 standard
    /// @dev Supports both EOA signatures (65 bytes) and validator-based signatures. Returns magic value 0x1626ba7e if valid, 0xffffffff if invalid
    /// @param hash Hash of the data to be validated
    /// @param signature Signature to validate (65 bytes for EOA, or encoded with keyHash for validator)
    /// @return EIP-1271 magic value (0x1626ba7e) if valid, 0xffffffff otherwise
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);

    /// @notice Returns the implementation contract address for proxy pattern
    /// @dev Used to identify the logic contract in proxy deployments, immutable value set at deployment
    /// @return Address of the implementation contract
    function IMPLEMENTATION() external view returns (address);

    /// @notice Performs a delegatecall and always reverts with the result
    /// @dev Used for gas estimation and simulation without state changes. Always reverts with DelegateAndRevert error containing execution result.
    /// @param target The contract to delegatecall to
    /// @param data The calldata to pass to the target
    function delegateAndRevert(address target, bytes calldata data) external;
}
