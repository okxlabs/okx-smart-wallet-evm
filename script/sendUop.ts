import { ethers } from "ethers";
import { network } from "hardhat";
import { contracts } from "./utils/contracts";
import { userOpUtils } from "./utils/userOp";
import { calldataUtils, Call, InitialOwner } from "./utils/calldata";
import { passkeySign } from "./utils/passkeySign";

const hre = require("hardhat");

// ── P-256 curve constants ──────────────────────────────────────────────────
const P256_N =
  115792089210356248762697446949407573529996955224135760342422259061068512044369n;
const P256_N_DIV_2 = P256_N / 2n;

// ── Wallet configuration ───────────────────────────────────────────────────
const SALT = "1100";
const PUB_KEY_X =
  "0x2080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336a";
const PUB_KEY_Y =
  "0xca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c";
const TOKEN_ADDRESS = "0x6250C0459A6565F904B71E2D53C3d2BbB582357c";
const CHAINLESS_NONCE_KEY = 196n;

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

  try {
    // ── Load contracts ─────────────────────────────────────────────────────
    const entrypoint = await contracts.getEntryPoint(deployer);
    const factory = await contracts.getSmartWalletFactory(deployer);
    const smartWalletImpl = await contracts.getSmartWallet(undefined, deployer);
    const helper = await contracts.getHelper(deployer);
    const token = await hre.ethers.getContractAt(
      "MockERC20",
      TOKEN_ADDRESS,
      deployer
    );

    console.log("EntryPoint:", contracts.ADDRESSES.ENTRYPOINT_ADDRESS);
    console.log("Factory:", await factory.getAddress());
    console.log("SmartWallet Impl:", await smartWalletImpl.getAddress());

    // ── Wallet setup ───────────────────────────────────────────────────────
    const initialOwners: InitialOwner[] = [
      calldataUtils.createPasskeyOwner(
        PUB_KEY_X,
        PUB_KEY_Y,
        "0x0000000000000000000000000000000000000002"
      ),
      calldataUtils.createECDSAOwner(
        deployer.address,
        "0x0000000000000000000000000000000000000001"
      ),
    ];

    const { sender, initCode } = await calldataUtils.generateInitCode(
      await factory.getAddress(),
      initialOwners,
      SALT
    );

    console.log("Sender:", sender);
    console.log("InitCode length:", ethers.dataLength(initCode));

    const bytecode = await hre.ethers.provider.getCode(sender);
    const accountExists = bytecode !== "0x";
    console.log("Account exists:", accountExists);

    const nonce = await entrypoint.getNonce(sender, 0);
    console.log("Nonce:", nonce.toString());

    if (!accountExists) {
      const tx = await deployer.sendTransaction({
        to: sender,
        value: hre.ethers.parseEther("0.0001"),
      });
      await tx.wait();
    }

    // ── Build calldata ─────────────────────────────────────────────────────
    const calls: Call[] = [
      {
        target: token.target,
        value: 0n,
        data: "0x40c10f190000000000000000000000003bceebfcee7d45eb78ff2e24a4007ff065d96c980000000000000000000000000000000000000000000000000de0b6b3a7640000aabbccdd",
      },
    ];

    const executeCalldata = calldataUtils.generateExecuteUserOpCalldata(calls);

    // ── Create UserOp ──────────────────────────────────────────────────────
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

    // ── Sign UserOp ────────────────────────────────────────────────────────
    let uopHash = await entrypoint.getUserOpHash(userOp);
    if (nonce === CHAINLESS_NONCE_KEY) {
      uopHash = await smartWalletImpl.getUserOpHashWithoutChainId(userOp);
    }
    uopHash = await helper.getUserOpHashWithUntil(
      uopHash,
      0,
      await smartWalletImpl.getAddress()
    );

    const proofs: string[] = [];
    const rootHash = await helper.getMerkleProofRootHash(proofs, uopHash);
    const passkeyMessageHash = await helper.getPasskeyMessageHash(rootHash);

    const [sigR, rawS] = passkeySign.sign(passkeyMessageHash[1]);
    const s = rawS > P256_N_DIV_2 ? P256_N - rawS : rawS;

    const verifyResult = await helper.webAuthnVerify(
      rootHash,
      sigR,
      s,
      PUB_KEY_X,
      PUB_KEY_Y
    );
    console.log("WebAuthn verify:", verifyResult);

    const validatorData = await helper.getValidatorDataWithProof(
      rootHash,
      sigR,
      s,
      PUB_KEY_X,
      PUB_KEY_Y,
      proofs
    );

    userOp.signature = ethers.solidityPacked(
      ["bytes32", "uint48", "bytes"],
      [initialOwners[0].keyHash, 0, validatorData]
    );

    // ── Submit ─────────────────────────────────────────────────────────────
    console.log("\nUserOp:", JSON.stringify({
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

    const tx = await entrypoint.handleOps.populateTransaction([userOp], bundler.address);
    console.log("Transaction:", tx);
   // await tx.wait();
   /// console.log("Transaction sent:", tx.hash);
  } catch (error) {
    console.error("Error:", error);
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
