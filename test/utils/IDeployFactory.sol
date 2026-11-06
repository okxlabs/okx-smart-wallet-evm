// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice EIP-2470 Singleton Factory interface used by the test deployment helpers.
interface IDeployFactory {
    /// @notice Deploys `initCode` at the CREATE2 address determined by `salt`.
    function deploy(
        bytes memory initCode,
        bytes32 salt
    ) external returns (address payable createdContract);
}
