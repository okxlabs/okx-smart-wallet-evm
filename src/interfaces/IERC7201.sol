// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IERC7201 {
    /// @notice Returns the namespace of the contract
    function namespace() external view returns (string memory);

    /// @notice Returns the current custom storage root of the contract
    function CUSTOM_STORAGE_ROOT() external view returns (bytes32);
}
