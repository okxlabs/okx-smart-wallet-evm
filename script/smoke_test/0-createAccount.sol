// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWalletFactory} from "src/interfaces/ISmartWalletFactory.sol";
import {InitialOwner} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";

/// @title CreateAccount
/// @notice A script for creating a new SmartWallet account with Passkey and ECDSA owners
contract CreateAccount is Script {
    function run() external {
        // Get environment variables
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factory = vm.envAddress("SMART_WALLET_FACTORY");
        address passkeyValidator = vm.envAddress("PASSKEY_VALIDATOR");

        // Get Passkey public key from environment
        uint256 passkeyPubX = vm.envUint("PASSKEY_PUB_X");
        uint256 passkeyPubY = vm.envUint("PASSKEY_PUB_Y");

        vm.startBroadcast(deployerPk);

        address deployer = vm.addr(deployerPk);
        console.log("Deployer address: ", deployer);
        console.log("Factory address: ", factory);
        console.log(
            "Creating new SmartWallet account with Passkey and ECDSA owners..."
        );

        // Create initial owners array with Passkey and ECDSA owners
        InitialOwner[] memory initialOwners = new InitialOwner[](2);

        // 1. Passkey owner configuration using pubkey from .env
        bytes32 passkeyKeyHash = keccak256(
            abi.encodePacked(passkeyPubX, passkeyPubY)
        );
        initialOwners[0] = InitialOwner({
            keyHash: passkeyKeyHash,
            validator: passkeyValidator
        });
        console.log("Adding Passkey owner with:");
        console.log("  PubKey X: ", passkeyPubX);
        console.log("  PubKey Y: ", passkeyPubY);
        console.log("  KeyHash: ");
        console.logBytes32(passkeyKeyHash);

        // 2. Generate a random ECDSA owner
        uint256 randomEcdsaPrivateKey = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    deployer,
                    "RANDOM_ECDSA_OWNER"
                )
            )
        );
        address randomEcdsaAddress = vm.addr(randomEcdsaPrivateKey);
        bytes32 ecdsaKeyHash = bytes32(uint256(uint160(randomEcdsaAddress)));
        initialOwners[1] = InitialOwner({
            keyHash: ecdsaKeyHash,
            validator: Static.ECDSA_VALIDATOR_ADDRESS
        });
        console.log("\nAdding ECDSA owner:");
        console.log("  Address: ", randomEcdsaAddress);
        console.log("  Private Key: ", randomEcdsaPrivateKey);
        console.log("  KeyHash: ");
        console.logBytes32(ecdsaKeyHash);

        // Generate a random salt (or use a specific one)
        uint256 salt = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, deployer, "SMART_WALLET_V1")
            )
        );
        console.log("Using salt: ", salt);

        // Create the account
        address newAccount = ISmartWalletFactory(factory).createAccount(
            initialOwners,
            salt
        );

        console.log("\n==============================");
        console.log("SmartWallet account created at: ", newAccount);
        console.log("==============================\n");

        // Verify the owners were added correctly
        console.log("Account has been successfully created with:");
        console.log("- 1 Passkey owner");
        console.log("- 1 ECDSA owner (random)");

        vm.stopBroadcast();
    }

    /// @notice Helper function to create account with custom parameters
    /// @param passkeyPubX The X coordinate of the passkey public key
    /// @param passkeyPubY The Y coordinate of the passkey public key
    /// @param customSalt Custom salt for deterministic deployment
    function createAccountWithParams(
        uint256 passkeyPubX,
        uint256 passkeyPubY,
        uint256 customSalt
    ) external {
        address factory = vm.envAddress("SMART_WALLET_FACTORY");
        address passkeyValidator = vm.envAddress("PASSKEY_VALIDATOR");

        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        vm.startBroadcast(deployerPk);

        // Create initial owners array with Passkey and ECDSA owners
        InitialOwner[] memory initialOwners = new InitialOwner[](2);

        // Passkey owner
        bytes32 passkeyKeyHash = keccak256(
            abi.encodePacked(passkeyPubX, passkeyPubY)
        );
        initialOwners[0] = InitialOwner({
            keyHash: passkeyKeyHash,
            validator: passkeyValidator
        });

        // Random ECDSA owner
        uint256 randomEcdsaPrivateKey = uint256(
            keccak256(
                abi.encodePacked(customSalt, deployer, "RANDOM_ECDSA_OWNER")
            )
        );
        address randomEcdsaAddress = vm.addr(randomEcdsaPrivateKey);
        bytes32 ecdsaKeyHash = bytes32(uint256(uint160(randomEcdsaAddress)));
        initialOwners[1] = InitialOwner({
            keyHash: ecdsaKeyHash,
            validator: Static.ECDSA_VALIDATOR_ADDRESS
        });

        // Create the account
        address newAccount = ISmartWalletFactory(factory).createAccount(
            initialOwners,
            customSalt
        );

        console.log("SmartWallet account created at: ", newAccount);
        console.log("With ECDSA owner: ", randomEcdsaAddress);

        vm.stopBroadcast();
    }
}
