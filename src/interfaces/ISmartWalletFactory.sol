// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {InitialOwner} from "../Types.sol";

interface ISmartWalletFactory {
    /// @notice event when account is created
    event AccountCreated(
        address indexed account,
        address indexed implementation,
        InitialOwner[] initialOwners,
        uint256 salt
    );

    /// @notice create smart account with owners and validators
    /// @param initialOwners: initial owners
    /// @param salt: salt
    function createAccount(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external payable returns (address account);

    /// @notice predict deterministic address
    /// @param initialOwners: initial owners
    /// @param salt: salt
    function getAddress(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address);
}
