// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IValidator} from "../interfaces/IValidator.sol";

/// @notice A library to store constant values that are used across the WalletCore contracts
library Static {
    /**
     * @notice new storage should have a different salt
     */
    bytes32 public constant STORAGE_SALT =
        keccak256(abi.encodePacked("storage"));

    bytes32 public constant VALIDATOR_SALT =
        keccak256(abi.encodePacked("validator"));

    address public constant SELF_VALIDATION_ADDRESS = address(1);
}
