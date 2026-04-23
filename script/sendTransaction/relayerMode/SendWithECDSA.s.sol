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

/// @title SendWithECDSA
/// @notice Foundry script equivalent of SendWithECDSA.ts — relayer mode (executeWithRelayer)
contract SendWithECDSA is Script {
    uint256 constant SALT = 1100;
    uint256 constant PUB_KEY_X =
        0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a;
    uint256 constant PUB_KEY_Y =
        0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c;
    uint256 constant CHAINLESS_NONCE_KEY = 196;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer    = vm.addr(deployerPk);
        address factory     = vm.envAddress("SMART_WALLET_FACTORY");
        address walletImpl  = vm.envAddress("SMART_WALLET");

        console.log("Deployer:", deployer);
        console.log("Chain id:", block.chainid);

        // ── Derive user wallet ─────────────────────────────────────────────
        InitialOwner[] memory initialOwners = _buildInitialOwners(deployer);
        // USER_WALLET env var takes priority; otherwise compute from factory
        address userWallet = vm.envOr("USER_WALLET", address(0));
        if (userWallet == address(0)) {
            userWallet = ISmartWalletFactory(factory).getAddress(initialOwners, SALT);
        }
        console.log("User wallet:", userWallet);

        // ── Read nonce ─────────────────────────────────────────────────────
        // getNonce(key) returns uint64 sequential counter for that key.
        // Full packed nonce for key=0: (0 << 64) | sequential = sequential
        uint256 nonce = uint256(INonceManager(userWallet).getNonce(0));
        console.log("Nonce:", nonce);

        // ── Build BatchedCall ──────────────────────────────────────────────
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: deployer, value: 1, data: bytes("")});
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: nonce});

        // ── Compute intentHash ─────────────────────────────────────────────
        // Mirrors: helper.getBatchCallHash(batchedCall, 0, walletImpl)
        bytes32 intentHash = BatchedCallLib.hash(batchedCall, 0, walletImpl);
        console.log("intentHash:");
        console.logBytes32(intentHash);

        // ── Compute typedDataHash ──────────────────────────────────────────
        // Chainless when nonce key (upper 192 bits) == CHAINLESS_NONCE_KEY
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
        bytes memory signature = _buildSignature(deployerPk, deployer, rootHash);

        // ── Submit ─────────────────────────────────────────────────────────
        vm.startBroadcast(deployerPk);
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

    function _buildSignature(
        uint256 signerPk,
        address deployer,
        bytes32 rootHash
    ) internal pure returns (bytes memory) {
        // Raw secp256k1 sign — mirrors signerWallet.signingKey.sign(rootHash).serialized
        // No EIP-191 prefix (unlike signMessage); the validator recovers the address directly
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, rootHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // layout: ecdsaKeyHash (32) | validUntil (6) | sig (65)
        bytes32 ecdsaKeyHash = keccak256(abi.encodePacked(deployer));
        return abi.encodePacked(ecdsaKeyHash, uint48(0), sig);
    }
}
