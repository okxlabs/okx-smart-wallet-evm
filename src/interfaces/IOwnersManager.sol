// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IOwnersManager {
    // EVENTS
    event ValidatorAdded(address validator);
    event ValidatorRemoved(bytes32 keyHash);
    function getValidator(bytes32 keyHash) external view returns (address);

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
            bool isAdmin,
            bool isExpired
        );

    function isSignerAdmin(bytes32 keyHash) external view returns (bool);

    function getSignerExpiration(
        bytes32 keyHash
    ) external view returns (uint40);

    function isSignerExpired(bytes32 keyHash) external view returns (bool);

    // Validator management functions
    function addValidator(
        bytes32 keyHash,
        address validator,
        bool isAdmin,
        uint40 expiration,
        address hook
    ) external;

    function removeValidator(bytes32 keyHash) external;
}
