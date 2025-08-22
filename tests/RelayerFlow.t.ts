import { expect } from "chai";
import { ethers } from "ethers";
import * as dotenv from "dotenv";
import axios from "axios";
import type { AxiosInstance, AxiosResponse } from "axios";
import fs from "fs";
import path from "path";
import crypto from "crypto";

dotenv.config();

// Test interfaces matching the contract types
interface Call {
    target: string;
    value: bigint;
    data: string;
}

interface BatchedCall {
    calls: Call[];
    nonce: bigint;
    expiry: number;
}

interface InitialOwner {
    keyHash: string;
    validator: string;
}

interface SimulateSponsorResult {
    execution_gas: number;
    total_gas: number;
    token_amount_needed: string;
    revert_reason: string;
    relayer: string;
}

interface SubmitSponsorResult {
    id: string;
    relayer_id: string;
    created_at: string;
}

interface TransactionStatusResponse {
    success: boolean;
    data: {
        id: string;
        hash: string;
        status: string;
        created_at: string;
        sent_at: string;
        confirmed_at: string;
        gas_price: number;
        gas_limit: number;
        nonce: number;
        value: string;
        from: string;
        to: string;
        relayer_id: string;
    };
    error: any;
}

export function generateSponsorTransferCalldata(
    recipient: ethers.AddressLike,
    amount: bigint
): string {
    const transferAbi = ["function transfer(address to, uint256 amount)"];
    const iface = new ethers.Interface(transferAbi);

    return iface.encodeFunctionData("transfer", [recipient, amount]);
}
export function validateEnvVariables(vars: string[]) {
    vars.forEach((variable) => {
        if (!process.env[variable]) {
            throw new Error(
                `${variable} is not defined in the environment variables.`
            );
        }
    });
}

export function loadAxiosInstance(url: string, auth: string): AxiosInstance {
    let axiosInstance = axios.create({ baseURL: url });

    axiosInstance.interceptors.request.use(
        (config) => {
            // set auth token
            config.headers["Authorization"] = `Bearer ${auth}`;
            config.headers["Content-Type"] = `application/json`;
            config.withCredentials = true;
            return config;
        },
        (error) => {
            return Promise.reject(error);
        }
    );

    return axiosInstance;
}


export function toTypedDataHash(
    domainSeparator: string,
    structHash: string
): string {
    const prefix = "0x1901";
    return ethers.keccak256(
        ethers.concat([
            ethers.getBytes(prefix),
            ethers.getBytes(domainSeparator),
            ethers.getBytes(structHash),
        ])
    );
}


export function handleAxiosResponse<T>(
    res: AxiosResponse<any>,
    isRpc: boolean = true
): T {
    if (res.status !== 200) {
        throw new Error(`Non-200 response: ${res.status}`);
    }

    if (res.data.error) {
        throw new Error(`Query error: ${res.data.error.message}`);
    }

    let result;
    if (isRpc) {
        result = res.data.result;
        if (!result) {
            throw new Error("Missing result field");
        }
    } else {
        result = res.data;
    }

    return result as T;
}

// Constants
const DEFAULT_VALIDATOR = "0x0000000000000000000000000000000000000001"; // ECDSA validator address

// Test configuration - these will be provided as variables
const RELAYER_API_URL = process.env.RELAYER_URL || "http://localhost:8080";
const RELAYER_AUTH_TOKEN = process.env.AUTHORIZATION || "";
const NETWORK = process.env.NETWORK || "localhost-example";
const ANVIL_RPC_URL = process.env.ANVIL_RPC_URL || "http://127.0.0.1:8545";

const RELAYER_ADDRESS = process.env.RELAYER_ADDRESS || "0x55f3a93f544e01ce4378d25e927d7c493b863bd6"

describe("RelayerFlow Integration Tests", function () {
    let provider: ethers.JsonRpcProvider;
    let smartWallet: any;
    let ecdsaValidator: any;
    let mockToken: any;
    let alice: ethers.Wallet;
    let bob: ethers.Wallet;
    let relayer: ethers.Wallet;
    let aliceAddress: string;
    let bobAddress: string;
    let relayerAddress: string;
    let relayerAxios: AxiosInstance;
    let chainId: bigint;
    let currentNonce: bigint;

    // EIP-712 domain and types
    let domain: any;
    const types = {
        Call: [
            { name: "target", type: "address" },
            { name: "value", type: "uint256" },
            { name: "data", type: "bytes" },
        ],
        BatchedCall: [
            { name: "calls", type: "Call[]" },
            { name: "nonce", type: "uint256" },
            { name: "expiry", type: "uint48" },
        ],
    };

    beforeEach(async function () {
        try {
            // Get the directory path for ES modules
            const currentDir = path.dirname(new URL(import.meta.url).pathname);
            
            // Reset Anvil state to ensure clean environment
            console.log("Resetting Anvil state...");
            provider = new ethers.JsonRpcProvider(ANVIL_RPC_URL);

            // Test connection
            try {
                await provider.getNetwork();
            } catch (error) {
                throw new Error(`Failed to connect to Anvil at ${ANVIL_RPC_URL}. Make sure Anvil is running.`);
            }

            // Create wallets using Anvil's default accounts
            alice = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider); // Account 0
            bob = new ethers.Wallet("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", provider);   // Account 1

            aliceAddress = alice.address;
            bobAddress = bob.address;
            relayerAddress = RELAYER_ADDRESS;

            try {
                await provider.send("anvil_setBalance", [relayerAddress, "0x" + ethers.parseEther("1000000").toString(16)]);
                await provider.send("anvil_setBalance", [aliceAddress, "0x" + ethers.parseEther("10000000").toString(16)]);
            } catch (error) {
                throw error;
            }

            // check relayer balance
            const relayerBalance = await provider.getBalance(relayerAddress);


            await provider.send("anvil_setBalance", [aliceAddress, "0x" + ethers.parseEther("1000").toString(16)]);
            const aliceBalance = await provider.getBalance(aliceAddress);


            // Verify balances were set correctly
            expect(Number(ethers.formatEther(relayerBalance))).to.be.greaterThan(999999); // Should be 1M ETH
            expect(Number(ethers.formatEther(aliceBalance))).to.be.greaterThan(999); // Should be 1K ETH

            // Get network info
            const network = await provider.getNetwork();
            chainId = network.chainId;

            // Check account balances
            const aliceBalanceCheck = await provider.getBalance(aliceAddress);

            // Get initial nonce
            let deploymentNonce = await provider.getTransactionCount(aliceAddress);

            // Load contract artifacts with error handling
            let ecdsaValidatorArtifact, smartWalletArtifact, mockERC20Artifact;

            try {
                ecdsaValidatorArtifact = JSON.parse(fs.readFileSync(path.join(currentDir, '../out/ECDSAValidator.sol/ECDSAValidator.json'), 'utf8'));
                smartWalletArtifact = JSON.parse(fs.readFileSync(path.join(currentDir, '../out/SmartWallet.sol/SmartWallet.json'), 'utf8'));
                mockERC20Artifact = JSON.parse(fs.readFileSync(path.join(currentDir, '../out/MockERC20.sol/MockERC20.json'), 'utf8'));
            } catch (error) {
                throw new Error(`Failed to load contract artifacts. Run 'forge build' first. Error: ${error.message}`);
            }

            // Deploy ECDSA Validator with explicit nonce
            const ECDSAValidatorFactory = new ethers.ContractFactory(ecdsaValidatorArtifact.abi, ecdsaValidatorArtifact.bytecode, alice);
            ecdsaValidator = await ECDSAValidatorFactory.deploy({ nonce: deploymentNonce++ });
            await ecdsaValidator.waitForDeployment();
            console.log(`ECDSAValidator deployed at: ${await ecdsaValidator.getAddress()}`);

            // Deploy SmartWallet implementation with explicit nonce
            const smartWalletFactory = new ethers.ContractFactory(smartWalletArtifact.abi, smartWalletArtifact.bytecode, alice);
            const smartWalletImpl = await smartWalletFactory.deploy({ nonce: deploymentNonce++ });
            await smartWalletImpl.waitForDeployment();
            console.log(`SmartWallet implementation deployed at: ${await smartWalletImpl.getAddress()}`);

            // Deploy SmartWalletFactory with explicit nonce
            const factoryArtifact = JSON.parse(fs.readFileSync(path.join(currentDir, '../out/SmartWalletFactory.sol/SmartWalletFactory.json'), 'utf8'));
            const FactoryFactory = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, alice);
            const factory: any = await FactoryFactory.deploy({ nonce: deploymentNonce++ });
            await factory.waitForDeployment();
            console.log(`SmartWalletFactory deployed at: ${await factory.getAddress()}`);

            // Deploy MockERC20 with explicit nonce
            const MockERC20Factory = new ethers.ContractFactory(mockERC20Artifact.abi, mockERC20Artifact.bytecode, alice);
            mockToken = await MockERC20Factory.deploy({ nonce: deploymentNonce++ });
            await mockToken.waitForDeployment();
            console.log(`MockERC20 deployed at: ${await mockToken.getAddress()}`);

            // Create Alice's wallet using the factory
            const initialOwners: InitialOwner[] = [{
                keyHash: ethers.solidityPackedKeccak256(["address"], [aliceAddress]),
                validator: await ecdsaValidator.getAddress() // Use our actual deployed validator
            }];

            const salt = 42; // Deterministic salt
            const createTx = await factory.createAccount(
                await smartWalletImpl.getAddress(),
                initialOwners,
                salt,
                { nonce: deploymentNonce++ }
            );
            const receipt = await createTx.wait();

            // Get the created wallet address from the event
            const event = receipt.logs.find((log: any) => {
                try {
                    const parsed = factory.interface.parseLog(log);
                    return parsed && parsed.name === 'AccountCreated';
                } catch {
                    return false;
                }
            });

            if (!event) {
                throw new Error("Could not find AccountCreated event");
            }

            const parsedEvent = factory.interface.parseLog(event);
            const walletAddress = parsedEvent!.args[0];
            console.log(`Alice's wallet created at: ${walletAddress}`);

            // Connect to the created wallet
            smartWallet = new ethers.Contract(walletAddress, smartWalletArtifact.abi, alice);

            // Give Alice some mock tokens for testing (using explicit nonce)
            const mintTx = await mockToken.mint(walletAddress, ethers.parseUnits("1000000", 18), { nonce: deploymentNonce++ });

            // To prevent cold storage writes
            const mintTx2 = await mockToken.mint(relayerAddress, ethers.parseUnits("100", 18), { nonce: deploymentNonce++ });
            const mintTx3 = await mockToken.mint(bobAddress, ethers.parseUnits("100", 18), { nonce: deploymentNonce++ });

            await mintTx.wait();
            await mintTx2.wait();
            await mintTx3.wait();

            console.log("Alice's wallet address", walletAddress);
            console.log("Bob address", bobAddress);

            // Initialize nonce tracking for tests (after all deployments)
            currentNonce = BigInt(await provider.getTransactionCount(aliceAddress));

            // Set up EIP-712 domain (use wallet address, not EOA address)
            domain = {
                name: "SmartWallet",
                version: "1.0.0",
                chainId: chainId,
                verifyingContract: await smartWallet.getAddress(),
            };

            // Set up relayer API client
            relayerAxios = axios.create({
                baseURL: RELAYER_API_URL,
                headers: {
                    'Authorization': `Bearer ${RELAYER_AUTH_TOKEN}`,
                    'Content-Type': 'application/json'
                },
                timeout: 30000 // 30 second timeout
            });
            console.log("Test environment setup complete");

        } catch (error) {
            console.error("BeforeEach setup failed:", error.message);
            throw error;
        }
    });

    function constructERC20TransferCall(tokenAddress: string, recipient: string, amount: bigint): Call {
        if (!recipient || recipient === "null" || recipient === "undefined") {
            throw new Error(`Invalid recipient address: ${recipient}`);
        }

        const iface = new ethers.Interface([
            "function transfer(address to, uint256 amount) returns (bool)"
        ]);
        return {
            target: tokenAddress,
            value: 0n,
            data: iface.encodeFunctionData("transfer", [recipient, amount])
        };
    }

    async function getValidationTypedHash(calls: Call[], nonce: bigint, expiry: number = 0): Promise<string> {
        try {
            const CALL_TYPEHASH = ethers.keccak256(ethers.toUtf8Bytes("Call(address target,uint256 value,bytes data)"));
            const BATCHED_CALL_TYPEHASH = ethers.keccak256(ethers.toUtf8Bytes("BatchedCall(Call[] calls,uint256 nonce,uint48 expiry)Call(address target,uint256 value,bytes data)"));

            let callsEncoded = "0x";
            for (const call of calls) {
                const callHash = ethers.keccak256(
                    ethers.AbiCoder.defaultAbiCoder().encode(
                        ["bytes32", "address", "uint256", "bytes32"],
                        [CALL_TYPEHASH, call.target, call.value, ethers.keccak256(call.data)]
                    )
                );
                callsEncoded += callHash.slice(2);
            }
            const finalCallsHash = ethers.keccak256("0x" + callsEncoded.slice(2));

            // BatchedCallLib.hash(batchedCall)
            const structHash = ethers.keccak256(
                ethers.AbiCoder.defaultAbiCoder().encode(
                    ["bytes32", "bytes32", "uint256", "uint48"],
                    [BATCHED_CALL_TYPEHASH, finalCallsHash, nonce, expiry]
                )
            );

            // Now call the contract's hashTypedData function with this struct hash
            const contractHash = await smartWallet.hashTypedData(structHash);

            return contractHash;

        } catch (error) {
            throw new Error(`Failed to get hash from contract: ${error.message}`);
        }
    }

    async function constructValidatorData(calls: Call[], nonce: bigint, expiry: number): Promise<string> {
        const hash = await getValidationTypedHash(calls, nonce, expiry);
        // Use _signingKey.sign directly to avoid Ethereum message prefix
        const sig = alice.signingKey.sign(hash);

        let signature = sig.serialized;

        const keyHash = ethers.solidityPackedKeccak256(["address"], [aliceAddress]);

        let validatorData = ethers.concat([keyHash, signature]);

        return validatorData;
    }

    function generateNonce(): bigint {
        //const crypto = require('crypto');
        const randomBytes = crypto.randomBytes(24);
        const zeroBytes = Buffer.alloc(8, 0);

        const nonceBuffer = Buffer.concat([randomBytes, zeroBytes]);
        const nonce = BigInt('0x' + nonceBuffer.toString('hex'));

        return nonce;
    }

    async function simulateGasViaRelayer(
        calls: Call[],
        tokenAddress: string,
        nonce: bigint = 0n
    ): Promise<SimulateSponsorResult> {
        const iface = new ethers.Interface(["function simulateExecuteWithRelayer(tuple(tuple(address target,uint256 value,bytes data)[] calls,uint256 nonce,uint48 expiry) batchedCall,address validator,bytes validatorData)"]);

        const batchedCall = {
            calls: calls,
            nonce: nonce, // This nonce should be using a nonce with valid key, to prevent cold storage writes
            expiry: Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
        };

        // append mock key hash to the validator data
        const keyHash = ethers.solidityPackedKeccak256(["address"], [aliceAddress]);
        const mockSignature = ethers.getBytes(
            "0x665186aa6b01d30d23f695519c5ace858b2849f42d4c44d7439f49e06ffe10ed1b954470b6234650c6c56b3b650d5a58966cc9a07f8737ea929af8fb07c3b47f1b"
        );
        const mockValidatorData = ethers.concat([keyHash, mockSignature]);

        const calldata = iface.encodeFunctionData("simulateExecuteWithRelayer", [
            batchedCall,
            DEFAULT_VALIDATOR,
            mockValidatorData,
        ]);

        // TODO; need to fix and conform to EIP
        const requestBody = {
            jsonrpc: "2.0",
            method: "relayer_getQuote",
            params: {
                calldata: calldata,
                to: await smartWallet.getAddress(),
                value: "0",
                token_address: tokenAddress,
            },
            id: 2,
        };

        try {
            const response = await relayerAxios.post(`/api/v1/relayers/${NETWORK}/rpc/paymaster`, requestBody);
            return response.data.result;
        } catch (error: any) {
            console.error("Request failed:", {
                message: error.message,
                code: error.code,
                status: error.response?.status,
                statusText: error.response?.statusText,
                data: error.response?.data
            });
            throw error;
        }
    }

    async function submitSponsorTx(
        calls: Call[],
        validationData: string,
        nonce: bigint,
        expiry: number
    ): Promise<SubmitSponsorResult> {
        const iface = new ethers.Interface(["function executeWithRelayer(tuple(tuple(address target,uint256 value,bytes data)[] calls,uint256 nonce,uint48 expiry) batchedCall,bytes validatorData)"]);

        const batchedCall = {
            calls: calls,
            nonce: nonce,
            expiry: expiry
        };

        const calldata = iface.encodeFunctionData("executeWithRelayer", [
            batchedCall,
            validationData,
        ]);

        // TODO: conform to EIP
        const requestBody = {
            jsonrpc: "2.0",
            method: "relayer_sendTransaction",
            params: {
                calldata: calldata,
                to: await smartWallet.getAddress(),
                value: "0",
            },
            id: 2,
        };

        const response = await relayerAxios.post(`/api/v1/relayers/${NETWORK}/rpc/paymaster`, requestBody);
        return response.data.result;
    }

    async function getTransactionStatus(relayerId: string, txId: string): Promise<TransactionStatusResponse> {
        const response = await relayerAxios.get(`/api/v1/relayers/${relayerId}/transactions/${txId}`);
        return response.data;
    }

    describe("simulateExecuteWithRelayer with Relayer API", function () {
        it("should simulate with relayer payment calls via API", async function () {
            const userCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                bobAddress,
                ethers.parseUnits("1", 18)
            );
            const relayerPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                ethers.parseUnits("10", 18)
            );

            const result = await simulateGasViaRelayer(
                [relayerPaymentCall, userCall],
                await mockToken.getAddress()
            );

            expect(result.execution_gas).to.be.a('number');
            expect(result.total_gas).to.be.a('number');
            expect(result.token_amount_needed).to.be.a('string');
            expect(Number(result.token_amount_needed)).to.be.greaterThan(0);
        });
    });

    describe("executeWithRelayer with Relayer API", function () {
        it("should execute successfully via relayer API", async function () {
            const calls = [
                constructERC20TransferCall(
                    await mockToken.getAddress(),
                    relayerAddress,
                    BigInt(10)
                ),
                constructERC20TransferCall(
                    await mockToken.getAddress(),
                    bobAddress,
                    BigInt(10)
                )
            ];

            const nonce = generateNonce();
            const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

            // Construct validation data
            const validatorData = await constructValidatorData(calls, nonce, expiry);

            const bobBalanceBefore = await mockToken.balanceOf(bobAddress);

            // Submit transaction via relayer API
            const submitResult = await submitSponsorTx(
                calls,
                validatorData,
                nonce,
                expiry
            );

            expect(submitResult.id).to.be.a('string');
            expect(submitResult.relayer_id).to.be.a('string');

            // Poll for transaction status
            let txStatus: TransactionStatusResponse;
            let attempts = 0;
            const maxAttempts = 30;

            do {
                await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
                txStatus = await getTransactionStatus(submitResult.relayer_id, submitResult.id);
                attempts++;
            } while ((txStatus.data.status === 'pending' || txStatus.data.status === 'submitted') && attempts < maxAttempts);

            expect(txStatus.success).to.be.true;
            expect(txStatus.data.status).to.equal('mined');

            // Verify the transaction effect
            const bobBalanceAfter = await mockToken.balanceOf(bobAddress);
            expect(bobBalanceAfter - bobBalanceBefore).to.equal(BigInt(10));
        });
    });

    describe("End-to-End Relayer Flow", function () {
        it("should complete full sponsored transaction flow", async function () {
            const calls = constructERC20TransferCall(
                await mockToken.getAddress(),
                bobAddress,
                BigInt(10)
            );

            const relayerPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                BigInt(10)
            );

            // Step 1: Simulate the transaction
            const simulationResult = await simulateGasViaRelayer(
                [relayerPaymentCall, calls],
                await mockToken.getAddress()
            );

            const newRelayerPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                BigInt(simulationResult.token_amount_needed)
            );

            // Step 2: Prepare and sign the transaction
            const allCalls = [newRelayerPaymentCall, calls];

            const nonce = generateNonce();
            const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
            const validatorData = await constructValidatorData(allCalls, nonce, expiry);

            // Step 3: Submit the transaction
            const submitResult = await submitSponsorTx(
                allCalls,
                validatorData,
                nonce,
                expiry
            );

            expect(submitResult.id).to.be.a('string');
            expect(submitResult.relayer_id).to.be.a('string');

            // Step 4: Monitor transaction status
            let txStatus: TransactionStatusResponse;
            let attempts = 0;

            do {
                await new Promise(resolve => setTimeout(resolve, 2000));
                txStatus = await getTransactionStatus(submitResult.relayer_id, submitResult.id);
                attempts++;
            } while (txStatus.data.status === 'pending' && attempts < 30);

            // Step 5: Verify successful completion
            expect(txStatus.success).to.be.true;
            expect(txStatus.data.status).to.equal('mined');
            expect(txStatus.data.hash).to.be.a('string');
        });

        it("should complete full sponsored transaction flow without any cold nonce writes", async function () {
            const calls = constructERC20TransferCall(
                await mockToken.getAddress(),
                bobAddress,
                BigInt(10)
            );

            const relayerPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                BigInt(10)
            );

            // Step 1: Simulate the transaction
            const simulationResult = await simulateGasViaRelayer(
                [relayerPaymentCall, calls],
                await mockToken.getAddress()
            );

            const newRelayerPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                BigInt(simulationResult.token_amount_needed)
            );

            const allCalls = [newRelayerPaymentCall, calls];

            const nonce = generateNonce();
            const expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
            const validatorData = await constructValidatorData(allCalls, nonce, expiry);

            // Submit once first to make the nonce non-zero
            const submitResult = await submitSponsorTx(
                allCalls,
                validatorData,
                nonce,
                expiry
            );

            let txStatus: TransactionStatusResponse;
            let attempts = 0;

            do {
                await new Promise(resolve => setTimeout(resolve, 2000));
                txStatus = await getTransactionStatus(submitResult.relayer_id, submitResult.id);
                attempts++;
            } while (txStatus.data.status === 'pending' && attempts < 30);

            // Step 5: Verify successful completion
            expect(txStatus.success).to.be.true;
            expect(txStatus.data.status).to.equal('mined');
            expect(txStatus.data.hash).to.be.a('string');

            console.log("First tx is successful");

            const key = nonce >> 64n; // Extract the upper 192 bits as the key
            const nonce2 = (key << 64n) | 1n; // Use the same key but set nonce value to 1

            const simulationResult2 = await simulateGasViaRelayer(
                [relayerPaymentCall, calls],
                await mockToken.getAddress(),
                nonce2
            );

            const newRelayerPaymentCall2 = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                BigInt(simulationResult2.token_amount_needed)
            );

            const allCalls2 = [newRelayerPaymentCall2, calls];

            const validatorData2 = await constructValidatorData(allCalls2, nonce2, expiry);
            // Step 3: Submit the transaction
            const submitResult2 = await submitSponsorTx(
                allCalls2,
                validatorData2,
                nonce2,
                expiry
            );

            do {
                await new Promise(resolve => setTimeout(resolve, 2000));
                txStatus = await getTransactionStatus(submitResult2.relayer_id, submitResult2.id);
                attempts++;
            } while (txStatus.data.status === 'pending' && attempts < 30);

            // Step 5: Verify successful completion
            expect(txStatus.success).to.be.true;
            expect(txStatus.data.status).to.equal('mined');
            expect(txStatus.data.hash).to.be.a('string');

            const txReceipt = await provider.getTransactionReceipt(txStatus.data.hash);

            console.log("Simulation gas: ", simulationResult2.total_gas);
            console.log("Transaction gas: ", txReceipt?.gasUsed);
            console.log("Difference percentage: ", Math.abs(Number(simulationResult2.total_gas) - Number(txReceipt?.gasUsed)) / Number(simulationResult2.total_gas) * 100);

            // Expect the difference to be less than 10%
            expect(Math.abs(Number(simulationResult2.total_gas) - Number(txReceipt?.gasUsed)) / Number(simulationResult2.total_gas) * 100).to.be.lessThan(10);
        });
    });
});
