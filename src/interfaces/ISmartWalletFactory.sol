// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {InitialOwner} from "../../src/Types.sol";

interface ISmartWalletFactory {
    /// @notice Event when account is created
    event AccountCreated(
        address indexed account,
        address indexed implementation,
        InitialOwner[] initialOwners,
        uint256 salt
    );

    /// @notice Creates a smart account with owners and validators
    /// @dev Deploys a new proxy pointing to the implementation contract and initializes it with owners
    /// @param initialOwners Array of initial owner configurations with keyHash and validator pairs
    /// @param salt Salt value for deterministic address generation using CREATE2
    /// @return account The address of the newly created or existing smart account
    function createAccount(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external payable returns (address account);

    /// @notice Predicts the deterministic address for a smart account
    /// @dev Calculates the address where the account would be deployed without actually deploying
    /// @param initialOwners Array of initial owner configurations
    /// @param salt Salt value for deterministic address calculation
    /// @return The predicted address of the smart account
    function getAddress(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address);
}
