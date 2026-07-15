// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IOwnerManager} from "./interfaces/IOwnerManager.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {Static} from "./libraries/Static.sol";
import {BaseAuthorization} from "./BaseAuthorization.sol";

/// @title OwnerManager
/// @notice Abstract contract providing owners management functionality for SmartWallet
/// @dev To be inherited by SmartWallet
abstract contract OwnerManager is IOwnerManager, BaseAuthorization {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    // State Variables

    EnumerableSetLib.Bytes32Set internal _ownerKeys; // Set of all owner keyHashes
    mapping(bytes32 => address) internal _ownerValidators; // keyHash => validator address for this owner
    mapping(bytes32 => uint256) internal _ownerSettings; // keyHash => packed settings (isAdmin + expiration + hook)

    // External Functions

    /// @notice Registers a validator with optional settings
    /// @dev Only callable by the wallet itself. Use packSettings() to create the settings parameter.
    /// @param keyHash The public key hash to associate with this validator
    /// @param validator The address of the validator contract to be registered
    /// @param settings Packed settings value (use packSettings to create)
    function addOwner(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) external onlySelf {
        _addOwner(keyHash, validator, settings);
    }

    /// @dev Internal function to add an owner
    /// @param keyHash The public key hash to associate with this validator
    /// @param validator The address of the validator contract to be registered
    /// @param settings Packed settings value (use packSettings to create)
    function _addOwner(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) internal {
        // Check if keyHash is already registered
        if (_ownerKeys.contains(keyHash)) {
            revert IOwnerManager.ValidatorAlreadyExists();
        }
        // Prevent adding address(this) - it's a built-in owner
        if (keyHash == keccak256(abi.encodePacked(address(this)))) {
            revert ISmartWallet.InvalidKeyHash(keyHash);
        }

        // Validate validator address
        _validateValidatorAddress(validator);

        // Store validator with settings
        _setValidatorWithSettings(keyHash, validator, settings);

        emit OwnerAdded(keyHash, validator, settings);
    }

    /// @notice Updates an existing validator's address and/or settings
    /// @dev Only callable by the wallet itself. Use packSettings() to create the settings parameter.
    /// @param keyHash The public key hash to update
    /// @param newValidator The new validator address
    /// @param newSettings New packed settings value (use packSettings to create)
    function updateOwner(
        bytes32 keyHash,
        address newValidator,
        uint256 newSettings
    ) external onlySelf {
        // Check if keyHash exists
        if (!_ownerKeys.contains(keyHash)) {
            revert IOwnerManager.ValidatorNotFound();
        }

        // Validate new validator address
        _validateValidatorAddress(newValidator);

        // Update validator and settings
        _ownerValidators[keyHash] = newValidator;
        _ownerSettings[keyHash] = newSettings;

        emit OwnerUpdated(keyHash, newValidator, newSettings);
    }

    /// @notice Removes a validator associated with a keyHash
    /// @dev Only callable by the wallet itself
    /// @param keyHash The public key hash to remove
    function removeOwner(bytes32 keyHash) external onlySelf {
        // Check if keyHash exists before removing
        if (!_ownerKeys.contains(keyHash)) {
            revert IOwnerManager.ValidatorNotFound();
        }

        emit OwnerRemoved(keyHash, _ownerValidators[keyHash]);

        _removeValidator(keyHash);
    }

    /// External View Functions
    /// @notice Get the total number of registered owners, including expired ones
    /// @return The total number of registered owners
    function ownerCount() external view override returns (uint256) {
        return _ownerKeys.length();
    }

    /// @notice Get the keyHash of the registered owner at the specified index,
    ///         including expired ones
    /// @param index The index of the owner to retrieve
    /// @return The keyHash of the registered owner at the given index
    function ownerAt(uint256 index) external view override returns (bytes32) {
        return _ownerKeys.at(index);
    }

    /// @notice Get all registered owner keyHashes, including expired ones
    /// @return Array of all registered owner keyHashes
    function getOwnerKeys() external view override returns (bytes32[] memory) {
        return _ownerKeys.values();
    }

    /// @notice Check if a keyHash is a registered owner, including expired ones
    /// @param keyHash The keyHash to check
    /// @return True if the keyHash is a registered owner, including expired ones, false otherwise
    function hasOwner(bytes32 keyHash) public view override returns (bool) {
        return _ownerKeys.contains(keyHash);
    }

    /// @notice Get comprehensive validator settings including hook, expiration, and admin status
    /// @param keyHash The public key hash to query
    /// @return validator The validator address
    /// @return hook The hook address (address(0) if no hook)
    /// @return expiration Unix timestamp when validator expires (0 = never expires)
    /// @return adminStatus Whether this validator has admin privileges
    /// @return expired Whether the validator is currently expired
    function getOwnerSettings(
        bytes32 keyHash
    )
        external
        view
        override
        returns (
            address validator,
            address hook,
            uint40 expiration,
            bool adminStatus,
            bool expired
        )
    {
        validator = _ownerValidators[keyHash];
        uint256 settings = _ownerSettings[keyHash];

        if (settings == 0) {
            // No additional settings, return defaults
            return (validator, address(0), 0, false, false);
        }

        hook = getHook(settings);
        expiration = getExpiration(settings);
        adminStatus = isAdmin(settings);
        expired = isSettingsExpired(settings);
    }

    // Public View Functions

    /// @notice Get the active validator address for a given `keyHash`
    /// @dev Returns the configured validator address if present and not expired; otherwise returns address(0).
    ///      For EIP-7702 compatibility, address(this) ALWAYS returns ECDSA validator and cannot be overridden.
    /// @param keyHash The public key hash to look up
    /// @return The validator address to use for validation (address(0) if none or expired)
    function getVerifiedValidator(
        bytes32 keyHash
    ) public view returns (address) {
        // EIP-7702 compatible: Built-in owner for address(this)
        if (keyHash == keccak256(abi.encodePacked(address(this)))) {
            return Static.ECDSA_VALIDATOR_ADDRESS;
        }

        address validator = _ownerValidators[keyHash];

        // Check if validator exists and is not expired
        if (validator != address(0)) {
            uint256 settings = _ownerSettings[keyHash];
            if (settings != 0 && isSettingsExpired(settings)) {
                validator = address(0); // Expired validator
            }
        }

        return validator;
    }

    /// @notice Check if settings are expired based on block timestamp
    /// @param settings Packed settings value
    /// @return expired True if settings are expired (expiration != 0 and < block.timestamp)
    function isSettingsExpired(uint256 settings) public view returns (bool) {
        uint40 expiration = getExpiration(settings);
        // expiration = 0 means never expires
        return expiration != 0 && expiration < block.timestamp;
    }

    // Public Pure Functions (Settings Management)
    // Bit layout: [255-208: UNUSED] [207-200: isAdmin] [199-160: expiration] [159-0: hook]

    /// @notice Pack settings into uint256
    /// @param adminFlag Admin flag
    /// @param expiration Unix timestamp (0 = never expires)
    /// @param hook Hook address (address(0) = no hook)
    /// @return packed Packed settings value
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook
    ) public pure returns (uint256) {
        return
            (uint256(adminFlag ? 1 : 0) << 200) |
            (uint256(expiration) << 160) |
            uint256(uint160(hook));
    }

    /// @notice Extract hook address from packed settings (bits 0-159)
    /// @param settings Packed settings value
    /// @return hook Hook address (address(0) = no hook)
    function getHook(uint256 settings) public pure returns (address) {
        return address(uint160(settings));
    }

    /// @notice Extract expiration timestamp from packed settings (bits 160-199)
    /// @param settings Packed settings value
    /// @return expiration Unix timestamp (0 = never expires)
    function getExpiration(uint256 settings) public pure returns (uint40) {
        return uint40(settings >> 160);
    }

    /// @notice Extract admin flag from packed settings (bits 200-207)
    /// @param settings Packed settings value
    /// @return isAdmin True if signer has admin privileges
    function isAdmin(uint256 settings) public pure returns (bool) {
        return ((settings >> 200) & 0xff) == 1;
    }

    // Internal Functions

    /// @notice Internal function to set an owner's validator with settings atomically
    /// @param keyHash The owner's public key hash
    /// @param validator The validator address to associate with this owner
    /// @param settings Packed settings value (0 for default settings)
    function _setValidatorWithSettings(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) internal {
        _ownerValidators[keyHash] = validator;
        _ownerSettings[keyHash] = settings;
        _ownerKeys.add(keyHash); // Add to the set
    }

    /// @notice Internal function to remove an owner's validator mapping
    /// @param keyHash The owner's public key hash to remove
    function _removeValidator(bytes32 keyHash) internal {
        delete _ownerValidators[keyHash];
        delete _ownerSettings[keyHash];
        _ownerKeys.remove(keyHash); // Remove from the set
    }

    /// @notice Internal function to validate validator address
    /// @param validator The validator address to validate
    function _validateValidatorAddress(address validator) internal view {
        // Allow built-in validator addresses (1 and 2), but check other addresses have contract code
        if (
            validator != Static.ECDSA_VALIDATOR_ADDRESS &&
            validator != Static.PASSKEY_VALIDATOR_ADDRESS &&
            validator.code.length == 0
        ) {
            revert IOwnerManager.InvalidValidatorImpl(validator);
        }
    }
}
