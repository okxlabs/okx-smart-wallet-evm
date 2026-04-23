// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {ISmartWalletFactory} from "src/interfaces/ISmartWalletFactory.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {InitialOwner, Call} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SendUopWithECDSA
contract SendUopWithECDSA is Script {
    // Wallet configuration (mirrors TS constants)
    uint256 constant SALT = 1100;
    uint256 constant PUB_KEY_X =
        0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a;
    uint256 constant PUB_KEY_Y =
        0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c;
    // Mirrors CHAINLESS_NONCE_KEY = 196n in TS
    uint256 constant CHAINLESS_NONCE_KEY = 196;

    address constant ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
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

        // Prefund sender when account does not yet exist
        if (!accountExists) {
            (bool ok, ) = sender.call{value: 0.0001 ether}("");
            require(ok, "prefund failed");
        }

        PackedUserOperation memory userOp = _buildUserOp(
            sender,
            nonce,
            accountExists,
            factory,
            initialOwners,
            deployer
        );

        userOp.signature = _buildEoaSignature(
            entrypoint,
            userOp,
            nonce,
            smartWalletImpl,
            deployerPk,
            // ECDSA owner is initialOwners[1]
            initialOwners[1].keyHash
        );

        console.log("UserOp signature length:", userOp.signature.length);

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
        // ECDSA owner (validator = address(1)) — keyHash = keccak256(abi.encodePacked(address))
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
        InitialOwner[] memory initialOwners,
        address deployer
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

        // Simple ETH transfer to deployer (mirrors TS: target=deployer, value=1, data="0x")
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: deployer, value: 1, data: bytes("")});

        bytes memory callData = abi.encodePacked(
            IERC4337Account.executeUserOp.selector,
            abi.encode(calls)
        );
        console.log("callData length:", callData.length);

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

    function _buildEoaSignature(
        IEntryPoint entrypoint,
        PackedUserOperation memory userOp,
        uint256 nonce,
        address smartWalletImpl,
        uint256 signerPk,
        bytes32 ecdsaKeyHash
    ) internal view returns (bytes memory) {
        // Mirrors TS: if (nonce === CHAINLESS_NONCE_KEY) use chainless hash
        bytes32 rawUopHash;
        if (nonce == CHAINLESS_NONCE_KEY) {
            rawUopHash = IERC4337Account(smartWalletImpl)
                .getUserOpHashWithoutChainId(userOp);
        } else {
            rawUopHash = entrypoint.getUserOpHash(userOp);
        }
        console.log("rawUopHash:");
        console.logBytes32(rawUopHash);

        // Mirrors helper.getUserOpHashWithUntilForEOA(uopHash, 0, impl)
        // = keccak256(abi.encode(uopHash, validUntil, impl))  — no EIP-191 prefix here
        bytes32 uopHashForEoa = keccak256(
            abi.encode(rawUopHash, uint48(0), smartWalletImpl)
        );
        console.log("uopHashForEoa:");
        console.logBytes32(uopHashForEoa);

        // Mirrors deployer.signMessage(ethers.getBytes(uopHash))
        // ethers signMessage applies EIP-191 prefix, so we do the same before vm.sign
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(
            uopHashForEoa
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, ethSignedHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // signature layout: ecdsaKeyHash (32) | validUntil (6) | sig (65)
        return abi.encodePacked(ecdsaKeyHash, uint48(0), sig);
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

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        entrypoint.handleOps(ops, bundler);
        console.log("handleOps submitted successfully");
    }
}
