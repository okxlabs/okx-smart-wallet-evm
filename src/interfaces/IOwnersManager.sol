// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

interface IOwnersManager {
    // EVENTS
    event ValidatorAdded(address validator);
    event ValidatorRemoved(bytes32 keyHash);
    
    // Public mappings (auto-generated getters)
    function ownerValidators(bytes32 keyHash) external view returns (address);
    function ownerSettings(bytes32 keyHash) external view returns (uint256);
    
    function getVerifiedValidator(
        bytes32 keyHash
    ) external view returns (address);

    // Validator enumeration functions
    function getValidatorCount() external view returns (uint256);
    function getValidatorAt(uint256 index) external view returns (bytes32);
    function getAllValidatorKeys() external view returns (bytes32[] memory);
    function hasValidator(bytes32 keyHash) external view returns (bool);

    // Validator settings query functions
    function getValidatorSettings(
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

    // Validator management functions
    function addValidator(
        bytes32 keyHash,
        address validator,
        bool adminFlag,
        uint40 expiration,
        address hook
    ) external;

    function removeValidator(bytes32 keyHash) external;
}
