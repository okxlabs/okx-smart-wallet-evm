// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {ISmartWalletFactory} from "src/interfaces/ISmartWalletFactory.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {InitialOwner, Call} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {HelperLib} from "./utils/Helper.s.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SendUop
/// @notice Foundry script equivalent of sendUop.ts — builds and submits a Passkey-signed UserOperation
contract SendUop is Script {
    // P-256 curve order, used for low-S normalisation
    uint256 constant P256_N =
        0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 constant P256_N_DIV_2 = P256_N / 2;

    // Wallet configuration (mirrors TS constants)
    uint256 constant SALT = 1100;
    uint256 constant PUB_KEY_X =
        0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a;
    uint256 constant PUB_KEY_Y =
        0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c;
    address constant TOKEN_ADDRESS =
        0x6250C0459A6565F904B71E2D53C3d2BbB582357c;
    // Matches CHAINLESS_NONCE_KEY = 196n in TS
    uint256 constant CHAINLESS_NONCE_KEY = 196;

    address constant ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 passkeyPk = vm.envUint("PASSKEY_PRIVATE_KEY");

        address deployer = vm.addr(deployerPk);
        address factory = vm.envAddress("SMART_WALLET_FACTORY");
        address smartWalletImpl = vm.envAddress("SMART_WALLET");

        console.log("Deployer:", deployer);
        console.log("Chain id:", block.chainid);

        IEntryPoint entrypoint = IEntryPoint(ENTRYPOINT);

        InitialOwner[] memory initialOwners = _buildInitialOwners(deployer);
        address sender = ISmartWalletFactory(factory).getAddress(
            initialOwners,
            SALT
        );
        console.log("Sender:", sender);

        bool accountExists = sender.code.length > 0;
        console.log("Account exists:", accountExists);

        uint256 nonce = entrypoint.getNonce(sender, 0);
        console.log("Nonce:", nonce);

        vm.startBroadcast(deployerPk);

        if (!accountExists) {
            (bool ok, ) = sender.call{value: 0.0001 ether}("");
            require(ok, "prefund failed");
        }

        PackedUserOperation memory userOp = _buildUserOp(
            sender,
            nonce,
            accountExists,
            factory,
            initialOwners
        );

        userOp.signature = _buildSignature(
            entrypoint,
            userOp,
            nonce,
            smartWalletImpl,
            passkeyPk,
            initialOwners[0].keyHash
        );

        _logAndSubmit(entrypoint, userOp, payable(deployer));

        vm.stopBroadcast();
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    function _buildInitialOwners(
        address deployer
    ) internal pure returns (InitialOwner[] memory initialOwners) {
        initialOwners = new InitialOwner[](2);
        // Passkey owner (validator = address(2))
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(PUB_KEY_X, PUB_KEY_Y)),
            validator: Static.PASSKEY_VALIDATOR_ADDRESS
        });
        // ECDSA owner (validator = address(1))
        initialOwners[1] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(deployer)),
            validator: Static.ECDSA_VALIDATOR_ADDRESS
        });
    }

    function _buildUserOp(
        address sender,
        uint256 nonce,
        bool accountExists,
        address factory,
        InitialOwner[] memory initialOwners
    ) internal view returns (PackedUserOperation memory userOp) {
        bytes memory initCode = accountExists
            ? bytes("")
            : abi.encodePacked(
                factory,
                abi.encodeCall(
                    ISmartWalletFactory.createAccount,
                    (initialOwners, SALT)
                )
            );
        console.log("initCode length:", initCode.length);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: TOKEN_ADDRESS,
            value: 1,
            data: new bytes(0)
        });
        bytes memory callData = abi.encodePacked(
            IERC4337Account.executeUserOp.selector,
            abi.encode(calls)
        );

        // accountGasLimits: upper 128 = verificationGasLimit (2_000_000), lower 128 = callGasLimit (400_000)
        // gasFees:          upper 128 = maxPriorityFeePerGas (1 wei),     lower 128 = maxFeePerGas (1 wei)
        userOp = PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: callData,
            accountGasLimits: bytes32(
                abi.encodePacked(uint128(2_000_000), uint128(400_000))
            ),
            preVerificationGas: 21_000,
            gasFees: bytes32(abi.encodePacked(uint128(1), uint128(1))),
            paymasterAndData: bytes(""),
            signature: bytes("")
        });
    }

    function _buildSignature(
        IEntryPoint entrypoint,
        PackedUserOperation memory userOp,
        uint256 nonce,
        address smartWalletImpl,
        uint256 passkeyPk,
        bytes32 passkeyKeyHash
    ) internal view returns (bytes memory) {
        bytes32 uopHash = _computeUopHash(
            entrypoint,
            userOp,
            nonce,
            smartWalletImpl
        );

        bytes32[] memory proofs = new bytes32[](0);
        bytes32 rootHash = MerkleProof.processProof(proofs, uopHash);

        return _signWithPasskey(passkeyPk, passkeyKeyHash, rootHash, proofs);
    }

    function _computeUopHash(
        IEntryPoint entrypoint,
        PackedUserOperation memory userOp,
        uint256 nonce,
        address smartWalletImpl
    ) internal view returns (bytes32 uopHash) {
        // Mirrors TS: if (nonce === CHAINLESS_NONCE_KEY) use chainless hash
        if (nonce == CHAINLESS_NONCE_KEY) {
            uopHash = IERC4337Account(smartWalletImpl)
                .getUserOpHashWithoutChainId(userOp);
        } else {
            uopHash = entrypoint.getUserOpHash(userOp);
        }
        // Mirrors helper.getUserOpHashWithUntil(uopHash, 0, smartWalletImpl)
        uopHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encode(uopHash, uint48(0), smartWalletImpl))
        );
    }

    function _signWithPasskey(
        uint256 passkeyPk,
        bytes32 passkeyKeyHash,
        bytes32 rootHash,
        bytes32[] memory proofs
    ) internal view returns (bytes memory) {
        (, , bytes32 passkeyMsgHash) = HelperLib.getPasskeyMessageHash(
            rootHash
        );

        (bytes32 r, bytes32 rawS) = vm.signP256(passkeyPk, passkeyMsgHash);
        // Low-S normalisation (mirrors TS: s = rawS > N/2 ? N - rawS : rawS)
        uint256 s = uint256(rawS) > P256_N_DIV_2
            ? P256_N - uint256(rawS)
            : uint256(rawS);

        bool verified = HelperLib.webAuthnVerify(
            rootHash,
            uint256(r),
            s,
            PUB_KEY_X,
            PUB_KEY_Y
        );
        console.log("WebAuthn verify:", verified);

        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            rootHash,
            uint256(r),
            s
        );
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: PUB_KEY_X,
                    pubKeyY: PUB_KEY_Y
                })
            ),
            abi.encode(auth, proofs)
        );

        // signature layout: keyHash (32) | validUntil (6) | validatorData
        return abi.encodePacked(passkeyKeyHash, uint48(0), validatorData);
    }

    function _logAndSubmit(
        IEntryPoint entrypoint,
        PackedUserOperation memory userOp,
        address payable bundler
    ) internal {
        console.log("UserOp sender:            ", userOp.sender);
        console.log("UserOp nonce:             ", userOp.nonce);
        console.log("UserOp initCode length:   ", userOp.initCode.length);
        console.log("UserOp callData length:   ", userOp.callData.length);
        console.log("UserOp preVerificationGas:", userOp.preVerificationGas);
        console.log("UserOp signature length:  ", userOp.signature.length);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        entrypoint.handleOps(ops, bundler);
    }
}
