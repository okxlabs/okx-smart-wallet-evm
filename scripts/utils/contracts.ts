/**
 * Contract instance helper functions for okx-smart-wallet
 * Adapted from SmartAccount project to work with OKX architecture
 */

import { ethers } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

// Use require for hardhat to match project style
const hre = require('hardhat');

// Contract addresses - update these based on your deployment
const ADDRESSES = {
    // Use deployed EntryPoint address from environment
    ENTRYPOINT_ADDRESS: process.env.ENTRY_POINT || "0x0000000071727De22E5E9d8BAf0edAc6f37da032",

    // These should be set via environment variables or deployment artifacts
    SMART_WALLET_FACTORY: process.env.SMART_WALLET_FACTORY || "",
    SMART_WALLET_IMPL: process.env.SMART_WALLET_IMPL || "",
    ECDSA_VALIDATOR: process.env.ECDSA_VALIDATOR || "",
    PASSKEY_VALIDATOR: process.env.PASSKEY_VALIDATOR || "",

    // Test token for experiments
    TEST_TOKEN: process.env.TEST_TOKEN || "",
};

/**
 * Get EntryPoint contract instance
 */
async function getEntryPoint(signer?: SignerWithAddress) {
    const entrypoint = await hre.ethers.getContractAt(
        "account-abstraction/core/EntryPoint.sol:EntryPoint", // Use the actual EntryPoint contract
        ADDRESSES.ENTRYPOINT_ADDRESS,
        signer,
    );
    return entrypoint;
}

/**
 * Get SmartWalletFactory contract instance
 */
async function getSmartWalletFactory(signer?: SignerWithAddress) {
    if (!ADDRESSES.SMART_WALLET_FACTORY) {
        throw new Error("SMART_WALLET_FACTORY address not set");
    }
    const factory = await hre.ethers.getContractAt("SmartWalletFactory", ADDRESSES.SMART_WALLET_FACTORY, signer);
    return factory;
}

/**
 * Get SmartWallet contract instance
 */
async function getSmartWallet(address?: string, signer?: SignerWithAddress) {
    const walletAddress = address || ADDRESSES.SMART_WALLET_IMPL;
    if (!walletAddress) {
        throw new Error("SmartWallet address not provided and SMART_WALLET_IMPL not set");
    }
    const smartWallet = await hre.ethers.getContractAt("SmartWallet", walletAddress, signer);
    return smartWallet;
}

/**
 * Get ECDSAValidator contract instance
 */
async function getECDSAValidator(signer?: SignerWithAddress) {
    if (!ADDRESSES.ECDSA_VALIDATOR) {
        throw new Error("ECDSA_VALIDATOR address not set");
    }
    const validator = await hre.ethers.getContractAt("ECDSAValidator", ADDRESSES.ECDSA_VALIDATOR, signer);
    return validator;
}

/**
 * Get PasskeyValidator contract instance
 */
async function getPasskeyValidator(signer?: SignerWithAddress) {
    if (!ADDRESSES.PASSKEY_VALIDATOR) {
        throw new Error("PASSKEY_VALIDATOR address not set");
    }
    const validator = await hre.ethers.getContractAt("PasskeyValidator", ADDRESSES.PASSKEY_VALIDATOR, signer);
    return validator;
}

/**
 * Get test ERC20 token contract instance
 */
async function getTestToken(signer?: SignerWithAddress) {
    if (!ADDRESSES.TEST_TOKEN) {
        throw new Error("TEST_TOKEN address not set");
    }
    const token = await hre.ethers.getContractAt("MockERC20", ADDRESSES.TEST_TOKEN, signer);
    return token;
}

export const contracts = {
    getEntryPoint,
    getSmartWalletFactory,
    getSmartWallet,
    getECDSAValidator,
    getPasskeyValidator,
    getTestToken,
    ADDRESSES,
};
