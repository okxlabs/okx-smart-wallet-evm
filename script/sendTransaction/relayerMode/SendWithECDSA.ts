import { ethers } from "ethers";
import { network } from "hardhat";
import { calldataUtils, Call } from "../utils/calldata";

const hre = require("hardhat");

// ── Wallet configuration ───────────────────────────────────────────────────
const SALT = 1100n;
const PUB_KEY_X =
  "0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a";
const PUB_KEY_Y =
  "0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c";
const CHAINLESS_NONCE_KEY = 196n;

async function main() {
  const [deployer] = await hre.ethers.getSigners();

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

  console.log("SmartWallet Impl:", await smartWalletImpl.getAddress());

  // ── Build initial owners ───────────────────────────────────────────────
  const passkeyKeyHash = calldataUtils.generateKeyHashFromPubKey(PUB_KEY_X, PUB_KEY_Y);
  const ecdsaKeyHash = calldataUtils.generateKeyHashFromAddress(deployer.address);
  const initialOwners = [
    { keyHash: passkeyKeyHash, validator: "0x0000000000000000000000000000000000000002" },
    { keyHash: ecdsaKeyHash,   validator: "0x0000000000000000000000000000000000000001" },
  ];

  // ── Derive user wallet address (consistent with sendUop.ts) ───────────
  const userWallet: string =
    process.env.USER_WALLET ||
    (await factory.getFunction("getAddress")(initialOwners, SALT));
  const aa = smartWalletImpl.attach(userWallet);
  console.log("User wallet:", userWallet);

  // getNonce returns uint64 sequential for the given key.
  // Full packed nonce for key=0: (0n << 64n) | sequential = sequential
  const nonce: bigint = await aa.getNonce(0);
  console.log("Nonce:", nonce.toString());

  // ── Build calls ────────────────────────────────────────────────────────
  const calls: Call[] = [
    {
      target: deployer.address,
      value: 1n,
      data: "0x",
    },
  ];

  const batchedCall = {
    calls,
    nonce,
  };

  // ── Compute hash to sign ───────────────────────────────────────────────
  const intentHash = await helper.getBatchCallHash(
    batchedCall,
    0,
    await smartWalletImpl.getAddress()
  );
  console.log("intentHash:", intentHash);

  // Use chainless (sans-chain-id) typed data hash when nonce key is CHAINLESS_NONCE_KEY
  let typedDataHash: string;
  if ((nonce >> 64n) === CHAINLESS_NONCE_KEY) {
    typedDataHash = await smartWalletImpl.hashTypedDataSansChainId(intentHash);
  } else {
    typedDataHash = await aa.hashTypedData(intentHash);
  }
  console.log("typedDataHash:", typedDataHash);

  // ── Merkle proof (empty — root == leaf) ───────────────────────────────
  const proofs: string[] = [];
  const rootHash = await helper.getMerkleProofRootHash(proofs, typedDataHash);
  console.log("rootHash:", rootHash);

  // ── ECDSA sign (raw, no EIP-191 prefix) ───────────────────────────────
  const signerWallet = new ethers.Wallet(
    process.env.DEPLOYER_PRIVATE_KEY!,
    hre.ethers.provider
  );
  const sig = signerWallet.signingKey.sign(rootHash).serialized;

  // layout: ecdsaKeyHash (32) | validUntil (6) | sig (65)
  const signature = ethers.solidityPacked(
    ["bytes32", "uint48", "bytes"],
    [ecdsaKeyHash, 0, sig]
  );

  // ── Submit via executeWithRelayer ──────────────────────────────────────
  const tx = await aa.executeWithRelayer(batchedCall, signature);
  console.log("tx hash:", tx.hash);
  await tx.wait();
  console.log("Transaction sent:", tx.hash);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
