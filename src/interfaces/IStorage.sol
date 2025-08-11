// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IStorage {
    // EVENTS
    event NonceConsumed(uint256 utilisedNonce);
    event SessionRevoked(uint256 id);

    // FUNCTIONS
    function readAndUpdateNonce(address validator) external returns (uint256);

    function revokeSession(uint256 id) external;

    function getOwner() external view returns (address);

    function getNonce() external view returns (uint256);

    function validateSession(uint256 id) external view returns (bool);

    function setValidator(bytes32 keyHash, address validator) external;

    function getValidator(bytes32 keyHash) external view returns (address);

    function removeValidator(bytes32 keyHash) external;
}
