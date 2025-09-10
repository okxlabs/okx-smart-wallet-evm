// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {LibClone} from "solady/utils/LibClone.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ISmartWalletFactory, InitialOwner} from "../script/utils/ISmartWalletFactory.sol";
import {BatchedCall} from "./Types.sol";

contract SmartWalletFactory is ISmartWalletFactory {
    address public immutable IMPLEMENTATION;

    /// @notice Constructor to set the implementation address
    /// @param _implementation Implementation contract address for proxy deployments
    constructor(address _implementation) {
        IMPLEMENTATION = _implementation;
    }

    /// @notice Creates a smart account with owners and validators
    /// @param initialOwners Initial owners configuration
    /// @param salt Salt for deterministic address generation
    function createAccount(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) public payable returns (address account) {
        (bool alreadyDeployed, address instance) = LibClone
            .createDeterministicERC1967(
                msg.value,
                IMPLEMENTATION,
                _getSalt(initialOwners, salt)
            );

        if (!alreadyDeployed) {
            ISmartWallet(instance).initialize(initialOwners);
        }

        emit AccountCreated(instance, IMPLEMENTATION, initialOwners, salt);
        account = instance;
    }

    /// @notice Creates a smart account and executes a call in the same transaction
    /// @param initialOwners Initial owners configuration
    /// @param salt Salt for deterministic address generation
    /// @param batchedCall Batched call to execute after deployment
    /// @param validatorData Validator data for call execution
    function createAccountWithCall(
        InitialOwner[] calldata initialOwners,
        uint256 salt,
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external payable returns (address account) {
        account = createAccount(initialOwners, salt);
        ISmartWallet(account).executeWithRelayer(batchedCall, validatorData);
    }

    /// @notice Predicts the deterministic address for a smart account
    /// @param initialOwners Initial owners configuration
    /// @param salt Salt for deterministic address generation
    function getAddress(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address) {
        return
            LibClone.predictDeterministicAddressERC1967(
                IMPLEMENTATION,
                _getSalt(initialOwners, salt),
                address(this)
            );
    }

    /// @notice Generates a deterministic salt for CREATE2 deployment
    /// @dev Combines initial owners configuration with user-provided salt to ensure unique addresses
    /// @param initialOwners Array of initial owner configurations (keyHash and validator pairs)
    /// @param salt User-provided salt for additional entropy
    /// @return Keccak256 hash used as CREATE2 salt for deterministic address generation
    function _getSalt(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(initialOwners, salt));
    }
}
