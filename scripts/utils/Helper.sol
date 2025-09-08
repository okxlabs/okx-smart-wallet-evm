// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {UserOperationLib} from "account-abstraction/core/UserOperationLib.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {InitialOwner} from "src/Types.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";

library HelperLib {
    uint256 public constant CHALLENGE_LOCATION = 23;
    uint256 public constant TYPE_INDEX = 1;

    string public constant CLIENT_DATA_JSON_PRE =
        '{"type":"webauthn.get","challenge":"';
    string public constant CLIENT_DATA_JSON_POST =
        '","origin":"http://localhost:8000","crossOrigin":false}';
    bytes public constant AUTHENTICATOR_DATA =
        hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000";

    using UserOperationLib for PackedUserOperation;

    function getUserOpHashWithEntryPoint(
        address entryPoint,
        uint256 chainid,
        PackedUserOperation calldata userOp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(userOp.hash(), entryPoint, chainid));
    }

    function getPubkeyHash(
        uint256 pubKeyX,
        uint256 pubKeyY
    ) internal pure returns (bytes32, bytes memory) {
        bytes32 hash = keccak256(abi.encode([pubKeyX, pubKeyY]));
        bytes memory encodeHash = abi.encode(hash);
        return (hash, encodeHash);
    }

    function getPasskeyMessageHash(
        bytes32 challenge
    )
        internal
        pure
        returns (
            string memory clientDataJson,
            bytes memory message,
            bytes32 messageHash
        )
    {
        string memory challengeB64url = Base64.encodeURL(abi.encode(challenge));

        clientDataJson = string.concat(
            CLIENT_DATA_JSON_PRE,
            challengeB64url,
            CLIENT_DATA_JSON_POST
        );

        bytes32 clientDataHash = sha256(bytes(clientDataJson));

        message = bytes.concat(AUTHENTICATOR_DATA, clientDataHash);
        messageHash = sha256(message);
    }

    function getWebAuthnAuth(
        bytes32 challenge,
        uint256 r,
        uint256 s
    ) internal pure returns (WebAuthn.WebAuthnAuth memory webAuthnAuth) {
        (string memory clientDataJson, , ) = getPasskeyMessageHash(challenge);
        webAuthnAuth = WebAuthn.WebAuthnAuth({
            authenticatorData: AUTHENTICATOR_DATA,
            clientDataJSON: clientDataJson,
            typeIndex: TYPE_INDEX,
            challengeIndex: CHALLENGE_LOCATION,
            r: r,
            s: s
        });
    }

    function webAuthnVerify(
        bytes32 challenge,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y
    ) internal view returns (bool) {
        WebAuthn.WebAuthnAuth memory webAuthnAuth = getWebAuthnAuth(
            challenge,
            r,
            s
        );
        return
            WebAuthn.verify(abi.encode(challenge), false, webAuthnAuth, x, y);
    }

    function getMerkleProofRootHash(
        bytes32[] memory proofs,
        bytes32 leaf
    ) internal pure returns (bytes32) {
        return MerkleProof.processProof(proofs, leaf);
    }
}

contract Helper {
    using UserOperationLib for PackedUserOperation;

    function getUserOpHashWithEntryPoint(
        address entryPoint,
        uint256 chainid,
        PackedUserOperation calldata userOp
    ) external pure returns (bytes32) {
        return
            HelperLib.getUserOpHashWithEntryPoint(entryPoint, chainid, userOp);
    }

    function getPubkeyHash(
        uint256 pubKeyX,
        uint256 pubKeyY
    ) external pure returns (bytes32, bytes memory) {
        return HelperLib.getPubkeyHash(pubKeyX, pubKeyY);
    }

    function getPasskeyMessageHash(
        bytes32 challenge
    )
        external
        pure
        returns (
            string memory clientDataJson,
            bytes memory message,
            bytes32 messageHash
        )
    {
        return HelperLib.getPasskeyMessageHash(challenge);
    }

    function getWebAuthnAuth(
        bytes32 challenge,
        uint256 r,
        uint256 s
    ) external pure returns (WebAuthn.WebAuthnAuth memory webAuthnAuth) {
        return HelperLib.getWebAuthnAuth(challenge, r, s);
    }

    function webAuthnVerify(
        bytes32 challenge,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y
    ) external view returns (bool) {
        return HelperLib.webAuthnVerify(challenge, r, s, x, y);
    }

    function getMerkleProofRootHash(
        bytes32[] memory proofs,
        bytes32 leaf
    ) external pure returns (bytes32) {
        return HelperLib.getMerkleProofRootHash(proofs, leaf);
    }

    function getValidatorData(
        bytes32 challenge,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y
    ) external pure returns (bytes memory) {
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            challenge,
            r,
            s
        );
        bytes memory sig = abi.encode(auth, new bytes(0));
        return abi.encodePacked(abi.encode(x, y), sig);
    }

    function getProxyInitCode(
        address implementation
    ) external pure returns (bytes memory) {
        return LibClone.initCodeERC1967(implementation);
    }

    function getProxyInitCodeHash(
        address implementation
    ) external pure returns (bytes32) {
        return LibClone.initCodeHashERC1967(implementation);
    }

    function predictDeterministicAddress(
        address implementation,
        InitialOwner[] calldata initialOwners,
        uint256 salt,
        address factory
    ) external pure returns (address) {
        return
            LibClone.predictDeterministicAddressERC1967(
                implementation,
                _getSalt(initialOwners, salt),
                factory
            );
    }

    function _getSalt(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(initialOwners, salt));
    }

    function getExecuteUserOpSelector() external pure returns (bytes4) {
        return IERC4337Account.executeUserOp.selector;
    }
}

contract EntryPointMock is EntryPoint {}
