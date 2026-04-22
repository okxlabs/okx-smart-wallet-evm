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
   
    let smartWalletImpl = await contracts.getSmartWallet(undefined, deployer);
    const helper = await contracts.getHelper(deployer);
    const ERC3009_ADDRESS = process.env.ERC3009 || "";
    const erc3009 = await hre.ethers.getContractAt(
      "ERC3009Token",
      ERC3009_ADDRESS,
      deployer
    );
    
    let aa = smartWalletImpl.attach(deployer.address);
    let expired = Math.floor(Date.now()/1000) + 3600;
    let nonce = ethers.randomBytes(32);

    const domain = {
        name: "ERC3009Token",
        version: "1",
        chainId: 196n,
        verifyingContract: ERC3009_ADDRESS
      }
      
      const types = {
        TransferWithAuthorization: [
          { name: "from",        type: "address" },
          { name: "to",          type: "address" },
          { name: "value",       type: "uint256" },
          { name: "validAfter",  type: "uint256" },
          { name: "validBefore", type: "uint256" },
          { name: "nonce",       type: "bytes32" },
        ]
      }

      const value = {
        from: deployer.address,
        to: deployer.address,
        value: 1,
        validAfter: 0,
        validBefore: expired, // 1小时有效
        nonce: nonce
      };
      
    const sigHex = await deployer.signTypedData(
        domain,
        types,
        value
    );

    // signTypedData 返回的是 hex 字符串，用 Signature.from 解析出 r, s, v
    const sig = ethers.Signature.from(sigHex);
    console.log("Signature (hex):", sigHex);
    console.log("r:", sig.r);
    console.log("s:", sig.s);
    console.log("v:", sig.v);

    const encoder = ethers.TypedDataEncoder.from(types);
    const structHash = encoder.hash(value);
    /// wallet extensions like metamask , okx sign it
      

    const bool = await erc3009.transferWithAuthorization(
      deployer.address,
      deployer.address,
      1,
      0,
      expired,
      nonce,
      sig.v,
      sig.r,
      sig.s
    );
    console.log(bool);

  } catch (error) {
    console.error("Error:", error);
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
