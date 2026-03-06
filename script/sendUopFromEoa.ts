/**
 * Send User Operation script for OKX Smart Wallet
 * Migrated and adapted from SmartAccount project
 */

import { ethers } from "ethers";
import { network } from "hardhat";
import { contracts } from "./utils/contracts";
import { userOpUtils, UserOperation } from "./utils/userOp";
import { calldataUtils, Call, InitialOwner } from "./utils/calldata";

// Use require for hardhat to match project style
const hre = require("hardhat");

async function main() {
  // Get signers
  const [deployer] = await hre.ethers.getSigners();
  const bundler = deployer;

  console.log("🚀 OKX Smart Wallet - Send User Operation");
  console.log("=========================================");
  console.log("Deployer address:", deployer.address);
  console.log("Network:", network.name);

  const chainId = (await hre.ethers.provider.getNetwork()).chainId;
  console.log("Chain ID:", chainId.toString());

  // Fund deployer for local testing
  if (chainId === 31337n) {
    await network.provider.send("hardhat_setBalance", [
      deployer.address,
      "0x1000000000000000000000000",
    ]);
    console.log("💰 Funded deployer account for local testing");
  }

  try {
    // Get contract instances
    console.log("\n📄 Loading contract instances...");
    const entrypoint = await contracts.getEntryPoint(deployer);
    const factory = await contracts.getSmartWalletFactory(deployer);
    const smartWalletImpl = await contracts.getSmartWallet(undefined, deployer);
    const helper = await contracts.getHelper(deployer);


    // let revertData =
    //   "0x220266b600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000001441413234207369676e6174757265206572726f72000000000000000000000000";
    // let revertD = entrypoint.interface.parseError(revertData);
    // console.log(revertD);
    // return;

    console.log("✅ Contracts loaded successfully");
    console.log("- EntryPoint:", contracts.ADDRESSES.ENTRYPOINT_ADDRESS);
    console.log("- Factory:", await factory.getAddress());
    console.log(
      "- SmartWallet Implementation:",
      await smartWalletImpl.getAddress()
    );
    console.log("- Helper:", await helper.getAddress());

    // Setup wallet configuration
    console.log("\n⚙️ Setting up wallet configuration...");

    const salt = "1100"; // Salt for deterministic address generation

    const pubKeyX =
      "0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a";
    const pubKeyY =
      "0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c";
    // Create initial owner with ECDSA validator
    const initialOwners: InitialOwner[] = [
      calldataUtils.createPasskeyOwner(
        pubKeyX,
        pubKeyY,
        "0x0000000000000000000000000000000000000002"
      ),
      calldataUtils.createECDSAOwner(
        deployer.address,
        "0x0000000000000000000000000000000000000001"
      ),
    ];
    console.log("Initial owner keyHash:", initialOwners[0].keyHash);
    console.log("Initial owner validator:", initialOwners[0].validator);

    // Generate initCode and predict sender address
    console.log("\n🔍 Generating initCode and predicting sender...");
    let { sender, initCode } = await calldataUtils.generateInitCode(
      await factory.getAddress(),
      initialOwners,
      salt
    );

    /// sender = deployer.address;
    // Check if account already exists by examining code at predicted address
    const bytecode = await hre.ethers.provider.getCode(sender);
    const accountExists = bytecode !== "0x";
    console.log("initCode : ", initCode);

    console.log("Account exists:", accountExists ? "✅ Yes" : "❌ No");
    if (accountExists) {
      console.log("Account bytecode length:", bytecode.length);
    }

    // Get nonce
    const nonce = await entrypoint.getNonce(sender, 0);
    console.log("Nonce:", nonce.toString());

    // Fund the account for local testing
    if (!accountExists && true) {
      const tx = await deployer.sendTransaction({
        to: sender,
        value: hre.ethers.parseEther("0.0001"),
      });
      await tx.wait();
      console.log("💰 Funded predicted account with 0.01 ETH");
    }

    // Create execution calls
    console.log("\n📝 Creating execution calls...");

    let deployerKeyHash = initialOwners[1].keyHash;
    let setting = await smartWalletImpl.packSettings(true, 0, "0x0000000000000000000000000000000000000000");
    let addOwnerCalldata = await smartWalletImpl.interface.encodeFunctionData("updateOwner", [deployerKeyHash, "0xd963bA3B7C1CA15AbF60606C9bEa4ab545cffe99", setting]);
    console.log("addOwnerCalldata : ", addOwnerCalldata);
    const calls: Call[] = [
      // Simple ETH transfer as an example
      {
        target: deployer.address ,
        value: 1n,
        data: "0x",
      },
    //   {
    //     target: sender ,
    //     value: 0n,
    //     data: addOwnerCalldata,
    //   },

    ];

    console.log("Number of calls:", calls.length);
    calls.forEach((call, i) => {
      console.log(`Call ${i + 1}:`, {
        target: call.target,
        value: hre.ethers.formatEther(call.value) + " ETH",
        dataLength: hre.ethers.dataLength(call.data),
      });
    });

    // Generate execution calldata
    const executeCalldata = calldataUtils.generateExecuteUserOpCalldata(calls);
    console.log(
      "Execute calldata length:",
      hre.ethers.dataLength(executeCalldata)
    );

    // Create User Operation
    console.log("\n🔨 Creating User Operation...");
    const userOp = userOpUtils.createUserOperation({
      sender,
      nonce,
      initCode: accountExists ? "0x" : initCode,
      callData: executeCalldata,
      verificationGasLimit: 2000000,
      callGasLimit: 400000,
      maxPriorityFeePerGas: hre.ethers.parseUnits("1", "wei"),
      maxFeePerGas: hre.ethers.parseUnits("1", "wei"),
      preVerificationGas: 21000n,
    });

    console.log("UserOp created:");
    console.log("- Sender:", userOp.sender);
    console.log("- Nonce:", userOp.nonce);
    console.log(
      "- InitCode:",
      userOp.initCode === "0x"
        ? "None"
        : `${hre.ethers.dataLength(userOp.initCode)} bytes`
    );
    console.log("- CallData length:", hre.ethers.dataLength(userOp.callData));

    // Sign the User Operation
    console.log("\n✍️ Signing User Operation...");

    // const verifyType = 1;
    let uopHash = await entrypoint.getUserOpHash(userOp);
    console.log("uopHash : ", uopHash);
    if(nonce == 196){
       uopHash = await smartWalletImpl.getUserOpHashWithoutChainId(userOp);
    }
    
    uopHash = await helper.getUserOpHashWithUntilForEOA(uopHash, 0, await smartWalletImpl.getAddress());
    // Success returns 0.
    console.log("uopHash : ", uopHash);

    let sig = await deployer.signMessage(ethers.getBytes(uopHash));
    userOp.signature = ethers.solidityPacked(
      ["bytes32","uint48", "bytes"],
      [initialOwners[1].keyHash, 0, sig]
    );
    console.log("userOp.signature : ", userOp.signature);

    // Log final UserOperation
    console.log("\n📋 Final User Operation:");
    console.log(
      JSON.stringify(
        {
          sender: userOp.sender,
          nonce: userOp.nonce,
          initCode: userOp.initCode,
          callData: userOp.callData,
          accountGasLimits: userOp.accountGasLimits,
          preVerificationGas: userOp.preVerificationGas,
          gasFees: userOp.gasFees,
          paymasterAndData: userOp.paymasterAndData,
          signature: userOp.signature,
        },
        null,
        2
      )
    );

    console.log("\n✅ User Operation prepared successfully!");
    console.log(
      "\n⚠️  NOTE: This script creates a UserOp but doesn't send it to EntryPoint."
    );
    console.log(
      "To actually execute, you would call entrypoint.handleOps([userOp], bundler.address)"
    );

    // Uncomment the following lines to actually send the transaction:
    console.log("\n🚀 Sending User Operation to EntryPoint...");

    // const txinfo = entrypoint.handleOps([userOp], bundler.address);
    // console.log("txinfo : ", txinfo);
    const tx =await entrypoint.handleOps([userOp], bundler.address);
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
