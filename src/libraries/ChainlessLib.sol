// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Call} from "../Types.sol";
import {OwnersManager} from "../OwnersManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";

/// @title ChainlessLib
/// @notice Library for chainless operation validation
/// @dev Provides validation functions for operations that can be performed without chain ID
library ChainlessLib {
    /// @notice Checks if a function selector is allowed to skip chain ID validation
    /// @param functionSelector The 4-byte function selector to check
    /// @return true if the selector is allowed to skip chain ID validation, false otherwise
    /// @dev Currently allowed selectors:
    ///      - addOwner
    ///      - upgradeToAndCall
    function canSkipChainIdValidation(
        bytes4 functionSelector
    ) internal pure returns (bool) {
        if (
            functionSelector == OwnersManager.addOwner.selector ||
            functionSelector == UUPSUpgradeable.upgradeToAndCall.selector
        ) {
            return true;
        }
        return false;
    }

    /// @notice Validates that all calls in the batch are allowed to skip chain ID validation
    /// @param calls Array of calls to validate
    /// @param selfAddress The address of the current contract (for self-call validation)
    /// @return true if all calls are allowed to skip chain ID validation, false otherwise
    /// @dev This is used when CHAIN_LESS_NONCE_KEY is used to ensure only allowed operations are performed
    ///      All chainless calls must be self-calls (target == address(this))
    function validateChainlessNonceCallData(
        Call[] memory calls,
        address selfAddress
    ) internal pure returns (bool) {
        for (uint256 i; i < calls.length; i++) {
            // Check that the target must be self (address(this))
            if (calls[i].target != selfAddress) {
                return false;
            }

            bytes memory callData = calls[i].data;
            if (callData.length < 4) {
                return false;
            }

            bytes4 selector;
            assembly {
                /// @dev truncate to only take the first 4 bytes
                selector := mload(add(callData, 32))
            }

            if (!canSkipChainIdValidation(selector)) {
                return false;
            }
        }
        return true;
    }
}
