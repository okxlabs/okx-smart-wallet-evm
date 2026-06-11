// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

library HelperLib {
    uint256 public constant CHALLENGE_LOCATION = 23;
    uint256 public constant TYPE_INDEX = 1;

    string public constant CLIENT_DATA_JSON_PRE =
        '{"type":"webauthn.get","challenge":"';
    string public constant CLIENT_DATA_JSON_POST =
        '","origin":"https://test-saglobal.okg.com"}';
    bytes public constant AUTHENTICATOR_DATA =
        hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000";

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

    function getMerkleProofRootHash(
        bytes32[] memory proofs,
        bytes32 leaf
    ) internal pure returns (bytes32) {
        return MerkleProof.processProof(proofs, leaf);
    }
}
