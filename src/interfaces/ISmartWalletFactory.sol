// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;
import {InitialOwner} from "../Types.sol";

interface ISmartWalletFactory {
    /// @notice event when account is created
    event AccountCreated(
        address indexed acount,
        address indexed implementation,
        InitialOwner[] initialOwners,
        uint256 salt
    );

    /// @notice create smart account with owners and validators
    /// @param implementation: implementation address
    /// @param initialOwners: initial owners
    /// @param salt: salt
    function createAccount(
        address implementation,
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external payable returns (address acount);

    /// @notice predict deterministic address
    /// @param implementation: implementation address
    /// @param initialOwners: initial owners
    /// @param salt: salt
    function getAddress(
        address implementation,
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address);
}
