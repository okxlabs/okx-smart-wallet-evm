// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IOwnerManager {
    // EVENTS
    event OwnerAdded(bytes32 keyHash, address validator);
    event OwnerRemoved(bytes32 keyHash, address validator);
    event OwnerUpdated(bytes32 keyHash, address newValidator);

    // Public mappings (auto-generated getters)
    function ownerValidators(bytes32 keyHash) external view returns (address);
    function ownerSettings(bytes32 keyHash) external view returns (uint256);

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
    /// @param keyHash The public key hash to associate with this validator
    /// @return Address of the verified validator
    function getVerifiedValidator(
        bytes32 keyHash
    ) external view returns (address);

    // Validator enumeration functions
    /// @notice Returns the total number of registered owners
    /// @return Count of owners in the wallet
    function ownerCount() external view returns (uint256);

    /// @notice Returns the owner key hash at a specific index
    /// @param index The index in the owner set (0-based)
    /// @return Key hash of the owner at the specified index
    function ownerAt(uint256 index) external view returns (bytes32);

    /// @notice Returns all registered owner key hashes
    /// @return Array of all owner key hashes in the wallet
    function getOwnerKeys() external view returns (bytes32[] memory);

    /// @notice Checks if a key hash is registered as an owner
    /// @param keyHash The key hash to check
    /// @return True if the key hash is a registered owner, false otherwise
    function hasOwner(bytes32 keyHash) external view returns (bool);

    // Validator settings query functions
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
    /// @notice Extracts the hook address from packed settings
    /// @param settings The packed settings value
    /// @return Hook address (bits 0-159)
    function getHook(uint256 settings) external pure returns (address);

    /// @notice Extracts the expiration timestamp from packed settings
    /// @param settings The packed settings value
    /// @return Expiration timestamp (bits 160-199)
    function getExpiration(uint256 settings) external pure returns (uint40);

    /// @notice Extracts the admin flag from packed settings
    /// @param settings The packed settings value
    /// @return True if admin flag is set (bit 200), false otherwise
    function isAdmin(uint256 settings) external pure returns (bool);

    /// @notice Checks if the settings have expired based on current block timestamp
    /// @param settings The packed settings value
    /// @return True if expiration > 0 and block.timestamp >= expiration, false otherwise
    function isSettingsExpired(uint256 settings) external view returns (bool);

    /// @notice Packs admin flag, expiration, and hook address into a single uint256
    /// @dev Bit layout: [unused (55 bits)][admin (1 bit)][expiration (40 bits)][hook (160 bits)]
    /// @param adminFlag Whether the owner has admin privileges
    /// @param expiration Timestamp when the owner expires (0 for no expiration)
    /// @param hook Address of the hook contract for this owner
    /// @return Packed settings value
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook
    ) external pure returns (uint256);
}
