// @ts-ignore
import ecPem from "ec-pem";
import { ethers } from "ethers";
import crypto from "crypto";

function sign(messageData: string) {
  let keyPair = ecPem(null, "prime256v1");
  keyPair.setPrivateKey(process.env.PASSKEY_PRIVATE_KEY, "hex");

  let message = Buffer.from(ethers.getBytes(messageData));

  const signer = crypto.createSign("RSA-SHA256");
  signer.update(message);
  let sigString = signer.sign(keyPair.encodePrivateKey(), "hex");

  // @ts-ignore
  const xlength = 2 * ("0x" + sigString.slice(6, 8));
  sigString = sigString.slice(8);

  const signatureArray = [BigInt("0x" + sigString.slice(0, xlength)), BigInt("0x" + sigString.slice(xlength + 4))];

  return signatureArray;
}

export const passkeySign = {
  sign,
};
