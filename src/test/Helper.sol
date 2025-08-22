// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {UserOperationLib} from "account-abstraction/core/UserOperationLib.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {Utils, WebAuthnInfo} from "webauthn-sol/../test/Utils.sol";

library Helper {
    uint256 constant CHALLENGE_LOCATION = 23;
    uint256 constant TYPE_INDEX = 1;

    string constant CLIENT_DATA_JSON_PRE = '{"type":"webauthn.get","challenge":"';
    string constant CLIENT_DATA_JSON_POST = '","origin":"http://localhost:8000","crossOrigin":false}';
    bytes constant AUTHENTICATOR_DATA = hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000";

    using UserOperationLib for PackedUserOperation;

    function getUserOpHashWithEntryPoint(
        address entryPoint,
        uint256 chainid,
        PackedUserOperation calldata userOp
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    userOp.hash(),
                    entryPoint,
                    chainid
                )
            );
    }

    function getPubkeyHash(
        uint256 pubKeyX,
        uint256 pubKeyY
    ) internal pure returns (bytes32, bytes memory) {
        bytes32 hash = keccak256(abi.encode([pubKeyX, pubKeyY]));
        bytes memory encodeHash = abi.encode(hash);
        return (hash, encodeHash);
    }

    function getBlocktimeStamp() internal view returns (uint256) {
        return block.timestamp;
    }

    function getPasskeyMessageHash(
        bytes32 challenge
    )
        internal
        pure
        returns (
            string memory clientDataJSON,
            bytes memory message,
            bytes32 messageHash
        )
    {
        string memory challengeB64url = Base64.encodeURL(
            abi.encode(challenge)
        );

        clientDataJSON = string.concat(
            CLIENT_DATA_JSON_PRE,
            challengeB64url,
            CLIENT_DATA_JSON_POST
        );

        bytes32 clientDataHash = sha256(bytes(clientDataJSON));

        message = bytes.concat(AUTHENTICATOR_DATA, clientDataHash);
        messageHash = sha256(message);
    }

    function getCoinbasePasskeyMessageHash(
        bytes32 challenge
    )
        internal
        pure
        returns (
            string memory clientDataJSON,
            bytes memory message,
            bytes32 messageHash
        )
    {   
        clientDataJSON = string.concat(
                '{"type":"webauthn.get","challenge":"', Base64.encodeURL(abi.encode(challenge)), '","origin":"http://localhost:3005"}');

        bytes32 clientDataHash = sha256(bytes(clientDataJSON));

        message = bytes.concat(hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101", clientDataHash);
        messageHash = sha256(message);
    }

    function getWebAuthnAuth(
        bytes32 challenge,
        uint256 r,
        uint256 s
    ) internal pure returns (WebAuthn.WebAuthnAuth memory webAuthnAuth) {
        (string memory clientDataJSON, , ) = getPasskeyMessageHash(challenge);
        webAuthnAuth = WebAuthn.WebAuthnAuth({
            authenticatorData: AUTHENTICATOR_DATA,
            clientDataJSON: clientDataJSON,
            typeIndex: TYPE_INDEX,
            challengeIndex: CHALLENGE_LOCATION,
            r: r,
            s: s
        });
    }

    function getCoinbaseWebAuthnAuth(
        bytes32 challenge,
        uint256 r,
        uint256 s
    ) internal pure returns (WebAuthn.WebAuthnAuth memory webAuthnAuth) {
        (string memory clientDataJSON, , ) = getCoinbasePasskeyMessageHash(challenge);
        webAuthnAuth = WebAuthn.WebAuthnAuth({
            authenticatorData: hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101",
            clientDataJSON: clientDataJSON,
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
        WebAuthn.WebAuthnAuth memory webAuthnAuth = getCoinbaseWebAuthnAuth(challenge, r, s);
        return WebAuthn.verify(
            abi.encode(challenge),
            false,
            webAuthnAuth,
            x,
            y
        );
    }

}
