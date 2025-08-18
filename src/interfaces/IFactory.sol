// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IFactory {

    /// @notice event when account is created
    event AccountCreated(address indexed acount, address indexed implementation, bytes32[] owners, address[] validators, uint256 salt);

    /// @notice create smart account with owners and validators
    /// @param implementation: implementation address
    /// @param owners: user's owner, eoa, passkey
    /// @param validators: contract address, can verify signatrue
    /// @param salt: salt
    function createAccount(
        address implementation,
        bytes32[] calldata owners,
        address[] calldata validators,
        uint256 salt
    ) external payable returns(address acount);

    /// @notice predict deterministic address
    /// @param implementation: implementation address
    /// @param owners: user's owner, eoa, passkey
    /// @param validators: contract address, can verify signatrue
    /// @param salt: salt
    function getAddress(
        address implementation,
        bytes32[] calldata owners,
        address[] calldata validators,
        uint256 salt
    ) external view returns(address);
}   