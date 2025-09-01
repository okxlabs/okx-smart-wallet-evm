// SPDX-License-Identifier: GPL-3.0
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
    /// @return The address of the verified validator
    function getVerifiedValidator(
        bytes32 keyHash
    ) external view returns (address);

    // Validator enumeration functions
    function ownerCount() external view returns (uint256);
    function ownerAt(uint256 index) external view returns (bytes32);
    function getOwnerKeys() external view returns (bytes32[] memory);
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
    function getHook(uint256 settings) external pure returns (address);
    function getExpiration(uint256 settings) external pure returns (uint40);
    function isAdmin(uint256 settings) external pure returns (bool);
    function isSettingsExpired(uint256 settings) external view returns (bool);
    function packSettings(
        bool adminFlag,
        uint40 expiration,
        address hook
    ) external pure returns (uint256);
}
