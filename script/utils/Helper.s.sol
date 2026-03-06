// SPDX-License-Identifier: UNLICENSED
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
import {BatchedCallLib, BatchedCall} from "src/libraries/BatchedCallLib.sol";
import {CallLib, Call} from "src/libraries/CallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Static} from "src/libraries/Static.sol";
import {DecodeLib} from "src/libraries/DecodeLib.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {MessageSignLib} from "src/libraries/MessageSignLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";



library HelperLib {
    uint256 public constant CHALLENGE_LOCATION = 23;
    uint256 public constant TYPE_INDEX = 1;

    string public constant CLIENT_DATA_JSON_PRE =
        '{"type":"webauthn.get","challenge":"';
    string public constant CLIENT_DATA_JSON_POST =
        '","origin":"https://test-saglobal.okg.com"}';
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

    function getValidatorDataWithProof(
        bytes32 challenge,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y,
        bytes32[] memory proofs
    ) external pure returns (bytes memory) {
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            challenge,
            r,
            s
        );
        bytes memory sig = abi.encode(auth, proofs);
        return abi.encodePacked(abi.encode(x, y), sig);
    }

    function getProxyInitCode(
        address factory,
        address implementation
    ) external pure returns (bytes memory) {
        bytes memory args = abi.encode(factory);
        return LibClone.initCodeERC1967(implementation, args);
    }

    function getProxyInitCodeHash(
        address factory,
        address implementation
    ) external pure returns (bytes32) {
        bytes memory args = abi.encode(factory);
        return LibClone.initCodeHashERC1967(implementation, args);
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

    function getUserOpHashWithUntil(
        bytes32 userOpHash,
        uint48 validUntil,
        address IMPLEMENTATION
    ) external pure returns (bytes32) {
        return MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encode(userOpHash, validUntil, IMPLEMENTATION)));
    }

    function getBatchCallHash(
        BatchedCall calldata batchedCall,
        uint48 validUntil,
        address walletImpl
    ) external view returns (bytes32) {
        return BatchedCallLib.hash(batchedCall, validUntil, walletImpl);
    }

    function getMessageLibHash(
        bytes32 _hash,
        uint48 validUntil,
        address walletImpl
    ) public pure returns (bytes32) {
        return MessageSignLib.hash(_hash, validUntil, walletImpl);
    }

    uint256 constant PASSKEY_PUBKEY_LENGTH = 64;
    function decodePasskey(
        bytes calldata sig
    )
        external
        pure
        returns (
            PasskeyValidatorLib.PasskeyPubKey memory passkeyPubKey,
            WebAuthn.WebAuthnAuth memory webAuthnAuth,
            uint256 r,
            uint256 s
        )
    {
        (bytes32 pubKeyHash, uint48 validUntil) = DecodeLib
            .decodeSignatureComponents(sig);
        bytes calldata validatorData = sig[38:];
        passkeyPubKey = abi.decode(
            validatorData[:PASSKEY_PUBKEY_LENGTH],
            (PasskeyValidatorLib.PasskeyPubKey)
        );
        bytes32[] memory proofs;
        // decode the WebAuthn authentication data from the validatorData
        (webAuthnAuth, proofs) = abi.decode(
            validatorData[PASSKEY_PUBKEY_LENGTH:],
            (WebAuthn.WebAuthnAuth, bytes32[])
        );
        r = webAuthnAuth.r;
        s = webAuthnAuth.s;
    }
}

contract EntryPointMock is EntryPoint {}
contract MockERC20 is ERC20 {
    constructor() ERC20("MockERC20", "MOCK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}

