// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

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

    modifier onlyOwner() {
        bytes32 keyHash = keccak256(abi.encode(msg.sender));
        if (msg.sender != address(this) && !_ownerKeys.contains(keyHash))
            revert Errors.NotFromSelf();
        _;
    }

    // ============ Storage Variables ============
    EnumerableSetLib.Bytes32Set internal _ownerKeys; // Set of all owner keyHashes
    mapping(bytes32 => address) public _ownerValidators; // keyHash => validator address for this owner
    mapping(bytes32 => uint256) public _ownerSettings; // keyHash => packed settings (isAdmin + expiration + hook)
    // TODO: add whitelistedBundlers

    // ============ Validator Management ============
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
        _ownerValidators[keyHash] = validator;
        _ownerSettings[keyHash] = settings;
        _ownerKeys.add(keyHash); // Add to the set
    }

    /**
     * @notice Internal function to remove an owner's validator mapping
     * @param keyHash The owner's public key hash to remove
     */
    function _removeValidator(bytes32 keyHash) internal {
        delete _ownerValidators[keyHash];
        delete _ownerSettings[keyHash];
        _ownerKeys.remove(keyHash); // Remove from the set
    }

    // ============ Validator Getter ============

    /**
     * @notice Get the validator address for a given keyHash
     * @dev Returns address(0) if validator doesn't exist or is expired
     * @param keyHash The public key hash to look up
     * @return The validator address, or address(0) if invalid/expired
     */
    function getValidator(
        bytes32 keyHash
    ) public view virtual override returns (address) {
        address validator = _ownerValidators[keyHash];
        if (validator == address(0)) return address(0);

        // Check if validator is expired
        uint256 settings = _ownerSettings[keyHash];
        if (settings != 0 && _isExpired(settings)) {
            return address(0); // Expired validator is treated as invalid
        }

        return validator;
    }

    // ============ Settings Management ============

    // Bit layout for settings (following Calibur's layout)
    // Layout: 6 bytes UNUSED | 1 byte isAdmin | 5 bytes expiration | 20 bytes hook
    // Bits:   [255-208]       | [207-200]      | [199-160]        | [159-0]

    /**
     * @notice Obtain settings from owner keyHash
     * @param keyHash The owner's public key hash to get settings for
     * @return settings Packed settings value
     */
    function _getSettings(bytes32 keyHash) internal view returns (uint256) {
        return _ownerSettings[keyHash];
    }

    /**
     * @notice Extract hook address from packed settings (bits 0-159)
     * @param settings Packed settings value
     * @return hook Hook address (address(0) = no hook)
     */
    function _getHook(uint256 settings) internal pure returns (address) {
        return address(uint160(settings));
    }

    /**
     * @notice Extract expiration timestamp from packed settings (bits 160-199)
     * @param settings Packed settings value
     * @return expiration Unix timestamp (0 = never expires)
     */
    function _getExpiration(uint256 settings) internal pure returns (uint40) {
        return uint40(settings >> 160);
    }

    /**
     * @notice Extract admin flag from packed settings (bits 200-207)
     * @param settings Packed settings value
     * @return isAdmin True if signer has admin privileges
     */
    function _isAdmin(uint256 settings) internal pure returns (bool) {
        return (settings >> 200) != 0;
    }

    /**
     * @notice Check if settings are expired based on block timestamp
     * @param settings Packed settings value
     * @return expired True if settings are expired (expiration != 0 and < block.timestamp)
     */
    function _isExpired(uint256 settings) internal view returns (bool) {
        uint40 expiration = _getExpiration(settings);
        // expiration = 0 means never expires
        return expiration != 0 && expiration < block.timestamp;
    }

    /**
     * @notice Pack settings into uint256 following Calibur's layout
     * @param isAdmin Admin flag
     * @param expiration Unix timestamp (0 = never expires)
     * @param hook Hook address (address(0) = no hook)
     * @return packed Packed settings value
     */
    function _packSettings(
        bool isAdmin,
        uint40 expiration,
        address hook
    ) internal pure returns (uint256) {
        return
            uint256(uint160(hook)) |
            (uint256(expiration) << 160) |
            (uint256(isAdmin ? 1 : 0) << 200);
    }

    // ============ Owner Enumeration Functions ============
    // Note: Function names retain "Validator" for interface compatibility,
    // but they actually enumerate wallet owners and their keyHashes

    function getValidatorCount()
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _ownerKeys.length();
    }

    function getValidatorAt(
        uint256 index
    ) external view virtual override returns (bytes32) {
        return _ownerKeys.at(index);
    }

    function getAllValidatorKeys()
        external
        view
        virtual
        override
        returns (bytes32[] memory)
    {
        return _ownerKeys.values();
    }

    function hasValidator(
        bytes32 keyHash
    ) external view virtual override returns (bool) {
        return _ownerKeys.contains(keyHash);
    }

    // ============ Settings Query Functions ============

    /**
     * @notice Get comprehensive validator settings including hook, expiration, and admin status
     * @param keyHash The public key hash to query
     * @return validator The validator address
     * @return hook The hook address (address(0) if no hook)
     * @return expiration Unix timestamp when validator expires (0 = never expires)
     * @return isAdmin Whether this validator has admin privileges
     * @return isExpired Whether the validator is currently expired
     */
    function getValidatorSettings(
        bytes32 keyHash
    )
        external
        view
        virtual
        override
        returns (
            address validator,
            address hook,
            uint40 expiration,
            bool isAdmin,
            bool isExpired
        )
    {
        validator = _ownerValidators[keyHash];
        uint256 settings = _ownerSettings[keyHash];

        if (settings == 0) {
            // No additional settings, return defaults
            return (validator, address(0), 0, false, false);
        }

        hook = _getHook(settings);
        expiration = _getExpiration(settings);
        isAdmin = _isAdmin(settings);
        isExpired = _isExpired(settings);
    }

    /**
     * @notice Check if a signer has admin privileges
     * @param keyHash The public key hash to check
     * @return isAdmin True if signer is admin, false otherwise
     */
    function isSignerAdmin(
        bytes32 keyHash
    ) external view virtual override returns (bool) {
        uint256 settings = _ownerSettings[keyHash];
        return settings != 0 && _isAdmin(settings);
    }

    /**
     * @notice Get the expiration timestamp of a signer
     * @param keyHash The public key hash to check
     * @return expiration Unix timestamp (0 = never expires)
     */
    function getSignerExpiration(
        bytes32 keyHash
    ) external view virtual override returns (uint40) {
        uint256 settings = _ownerSettings[keyHash];
        return settings != 0 ? _getExpiration(settings) : 0;
    }

    /**
     * @notice Check if a signer is currently expired
     * @param keyHash The public key hash to check
     * @return isExpired True if expired, false otherwise
     */
    function isSignerExpired(
        bytes32 keyHash
    ) external view virtual override returns (bool) {
        uint256 settings = _ownerSettings[keyHash];
        return settings != 0 && _isExpired(settings);
    }

    // ============ Validator Management Functions ============

    /**
     * @notice Registers a validator with optional settings
     * @dev Only callable by the wallet itself. Use default parameters for simple registration.
     * @param keyHash The public key hash to associate with this validator
     * @param validator The address of the validator contract to be registered
     * @param isAdmin Whether this validator has admin privileges
     * @param expiration Unix timestamp when validator expires (0 = never expires)
     * @param hook The hook address for additional validation (address(0) = no hook)
     */
    function addValidator(
        bytes32 keyHash,
        address validator,
        bool isAdmin,
        uint40 expiration,
        address hook
    ) external virtual override onlyOwner {
        // Check if keyHash is already registered
        address existingValidator = _ownerValidators[keyHash];
        if (existingValidator != address(0)) {
            revert Errors.ValidatorAlreadyExists();
        }

        // Allow SELF_VALIDATION_ADDRESS, but check other addresses have contract code
        if (
            validator != Static.SELF_VALIDATION_ADDRESS &&
            validator.code.length == 0
        ) {
            revert Errors.InvalidValidatorImpl(validator);
        }

        // Pack and store settings
        uint256 settings = _packSettings(isAdmin, expiration, hook);
        _setValidatorWithSettings(keyHash, validator, settings);

        emit ValidatorAdded(validator);
    }

    /**
     * @notice Removes a validator associated with a keyHash
     * @dev Only callable by the wallet owner
     * @param keyHash The public key hash to remove
     */
    function removeValidator(
        bytes32 keyHash
    ) external virtual override onlyOwner {
        _removeValidator(keyHash);
        emit ValidatorRemoved(keyHash);
    }
}
