// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// Interface for EIP-2470 Singleton Factory
interface IDeployFactory {
    /// @notice Deploys `_initCode` using `_salt` for defining the deterministic address.
    /// @param _initCode Initialization code.
    /// @param _salt Arbitrary value to modify resulting address.
    /// @return createdContract Created contract address.
    function deploy(
        bytes memory _initCode,
        bytes32 _salt
    ) external returns (address payable createdContract);
}
