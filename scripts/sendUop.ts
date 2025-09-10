/**
 * Send User Operation script for Smart Wallet
 * Migrated and adapted from SmartAccount project
 */

import { ethers } from "ethers";
import { network } from "hardhat";
import { contracts } from "./utils/contracts";
import { userOpUtils, UserOperation } from "./utils/userOp";
import { calldataUtils, Call, InitialOwner } from "./utils/calldata";

// Use require for hardhat to match project style
const hre = require('hardhat');

async function main() {
    // Get signers
    const [deployer] = await hre.ethers.getSigners();
    const bundler = deployer;

    console.log("🚀 Smart Wallet - Send User Operation");
    console.log("=========================================");
    console.log("Deployer address:", deployer.address);
    console.log("Network:", network.name);

    const chainId = (await hre.ethers.provider.getNetwork()).chainId;
    console.log("Chain ID:", chainId.toString());

    // Fund deployer for local testing
    if (chainId === 31337n) {
        await network.provider.send("hardhat_setBalance", [
            deployer.address,
            "0x1000000000000000000000000"
        ]);
        console.log("💰 Funded deployer account for local testing");
    }

    try {
        // Get contract instances
        console.log("\n📄 Loading contract instances...");
        const entrypoint = await contracts.getEntryPoint(deployer);
        const factory = await contracts.getSmartWalletFactory(deployer);
        const smartWalletImpl = await contracts.getSmartWallet(undefined, deployer);
        const ecdsaValidator = await contracts.getECDSAValidator(deployer);

        console.log("✅ Contracts loaded successfully");
        console.log("- EntryPoint:", contracts.ADDRESSES.ENTRYPOINT_ADDRESS);
        console.log("- Factory:", await factory.getAddress());
        console.log("- SmartWallet Implementation:", await smartWalletImpl.getAddress());
        console.log("- ECDSA Validator:", await ecdsaValidator.getAddress());

        // Setup wallet configuration
        console.log("\n⚙️ Setting up wallet configuration...");

        const salt = "0"; // Salt for deterministic address generation

        // Create initial owner with ECDSA validator
        const initialOwners: InitialOwner[] = [
            calldataUtils.createECDSAOwner(
                deployer.address,
                await ecdsaValidator.getAddress()
            )
        ];

        console.log("Initial owner keyHash:", initialOwners[0].keyHash);
        console.log("Initial owner validator:", initialOwners[0].validator);

        // Generate initCode and predict sender address
        console.log("\n🔍 Generating initCode and predicting sender...");
        const { sender, initCode } = await calldataUtils.generateInitCode(
            await factory.getAddress(),
            await smartWalletImpl.getAddress(),
            initialOwners,
            salt
        );

        console.log("Predicted sender address:", sender);
        console.log("InitCode length:", ethers.dataLength(initCode));

        // Check if account already exists by examining code at predicted address
        const bytecode = await hre.ethers.provider.getCode(sender);
        const accountExists = bytecode !== "0x";
        console.log("Account exists:", accountExists ? "✅ Yes" : "❌ No");
        if (accountExists) {
            console.log("Account bytecode length:", bytecode.length);
        }

        // Get nonce
        const nonce = accountExists
            ? 0n // SmartWallet has its own nonce management
            : 0n;
        console.log("Nonce:", nonce.toString());

        // Fund the account for local testing
        if (chainId === 31337n && !accountExists) {
            const tx = await deployer.sendTransaction({
                to: sender,
                value: hre.ethers.parseEther("1.0"),
            });
            await tx.wait();
            console.log("💰 Funded predicted account with 1 ETH");
        }

        // Create execution calls
        console.log("\n📝 Creating execution calls...");

        const calls: Call[] = [
            // Simple ETH transfer as an example
            calldataUtils.generateTransferCalldata(
                deployer.address,
                hre.ethers.parseEther("0.001")
            )
        ];

        console.log("Number of calls:", calls.length);
        calls.forEach((call, i) => {
            console.log(`Call ${i + 1}:`, {
                target: call.target,
                value: hre.ethers.formatEther(call.value) + " ETH",
                dataLength: hre.ethers.dataLength(call.data)
            });
        });

        // Generate execution calldata
        const executeCalldata = calldataUtils.generateExecuteCalldata(calls);
        console.log("Execute calldata length:", hre.ethers.dataLength(executeCalldata));

        // Create User Operation
        console.log("\n🔨 Creating User Operation...");
        const userOp = userOpUtils.createUserOperation({
            sender,
            nonce,
            initCode: accountExists ? "0x" : initCode,
            callData: executeCalldata,
            verificationGasLimit: 2000000,
            callGasLimit: 400000,
            maxPriorityFeePerGas: hre.ethers.parseUnits("1", "gwei"),
            maxFeePerGas: hre.ethers.parseUnits("10", "gwei"),
            preVerificationGas: 21000n
        });

        console.log("UserOp created:");
        console.log("- Sender:", userOp.sender);
        console.log("- Nonce:", userOp.nonce);
        console.log("- InitCode:", userOp.initCode === "0x" ? "None" : `${hre.ethers.dataLength(userOp.initCode)} bytes`);
        console.log("- CallData length:", hre.ethers.dataLength(userOp.callData));

        // Sign the User Operation
        console.log("\n✍️ Signing User Operation...");
        const signature = await userOpUtils.signUserOperationWithECDSA(
            userOp,
            deployer,
            contracts.ADDRESSES.ENTRYPOINT_ADDRESS,
            chainId
        );

        userOp.signature = signature;
        console.log("Signature generated, length:", hre.ethers.dataLength(signature));

        // Log final UserOperation
        console.log("\n📋 Final User Operation:");
        console.log(JSON.stringify({
            sender: userOp.sender,
            nonce: userOp.nonce,
            initCode: userOp.initCode,
            callData: userOp.callData,
            accountGasLimits: userOp.accountGasLimits,
            preVerificationGas: userOp.preVerificationGas,
            gasFees: userOp.gasFees,
            paymasterAndData: userOp.paymasterAndData,
            signature: userOp.signature,
        }, null, 2));

        console.log("\n✅ User Operation prepared successfully!");
        console.log("\n⚠️  NOTE: This script creates a UserOp but doesn't send it to EntryPoint.");
        console.log("To actually execute, you would call entrypoint.handleOps([userOp], bundler.address)");

        // Uncomment the following lines to actually send the transaction:
        console.log("\n🚀 Sending User Operation to EntryPoint...");
        const tx = await entrypoint.handleOps([userOp], bundler.address);
        await tx.wait();
        console.log("✅ Transaction sent:", tx.hash);

    } catch (error) {
        console.error("\n❌ Error occurred:");
        console.error(error);
        throw error;
    }
}

// Execute the script
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
