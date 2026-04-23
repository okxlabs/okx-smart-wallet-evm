import { ethers } from "ethers";
import { network } from "hardhat";
import { userOpUtils } from "../utils/userOp";
import { calldataUtils, Call } from "../utils/calldata";

const hre = require("hardhat");

// ── Wallet configuration ───────────────────────────────────────────────────
const SALT = 1100n;
const PUB_KEY_X =
  "0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a";
const PUB_KEY_Y =
  "0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c";
const CHAINLESS_NONCE_KEY = 196n;
const ENTRYPOINT =
  process.env.ENTRY_POINT || "0x0000000071727De22E5E9d8BAf0edAc6f37da032";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const bundler = deployer;

  console.log("Deployer:", deployer.address);
  console.log("Network:", network.name);

  const { chainId } = await hre.ethers.provider.getNetwork();
  console.log("Chain ID:", chainId.toString());

  if (chainId === 31337n) {
    await network.provider.send("hardhat_setBalance", [
      deployer.address,
      "0x1000000000000000000000000",
    ]);
  }

  // ── Load contracts ─────────────────────────────────────────────────────
  const entrypoint = await hre.ethers.getContractAt(
    "account-abstraction/core/EntryPoint.sol:EntryPoint",
    ENTRYPOINT,
    deployer
  );
  const factory = await hre.ethers.getContractAt(
    "SmartWalletFactory",
    process.env.SMART_WALLET_FACTORY!,
    deployer
  );
  const smartWalletImpl = await hre.ethers.getContractAt(
    "SmartWallet",
    process.env.SMART_WALLET!,
    deployer
  );
  const helper = await hre.ethers.getContractAt(
    "Helper",
    process.env.HELPER!,
    deployer
  );

  console.log("EntryPoint:", await entrypoint.getAddress());
  console.log("Factory:", await factory.getAddress());
  console.log("SmartWallet Impl:", await smartWalletImpl.getAddress());

  // ── Build initial owners ───────────────────────────────────────────────
  const passkeyKeyHash = calldataUtils.generateKeyHashFromPubKey(PUB_KEY_X, PUB_KEY_Y);
  const ecdsaKeyHash = calldataUtils.generateKeyHashFromAddress(deployer.address);
  const initialOwners = [
    { keyHash: passkeyKeyHash, validator: "0x0000000000000000000000000000000000000002" },
    { keyHash: ecdsaKeyHash,   validator: "0x0000000000000000000000000000000000000001" },
  ];

  // ── Predict sender address ─────────────────────────────────────────────
  const sender: string = await factory.getFunction("getAddress")(initialOwners, SALT);
  console.log("Sender:", sender);

  const accountExists = (await hre.ethers.provider.getCode(sender)) !== "0x";
  console.log("Account exists:", accountExists);

  const nonce = await entrypoint.getNonce(sender, 0);
  console.log("Nonce:", nonce.toString());

  // ── Prefund sender if account does not yet exist ───────────────────────
  if (!accountExists) {
    const tx = await deployer.sendTransaction({
      to: sender,
      value: hre.ethers.parseEther("0.0001"),
    });
    await tx.wait();
  }

  // ── Build initCode ─────────────────────────────────────────────────────
  const factoryCalldata = factory.interface.encodeFunctionData("createAccount", [
    initialOwners,
    SALT,
  ]);
  const initCode = accountExists
    ? "0x"
    : ethers.solidityPacked(
        ["address", "bytes"],
        [await factory.getAddress(), factoryCalldata]
      );
  console.log("initCode length:", ethers.dataLength(initCode));

  // ── Build calldata (simple ETH transfer to deployer) ──────────────────
  const calls: Call[] = [
    {
      target: deployer.address,
      value: 1n,
      data: "0x",
    },
  ];
  const executeCalldata = calldataUtils.generateExecuteUserOpCalldata(calls);

  // ── Create UserOp ──────────────────────────────────────────────────────
  const userOp = userOpUtils.createUserOperation({
    sender,
    nonce,
    initCode,
    callData: executeCalldata,
    verificationGasLimit: 2000000,
    callGasLimit: 400000,
    maxPriorityFeePerGas: 1n,
    maxFeePerGas: 1n,
    preVerificationGas: 21000n,
  });

  // ── Compute userOpHash ─────────────────────────────────────────────────
  let uopHash = await entrypoint.getUserOpHash(userOp);
  if (nonce === CHAINLESS_NONCE_KEY) {
    uopHash = await smartWalletImpl.getUserOpHashWithoutChainId(userOp);
  }
  // getUserOpHashWithUntilForEOA = keccak256(abi.encode(hash, validUntil, impl))
  // signMessage then applies EIP-191 prefix on top
  uopHash = await helper.getUserOpHashWithUntilForEOA(
    uopHash,
    0,
    await smartWalletImpl.getAddress()
  );
  console.log("uopHash:", uopHash);

  // ── EOA sign ───────────────────────────────────────────────────────────
  // deployer.signMessage applies EIP-191 prefix to the 32-byte hash
  const sig = await deployer.signMessage(ethers.getBytes(uopHash));

  // layout: ecdsaKeyHash (32) | validUntil (6) | sig (65)
  userOp.signature = ethers.solidityPacked(
    ["bytes32", "uint48", "bytes"],
    [ecdsaKeyHash, 0, sig]
  );

  // ── Submit ─────────────────────────────────────────────────────────────
  console.log("\nUserOp:", JSON.stringify({
    sender:             userOp.sender,
    nonce:              userOp.nonce,
    initCode:           userOp.initCode,
    callData:           userOp.callData,
    accountGasLimits:   userOp.accountGasLimits,
    preVerificationGas: userOp.preVerificationGas,
    gasFees:            userOp.gasFees,
    paymasterAndData:   userOp.paymasterAndData,
    signature:          userOp.signature,
  }, null, 2));

  const tx = await entrypoint.handleOps([userOp], bundler.address);
  await tx.wait();
  console.log("Transaction sent:", tx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
