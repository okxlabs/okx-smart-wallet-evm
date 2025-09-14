// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {EIP712} from "solady/utils/EIP712.sol";

/// @title EIP712
abstract contract ERC712 is EIP712 {
    /// @notice Computes the EIP-712 typed data hash with chain ID
    /// @dev Wraps Solady's internal _hashTypedData to provide public access
    /// @param structHash Hash of the structured data to be signed
    /// @return digest EIP-712 compliant hash including domain separator with chain ID
    function hashTypedData(
        bytes32 structHash
    ) public view returns (bytes32 digest) {
        return _hashTypedData(structHash);
    }

    /// @notice Computes the EIP-712 typed data hash without chain ID for cross-chain compatibility
    /// @dev Wraps Solady's internal _hashTypedDataSansChainId for chainless operation mode
    /// @param structHash Hash of the structured data to be signed
    /// @return digest EIP-712 compliant hash excluding chain ID from domain separator
    function hashTypedDataSansChainId(
        bytes32 structHash
    ) public view returns (bytes32 digest) {
        return _hashTypedDataSansChainId(structHash);
    }

    /// Note: If the returned result may change after the contract has been deployed,
    /// you must override `_domainNameAndVersionMayChange()` to return true.
    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        return ("SmartWallet", "1.0.0");
    }

    /// @dev Returns if `_domainNameAndVersion()` may change
    /// after the contract has been deployed (i.e. after the constructor).
    /// Default: false.
    function _domainNameAndVersionMayChange()
        internal
        pure
        override
        returns (bool result)
    {
        return true;
    }
}
