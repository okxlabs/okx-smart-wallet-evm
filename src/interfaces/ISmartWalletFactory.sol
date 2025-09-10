// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {InitialOwner} from "../Types.sol";

interface ISmartWalletFactory {
    /// @notice Event emitted when an account is created
    event AccountCreated(
        address indexed account,
        address indexed implementation,
        InitialOwner[] initialOwners,
        uint256 salt
    );

    /// @notice Creates a smart account with owners and validators
    /// @param initialOwners Initial owners configuration
    /// @param salt Salt for deterministic address generation
    function createAccount(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external payable returns (address account);

    /// @notice Predicts the deterministic address for a smart account
    /// @param initialOwners Initial owners configuration
    /// @param salt Salt for deterministic address generation
    function getAddress(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address);
}
