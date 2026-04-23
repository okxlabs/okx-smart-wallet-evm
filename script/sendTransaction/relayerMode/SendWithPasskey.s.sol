// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWalletFactory} from "src/interfaces/ISmartWalletFactory.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {InitialOwner, Call, BatchedCall} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {HelperLib} from "../utils/Helper.s.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";

/// @title SendWithPasskey
/// @notice Foundry script equivalent of SendWithPasskey.ts — relayer mode (executeWithRelayer)
contract SendWithPasskey is Script {
    // P-256 curve order, used for low-S normalisation
    uint256 constant P256_N =
        0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 constant P256_N_DIV_2 = P256_N / 2;

    uint256 constant SALT = 1100;
    uint256 constant PUB_KEY_X =
        0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a;
    uint256 constant PUB_KEY_Y =
        0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c;
    uint256 constant CHAINLESS_NONCE_KEY = 196;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 passkeyPk  = vm.envUint("PASSKEY_PRIVATE_KEY");
        address deployer   = vm.addr(deployerPk);
        address factory    = vm.envAddress("SMART_WALLET_FACTORY");
        address walletImpl = vm.envAddress("SMART_WALLET");

        console.log("Deployer:", deployer);
        console.log("Chain id:", block.chainid);

        // ── Derive user wallet ─────────────────────────────────────────────
        InitialOwner[] memory initialOwners = _buildInitialOwners(deployer);
        address userWallet = vm.envOr("USER_WALLET", address(0));
        if (userWallet == address(0)) {
            userWallet = ISmartWalletFactory(factory).getAddress(initialOwners, SALT);
        }
        console.log("User wallet:", userWallet);

        // ── Read nonce ─────────────────────────────────────────────────────
        uint256 nonce = uint256(INonceManager(userWallet).getNonce(0));
        console.log("Nonce:", nonce);

        // ── Build BatchedCall ──────────────────────────────────────────────
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: deployer, value: 1, data: bytes("")});
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: nonce});

        // ── Compute intentHash ─────────────────────────────────────────────
        bytes32 intentHash = BatchedCallLib.hash(batchedCall, 0, walletImpl);
        console.log("intentHash:");
        console.logBytes32(intentHash);

        // ── Compute typedDataHash ──────────────────────────────────────────
        bytes32 typedDataHash;
        if ((nonce >> 64) == CHAINLESS_NONCE_KEY) {
            typedDataHash = SmartWallet(payable(userWallet)).hashTypedDataSansChainId(intentHash);
        } else {
            typedDataHash = SmartWallet(payable(userWallet)).hashTypedData(intentHash);
        }
        console.log("typedDataHash:");
        console.logBytes32(typedDataHash);

        // ── Merkle proof (empty — root == leaf) ───────────────────────────
        bytes32[] memory proofs = new bytes32[](0);
        bytes32 rootHash = MerkleProof.processProof(proofs, typedDataHash);
        console.log("rootHash:");
        console.logBytes32(rootHash);

        // ── Build signature ────────────────────────────────────────────────
        bytes memory signature = _signWithPasskey(
            passkeyPk,
            initialOwners[0].keyHash,
            rootHash,
            proofs
        );

        // ── Submit ─────────────────────────────────────────────────────────
        vm.startBroadcast(deployerPk);
        if (userWallet.balance == 0) {
            (bool ok, ) = userWallet.call{value: 0.00001 ether}("");
            require(ok, "prefund failed");
        }
        ISmartWallet(userWallet).executeWithRelayer(batchedCall, signature);
        console.log("executeWithRelayer submitted successfully");
        vm.stopBroadcast();
    }

    // ── Internal helpers ───────────────────────────────────────────────────

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

    function _signWithPasskey(
        uint256 passkeyPk,
        bytes32 passkeyKeyHash,
        bytes32 rootHash,
        bytes32[] memory proofs
    ) internal view returns (bytes memory) {
        (, , bytes32 passkeyMsgHash) = HelperLib.getPasskeyMessageHash(rootHash);

        (bytes32 r, bytes32 rawS) = vm.signP256(passkeyPk, passkeyMsgHash);
        // Low-S normalisation (mirrors TS: s = rawS > N/2 ? N - rawS : rawS)
        uint256 s = uint256(rawS) > P256_N_DIV_2
            ? P256_N - uint256(rawS)
            : uint256(rawS);

        bool verified = HelperLib.webAuthnVerify(rootHash, uint256(r), s, PUB_KEY_X, PUB_KEY_Y);
        console.log("WebAuthn verify:", verified);

        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(rootHash, uint256(r), s);
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: PUB_KEY_X,
                    pubKeyY: PUB_KEY_Y
                })
            ),
            abi.encode(auth, proofs)
        );

        // signature layout: passkeyKeyHash (32) | validUntil (6) | validatorData
        return abi.encodePacked(passkeyKeyHash, uint48(0), validatorData);
    }
}
