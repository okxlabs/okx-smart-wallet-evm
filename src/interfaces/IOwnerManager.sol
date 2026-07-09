// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IOwnerManager {
    // ERRORS
    error InvalidValidatorImpl(address validatorImpl);
    error ValidatorAlreadyExists();
    error ValidatorNotFound();

    // EVENTS
    event OwnerAdded(bytes32 keyHash, address validator, uint256 settings);
    event OwnerRemoved(bytes32 keyHash, address validator);
    event OwnerUpdated(bytes32 keyHash, address newValidator, uint256 settings);

    /// @notice Add an owner to the wallet
    /// @param keyHash The public key hash to associate with this validator
    /// @param validator The address of the validator contract to be registered
    /// @param settings Packed settings value (use packSettings to create)
    function addOwner(
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) external;

    /// @notice Update an owner to the wallet
    /// @param keyHash The public key hash to associate with this validator
    /// @param newValidator The address of the validator contract to be registered
    /// @param newSettings Packed settings value (use packSettings to create)
    function updateOwner(
        bytes32 keyHash,
        address newValidator,
        uint256 newSettings
    ) external;

    /// @notice Remove an owner from the wallet
    /// @param keyHash The public key hash to associate with this validator
    function removeOwner(bytes32 keyHash) external;

    /// @notice Get the verified validator for a given keyHash
    /// @dev For EIP-7702 compatibility, address(this) ALWAYS returns ECDSA validator and cannot be overridden.
    ///      The built-in address(this) owner is immutable and ignores any settings in ownerValidators or ownerSettings.
    /// @param keyHash The public key hash to associate with this validator
    /// @return Address of the verified validator
    function getVerifiedValidator(
        bytes32 keyHash
    ) external view returns (address);

    // Validator enumeration functions
    /// @notice Returns the total number of owners registered in the wallet
    /// @return The count of registered owners
    function ownerCount() external view returns (uint256);

    /// @notice Returns the keyHash of the owner at the specified index
    /// @param index The index of the owner to retrieve
    /// @return The keyHash of the owner at the given index
    function ownerAt(uint256 index) external view returns (bytes32);

    /// @notice Returns all owner keyHashes
    /// @return Array of all registered owner keyHashes
    function getOwnerKeys() external view returns (bytes32[] memory);

    /// @notice Checks if a keyHash is registered as an owner
    /// @param keyHash The keyHash to check
    /// @return True if the keyHash is a registered owner, false otherwise
    function hasOwner(bytes32 keyHash) external view returns (bool);

    // Validator settings query functions
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
        returns (
            address validator,
            address hook,
            uint40 expiration,
            bool adminStatus,
            bool expired
        );

    // Settings utility functions
    /// @notice Extract hook address from packed settings (bits 0-159)
    /// @param settings Packed settings value
    /// @return Hook address (address(0) = no hook)
    function getHook(uint256 settings) external pure returns (address);

    /// @notice Extract expiration timestamp from packed settings (bits 160-199)
    /// @param settings Packed settings value
    /// @return Unix timestamp (0 = never expires)
    function getExpiration(uint256 settings) external pure returns (uint40);

    /// @notice Extract admin flag from packed settings (bits 200-207)
    /// @param settings Packed settings value
    /// @return True if signer has admin privileges
    function isAdmin(uint256 settings) external pure returns (bool);

    /// @notice Whether the key's hook opts into the new signature/TWA hook interfaces (bits 208-215)
    /// @param settings Packed settings value
    /// @return True if the signature-hook flag is set (new hook); false for legacy hooks
    function checkHookFlag(uint256 settings) external pure returns (bool);

    /// @notice Check if settings are expired based on block timestamp
    /// @param settings Packed settings value
    /// @return True if settings are expired (expiration != 0 and < block.timestamp)
    function isSettingsExpired(uint256 settings) external view returns (bool);

    /// @notice Pack settings into uint256 (sigHookFlag defaults to 0 / legacy hook)
    /// @param adminFlag Admin flag
    /// @param expiration Unix timestamp (0 = never expires)
    /// @param hook Hook address (address(0) = no hook)
    /// @return Packed settings value
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook
    ) external pure returns (uint256);

    /// @notice Pack settings into uint256, explicitly setting the signature-hook flag
    /// @param adminFlag Admin flag
    /// @param expiration Unix timestamp (0 = never expires)
    /// @param hook Hook address (address(0) = no hook)
    /// @param sigHookFlag Whether the hook opts into the new signature/TWA hook interfaces
    /// @return Packed settings value
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook,
        bool sigHookFlag
    ) external pure returns (uint256);
}
