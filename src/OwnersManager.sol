// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IOwnersManager} from "./interfaces/IOwnersManager.sol";
import {Errors} from "./libraries/Errors.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {Static} from "./libraries/Static.sol";

/**
 * @title OwnersManager
 * @notice Abstract contract providing owners management functionality for WalletCore
 * @dev To be inherited by WalletCore
 */
abstract contract OwnersManager is IOwnersManager {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    // ============ State Variables ============

    EnumerableSetLib.Bytes32Set internal _ownerKeys; // Set of all owner keyHashes
    mapping(bytes32 => address) public ownerValidators; // keyHash => validator address for this owner
    mapping(bytes32 => uint256) public ownerSettings; // keyHash => packed settings (isAdmin + expiration + hook)
    // TODO: add whitelistedBundlers

    // ============ Modifiers ============

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Errors.NotFromSelf();
        }
        _;
    }

    // ============ External Functions ============

    /**
     * @notice Registers a validator with optional settings
     * @dev Only callable by the wallet itself. Use packSettings() to create the settings parameter.
     * @param keyHash The public key hash to associate with this validator
     * @param validator The address of the validator contract to be registered
     * @param settings Packed settings value (use packSettings to create)
     */
    function addValidator(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) external onlySelf {
        // Check if keyHash is already registered
        if (_ownerKeys.contains(keyHash)) {
            revert Errors.ValidatorAlreadyExists();
        }

        // Validate validator address
        _validateValidatorAddress(validator);

        // Store validator with settings
        _setValidatorWithSettings(keyHash, validator, settings);

        emit ValidatorAdded(validator);
    }

    /**
     * @notice Updates an existing validator's address and/or settings
     * @dev Only callable by the wallet itself. Use packSettings() to create the settings parameter.
     * @param keyHash The public key hash to update
     * @param newValidator The new validator address
     * @param newSettings New packed settings value (use packSettings to create)
     */
    function updateValidator(
        bytes32 keyHash,
        address newValidator,
        uint256 newSettings
    ) external onlySelf {
        // Check if keyHash exists
        if (!_ownerKeys.contains(keyHash)) {
            revert Errors.ValidatorNotFound();
        }

        // Validate new validator address
        _validateValidatorAddress(newValidator);

        // Update validator and settings
        ownerValidators[keyHash] = newValidator;
        ownerSettings[keyHash] = newSettings;

        emit ValidatorUpdated(keyHash, newValidator);
    }

    /**
     * @notice Removes a validator associated with a keyHash
     * @dev Only callable by the wallet owner
     * @param keyHash The public key hash to remove
     */
    function removeValidator(bytes32 keyHash) external onlySelf {
        _removeValidator(keyHash);
        emit ValidatorRemoved(keyHash);
    }

    // ============ External View Functions (Interface Implementation) ============
    // Note: Function names retain "Validator" for interface compatibility,
    // but they actually enumerate wallet owners and their keyHashes

    function ownerCount()
        external
        view
        override
        returns (uint256)
    {
        return _ownerKeys.length();
    }

    function ownerAt(
        uint256 index
    ) external view override returns (bytes32) {
        return _ownerKeys.at(index);
    }

    function getOwnerKeys()
        external
        view
        override
        returns (bytes32[] memory)
    {
        return _ownerKeys.values();
    }

    function hasOwner(
        bytes32 keyHash
    ) external view override returns (bool) {
        return _ownerKeys.contains(keyHash);
    }

    /**
     * @notice Get comprehensive validator settings including hook, expiration, and admin status
     * @param keyHash The public key hash to query
     * @return validator The validator address
     * @return hook The hook address (address(0) if no hook)
     * @return expiration Unix timestamp when validator expires (0 = never expires)
     * @return adminStatus Whether this validator has admin privileges
     * @return expired Whether the validator is currently expired
     */
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
        validator = ownerValidators[keyHash];
        uint256 settings = ownerSettings[keyHash];

        if (settings == 0) {
            // No additional settings, return defaults
            return (validator, address(0), 0, false, false);
        }

        hook = getHook(settings);
        expiration = getExpiration(settings);
        adminStatus = isAdmin(settings);
        expired = isSettingsExpired(settings);
    }

    // ============ Public View Functions ============

    /**
     * @notice Get the verified validator address for a given keyHash with EIP-7702 support
     * @dev Returns built-in ECDSA validator (address(1)) for self-signing when no validator installed
     * @param keyHash The public key hash to look up
     * @return The validator address to use for validation
     */
    function getVerifiedValidator(
        bytes32 keyHash
    ) public view returns (address) {
        address validator = ownerValidators[keyHash];

        // Check if validator exists and is not expired
        if (validator != address(0)) {
            uint256 settings = ownerSettings[keyHash];
            if (settings != 0 && isSettingsExpired(settings)) {
                validator = address(0); // Expired validator
            }
        } else if (keyHash == keccak256(abi.encode(address(this)))) {
            // EIP-7702: Default to ECDSA for self-signing
            return Static.ECDSA_VALIDATOR_ADDRESS;
        }

        return validator;
    }

    /**
     * @notice Check if settings are expired based on block timestamp
     * @param settings Packed settings value
     * @return expired True if settings are expired (expiration != 0 and < block.timestamp)
     */
    function isSettingsExpired(uint256 settings) public view returns (bool) {
        uint40 expiration = getExpiration(settings);
        // expiration = 0 means never expires
        return expiration != 0 && expiration < block.timestamp;
    }

    // ============ Public Pure Functions (Settings Management) ============
    // Bit layout for settings (following Calibur's layout)
    // Layout: 6 bytes UNUSED | 1 byte isAdmin | 5 bytes expiration | 20 bytes hook
    // Bits:   [255-208]       | [207-200]      | [199-160]        | [159-0]

    /**
     * @notice Pack settings into uint256 following Calibur's layout
     * @param adminFlag Admin flag
     * @param expiration Unix timestamp (0 = never expires)
     * @param hook Hook address (address(0) = no hook)
     * @return packed Packed settings value
     */
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook
    ) public pure returns (uint256) {
        return
            uint256(uint160(hook)) |
            (uint256(expiration) << 160) |
            (uint256(adminFlag ? 1 : 0) << 200);
    }

    /**
     * @notice Extract hook address from packed settings (bits 0-159)
     * @param settings Packed settings value
     * @return hook Hook address (address(0) = no hook)
     */
    function getHook(uint256 settings) public pure returns (address) {
        return address(uint160(settings));
    }

    /**
     * @notice Extract expiration timestamp from packed settings (bits 160-199)
     * @param settings Packed settings value
     * @return expiration Unix timestamp (0 = never expires)
     */
    function getExpiration(uint256 settings) public pure returns (uint40) {
        return uint40(settings >> 160);
    }

    /**
     * @notice Extract admin flag from packed settings (bits 200-207)
     * @param settings Packed settings value
     * @return isAdmin True if signer has admin privileges
     */
    function isAdmin(uint256 settings) public pure returns (bool) {
        return (settings >> 200) != 0;
    }

    // ============ Internal Functions ============

    /**
     * @notice Internal function to set an owner's validator with settings atomically
     * @param keyHash The owner's public key hash
     * @param validator The validator address to associate with this owner
     * @param settings Packed settings value (0 for default settings)
     */
    function _setValidatorWithSettings(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) internal {
        ownerValidators[keyHash] = validator;
        ownerSettings[keyHash] = settings;
        _ownerKeys.add(keyHash); // Add to the set
    }

    /**
     * @notice Internal function to remove an owner's validator mapping
     * @param keyHash The owner's public key hash to remove
     */
    function _removeValidator(bytes32 keyHash) internal {
        delete ownerValidators[keyHash];
        delete ownerSettings[keyHash];
        _ownerKeys.remove(keyHash); // Remove from the set
    }

    /**
     * @notice Internal function to validate validator address
     * @param validator The validator address to validate
     */
    function _validateValidatorAddress(address validator) internal view {
        // Allow built-in validator addresses (1 and 2), but check other addresses have contract code
        if (
            validator != Static.ECDSA_VALIDATOR_ADDRESS &&
            validator != Static.PASSKEY_VALIDATOR_ADDRESS &&
            validator.code.length == 0
        ) {
            revert Errors.InvalidValidatorImpl(validator);
        }
    }

}
