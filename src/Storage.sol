// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IStorage} from "./interfaces/IStorage.sol";
import {Errors} from "./libraries/Errors.sol";
import {Static} from "./libraries/Static.sol";

contract Storage is IStorage {
    //mutable storage
    uint256 private _nonce;
    mapping(uint256 => bool) private _invalidSessionId;
    mapping(bytes32 => address) private _signers; // keyHash => validator address

    /**
     * @notice Restricts function access to the wallet owner only
     * @dev Reverts with INVALID_OWNER if caller is not the owner
     */
    modifier onlyOwner() {
        if (msg.sender != getOwner()) {
            revert Errors.InvalidOwner();
        }
        _;
    }

    /**
     * @notice Reads the current nonce and increments it for the next transaction
     * @dev Only callable by wallet owner. Uses unchecked math for gas optimization
     * @param validator The address of the validator contract
     * @return uint256 The current nonce before increment
     */
    function readAndUpdateNonce(
        address validator
    ) external onlyOwner returns (uint256) {
        if (validator == address(0)) {
            revert Errors.InvalidValidator(validator);
        }
        unchecked {
            uint256 currentNonce = _nonce++;
            emit NonceConsumed(currentNonce);
            return currentNonce;
        }
    }

    /**
     * @notice Revokes the specified session ID, marking it as invalid.
     * @dev Only callable by wallet owner
     * @param id The session ID to be revoked
     */
    function revokeSession(uint256 id) external onlyOwner {
        _invalidSessionId[id] = true;
        emit SessionRevoked(id);
    }

    /**
     * @notice Returns the owner address of the wallet
     * @dev Decodes the owner address from the proxy contract's initialization data
     * @return owner The owner address of the wallet
     */
    function getOwner() public view returns (address owner) {
        assembly {
            extcodecopy(address(), 12, 57, 20)
            owner := mload(0)
        }
    }

    /**
     * @notice Returns the current nonce value
     * @dev Can be called by anyone
     * @return uint256 The current nonce value
     */
    function getNonce() external view returns (uint256) {
        return _nonce;
    }

    /**
     * @notice Validates a session
     * @dev Returns false if session is invalid (blacklisted)
     * @param id The ID of the session to validate
     * @return bool True if session is valid, false otherwise
     */
    function validateSession(uint256 id) external view returns (bool) {
        return !_invalidSessionId[id];
    }

    /**
     * @notice Sets a keyHash to validator mapping
     * @dev Only callable by wallet owner
     * @param keyHash The public key hash to map
     * @param validator The validator address to associate with the keyHash
     */
    function setValidator(
        bytes32 keyHash,
        address validator
    ) external onlyOwner {
        _signers[keyHash] = validator;
    }

    /**
     * @notice Gets the validator address associated with a keyHash
     * @param keyHash The public key hash to look up
     * @return address The validator address, or address(0) if not found
     */
    function getValidator(bytes32 keyHash) external view returns (address) {
        return _signers[keyHash];
    }

    /**
     * @notice Removes a keyHash to validator mapping
     * @dev Only callable by wallet owner
     * @param keyHash The public key hash to remove
     */
    function removeValidator(bytes32 keyHash) external onlyOwner {
        delete _signers[keyHash];
    }
}
