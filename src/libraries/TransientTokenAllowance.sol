// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Library for managing transient ERC20 token allowances
/// @dev Uses transient storage for temporary token approvals that clear after transaction
library TransientTokenAllowance {
    /// @notice Calculates storage slot for transient token allowance
    /// @param token The ERC20 token address
    /// @param spender The address approved to spend tokens
    /// @return hashSlot The computed storage slot
    function _computeSlot(
        address token,
        address spender
    ) internal pure returns (bytes32 hashSlot) {
        assembly ("memory-safe") {
            mstore(0, and(token, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(32, and(spender, 0xffffffffffffffffffffffffffffffffffffffff))
            hashSlot := keccak256(0, 64)
        }
    }

    /// @notice Returns the transient allowance for a given token and spender
    /// @param token The ERC20 token address
    /// @param spender The address approved to spend tokens
    /// @return allowance The current transient allowance
    function get(
        address token,
        address spender
    ) internal view returns (uint256 allowance) {
        bytes32 hashSlot = _computeSlot(token, spender);
        assembly ("memory-safe") {
            allowance := tload(hashSlot)
        }
    }

    /// @notice Sets the transient allowance for a given token and spender
    /// @param token The ERC20 token address
    /// @param spender The address approved to spend tokens
    /// @param allowance The allowance amount to set
    function set(address token, address spender, uint256 allowance) internal {
        bytes32 hashSlot = _computeSlot(token, spender);
        assembly ("memory-safe") {
            tstore(hashSlot, allowance)
        }
    }
}
