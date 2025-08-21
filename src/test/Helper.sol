// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {UserOperationLib} from "account-abstraction/core/UserOperationLib.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {Utils, WebAuthnInfo} from "webauthn-sol/../test/Utils.sol";

contract Helper {
    uint256 constant CHALLENGE_LOCATION = 23;
    uint256 constant TYPE_INDEX = 1;

    using UserOperationLib for PackedUserOperation;

    function getUserOpHashWithEntryPoint(
        address entryPoint,
        uint256 chainid,
        PackedUserOperation calldata userOp
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    userOp.hash(bytes32(uint256(uint160(entryPoint)))),
                    entryPoint,
                    chainid
                )
            );
    }

    function getPubkeyHash(
        uint256 pubKeyX,
        uint256 pubKeyY
    ) public pure returns (bytes32, bytes memory) {
        bytes32 hash = keccak256(abi.encode([pubKeyX, pubKeyY]));
        bytes memory encodeHash = abi.encode(hash);
        return (hash, encodeHash);
    }

    function getBlocktimeStamp() external view returns (uint256) {
        return block.timestamp;
    }

    function getClientJson(
        string memory clientDataJSONPre,
        string memory clientDataJSONPost,
        bytes32 userOpHash
    )
        external
        pure
        returns (
            string memory clientDataJSON,
            bytes memory message,
            bytes32 messageHash
        )
    {
        string memory challengeB64url = Base64.encodeURL(
            abi.encodePacked(userOpHash)
        );

        clientDataJSON = string.concat(
            clientDataJSONPre,
            challengeB64url,
            clientDataJSONPost
        );
        bytes
            memory authenticatorData = hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000";

        bytes32 clientDataHash = sha256(bytes(clientDataJSON));

        message = bytes.concat(authenticatorData, clientDataHash);
        messageHash = sha256(message);
    }

    function getWebAuthnInfo(
        bytes32 userOpHash
    ) external pure returns (WebAuthnInfo memory) {
        return Utils.getWebAuthnStruct(userOpHash);
    }

    function getWebAuthnAuth(
        bytes32 userOpHash,
        uint256 r,
        uint256 s
    ) external pure returns (WebAuthn.WebAuthnAuth memory webAuthnAuth) {
        WebAuthnInfo memory webAuthn = Utils.getWebAuthnStruct(userOpHash);
        webAuthnAuth = WebAuthn.WebAuthnAuth({
            authenticatorData: webAuthn.authenticatorData,
            clientDataJSON: webAuthn.clientDataJSON,
            typeIndex: TYPE_INDEX,
            challengeIndex: CHALLENGE_LOCATION,
            r: r,
            s: s
        });
    }
    // /// decode the WebAuthn signature
    // (
    //     bytes memory authenticatorData,
    //     string memory clientDataJSON,
    //     uint256 responseTypeLocation,
    //     uint256 r,
    //     uint256 s,
    //     uint8 usePrecompiled
    // ) = abi.decode(
    //         userSignature,
    //         (bytes, string, uint256, uint256, uint256, uint8)
    //     );
    function encodePasskeySig(
        uint256 r,
        uint256 s,
        string memory clientDataJSON
    ) external pure returns (bytes memory) {
        bytes
            memory authenticatorData = hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000";
        ///string
        ///    memory clientDataJSON = '{"type":"webauthn.get","challenge":"gw6YFSEOxfTvfP937iQt2nslHwbUYHOoKLKBhq2RLFM","origin":"http://localhost:8000","crossOrigin":false}';
        return abi.encode(authenticatorData, clientDataJSON, TYPE_INDEX, r, s);
    }

    // function passkeyVerify(
    //     bytes32 okxHash,
    //     uint256 r,
    //     uint256 s,
    //     uint256 x,
    //     uint256 y,
    //     VerifierType verifyType,
    //     string memory clientDataJSON
    // ) external view returns (bool, uint256) {
    //     uint256 gasBefore = gasleft();
    //     bytes
    //         memory authenticatorData = hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000";
    //     ///string
    //     ///    memory clientDataJSON = '{"type":"webauthn.get","challenge":"gw6YFSEOxfTvfP937iQt2nslHwbUYHOoKLKBhq2RLFM","origin":"http://localhost:8000","crossOrigin":false}';
    //     bool verified = WebAuthn.verifySignature(
    //         abi.encodePacked(okxHash),
    //         authenticatorData,
    //         false,
    //         clientDataJSON,
    //         CHALLENGE_LOCATION,
    //         YTPE_INDEX,
    //         r,
    //         s,
    //         x,
    //         y,
    //         verifyType
    //     );
    //     uint256 gasUsed = gasBefore - gasleft();
    //     return (verified, gasUsed);
    // }

    // function verifyPasskeySignature(
    //     bytes memory challenge,
    //     bytes memory authenticatorData,
    //     string memory clientDataJSON,
    //     uint256 r,
    //     uint256 s,
    //     uint256 x,
    //     uint256 y,
    //     VerifierType verifier
    // ) external view returns (bool, uint256) {
    //     uint256 gasBefore = gasleft();
    //     bool verified = WebAuthn.verifySignature(
    //         challenge,
    //         authenticatorData,
    //         false,
    //         clientDataJSON,
    //         CHALLENGE_LOCATION,
    //         1,
    //         r,
    //         s,
    //         x,
    //         y,
    //         verifier
    //     );
    //     uint256 gasUsed = gasBefore - gasleft();
    //     return (verified, gasUsed);
    // }
}
