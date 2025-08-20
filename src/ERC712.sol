// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP712} from "solady/utils/EIP712.sol";

/// @title EIP712
contract ERC712 is EIP712 {
    function hashTypedData(
        bytes32 structHash
    ) public view virtual returns (bytes32 digest) {
        return _hashTypedData(structHash);
    }

    function hashTypedDataSansChainId(
        bytes32 structHash
    ) public view virtual returns (bytes32 digest) {
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
    {}
}
