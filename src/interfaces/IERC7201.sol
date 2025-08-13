// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IERC7201 {
    /// @notice Returns the namespace and version of the contract
    function namespaceAndVersion() external view returns (string memory);
    /// @notice Returns the current custom storage root of the contract
    function CUSTOM_STORAGE_ROOT() external view returns (bytes32);
}
