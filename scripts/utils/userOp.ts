/**
 * User Operation utilities for okx-smart-wallet
 * Adapted from SmartAccount project for OKX architecture
 */

import { ethers } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

export interface UserOperation {
    sender: string;
    nonce: string;
    initCode: string;
    callData: string;
    accountGasLimits: string;
    preVerificationGas: string;
    gasFees: string;
    paymasterAndData: string;
    signature: string;
}

/**
 * Generate account gas limits (verificationGasLimit + callGasLimit)
 */
function generateAccountGasLimits(verificationGasLimit: number, callGasLimit: number): string {
    return ethers.solidityPacked(
        ["uint128", "uint128"],
        [
            ethers.zeroPadValue(ethers.toBeHex(verificationGasLimit), 16),
            ethers.zeroPadValue(ethers.toBeHex(callGasLimit), 16),
        ],
    );
}

/**
 * Generate gas fees (maxPriorityFeePerGas + maxFeePerGas)
 */
function generateGasFees(maxPriorityFeePerGas: bigint, maxFeePerGas: bigint): string {
    return ethers.solidityPacked(
        ["uint128", "uint128"],
        [
            ethers.zeroPadValue(ethers.toBeHex(maxPriorityFeePerGas), 16),
            ethers.zeroPadValue(ethers.toBeHex(maxFeePerGas), 16),
        ],
    );
}

/**
 * Create a complete UserOperation from parameters
 */
function createUserOperation(params: {
    sender: string;
    nonce: bigint;
    initCode?: string;
    callData?: string;
    verificationGasLimit?: number;
    callGasLimit?: number;
    maxPriorityFeePerGas?: bigint;
    maxFeePerGas?: bigint;
    preVerificationGas?: bigint;
    paymasterAndData?: string;
}): UserOperation {
    const {
        sender,
        nonce,
        initCode = "0x",
        callData = "0x",
        verificationGasLimit = 2000000,
        callGasLimit = 400000,
        maxPriorityFeePerGas = ethers.parseUnits("1", "wei"),
        maxFeePerGas = ethers.parseUnits("10", "wei"),
        preVerificationGas = 21000n,
        paymasterAndData = "0x"
    } = params;

    return {
        sender,
        nonce: ethers.toBeHex(nonce),
        initCode,
        callData,
        accountGasLimits: generateAccountGasLimits(verificationGasLimit, callGasLimit),
        preVerificationGas: ethers.toBeHex(preVerificationGas),
        gasFees: generateGasFees(maxPriorityFeePerGas, maxFeePerGas),
        paymasterAndData,
        signature: "0x"
    };
}

/**
 * Generate ECDSA signature for user operation
 * Note: This is a simplified version - for production, implement proper signature validation
 */
async function signUserOperationWithECDSA(
    userOp: UserOperation,
    signer: HardhatEthersSigner,
    entryPointAddress: string,
    chainId: bigint
): Promise<string> {
    // Create the user operation hash
    const userOpHash = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "uint256", "bytes32", "bytes32", "bytes32", "uint256", "bytes32", "bytes32"],
            [
                userOp.sender,
                userOp.nonce,
                ethers.keccak256(userOp.initCode),
                ethers.keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                ethers.keccak256(userOp.paymasterAndData)
            ]
        )
    );

    // Create the final hash with entry point and chain ID
    const finalHash = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["bytes32", "address", "uint256"],
            [userOpHash, entryPointAddress, chainId]
        )
    );

    // Sign the hash
    const signature = await signer.signMessage(ethers.getBytes(finalHash));

    // For OKX SmartWallet, we need to format the signature with keyHash prefix
    const signerAddress = await signer.getAddress();
    const keyHash = ethers.keccak256(ethers.solidityPacked(["address"], [signerAddress]));

    return ethers.solidityPacked(["bytes32", "bytes"], [keyHash, signature]);
}

export const userOpUtils = {
    generateAccountGasLimits,
    generateGasFees,
    createUserOperation,
    signUserOperationWithECDSA,
};
