import { expect } from "chai";
import { ethers } from "ethers";
import { Signer } from "ethers";
import * as dotenv from "dotenv";
import axios, { AxiosInstance, AxiosResponse } from "axios";

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

export const ABI = [
    {
        "type": "constructor",
        "inputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "fallback",
        "stateMutability": "payable"
    },
    {
        "type": "receive",
        "stateMutability": "payable"
    },
    {
        "type": "function",
        "name": "CUSTOM_STORAGE_ROOT",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "IMPLEMENTATION",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "_nonces",
        "inputs": [
            {
                "name": "",
                "type": "uint192",
                "internalType": "uint192"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "uint64",
                "internalType": "uint64"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "addValidator",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "internalType": "bytes32"
            },
            {
                "name": "validator",
                "type": "address",
                "internalType": "address"
            },
            {
                "name": "adminFlag",
                "type": "bool",
                "internalType": "bool"
            },
            {
                "name": "expiration",
                "type": "uint40",
                "internalType": "uint40"
            },
            {
                "name": "hook",
                "type": "address",
                "internalType": "address"
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "eip712Domain",
        "inputs": [],
        "outputs": [
            {
                "name": "fields",
                "type": "bytes1",
                "internalType": "bytes1"
            },
            {
                "name": "name",
                "type": "string",
                "internalType": "string"
            },
            {
                "name": "version",
                "type": "string",
                "internalType": "string"
            },
            {
                "name": "chainId",
                "type": "uint256",
                "internalType": "uint256"
            },
            {
                "name": "verifyingContract",
                "type": "address",
                "internalType": "address"
            },
            {
                "name": "salt",
                "type": "bytes32",
                "internalType": "bytes32"
            },
            {
                "name": "extensions",
                "type": "uint256[]",
                "internalType": "uint256[]"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "entryPoint",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "pure"
    },
    {
        "type": "function",
        "name": "execute",
        "inputs": [
            {
                "name": "calls",
                "type": "tuple[]",
                "internalType": "struct Call[]",
                "components": [
                    {
                        "name": "target",
                        "type": "address",
                        "internalType": "address"
                    },
                    {
                        "name": "value",
                        "type": "uint256",
                        "internalType": "uint256"
                    },
                    {
                        "name": "data",
                        "type": "bytes",
                        "internalType": "bytes"
                    }
                ]
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "executeWithRelayer",
        "inputs": [
            {
                "name": "batchedCall",
                "type": "tuple",
                "internalType": "struct BatchedCall",
                "components": [
                    {
                        "name": "calls",
                        "type": "tuple[]",
                        "internalType": "struct Call[]",
                        "components": [
                            {
                                "name": "target",
                                "type": "address",
                                "internalType": "address"
                            },
                            {
                                "name": "value",
                                "type": "uint256",
                                "internalType": "uint256"
                            },
                            {
                                "name": "data",
                                "type": "bytes",
                                "internalType": "bytes"
                            }
                        ]
                    },
                    {
                        "name": "nonce",
                        "type": "uint256",
                        "internalType": "uint256"
                    },
                    {
                        "name": "expiry",
                        "type": "uint48",
                        "internalType": "uint48"
                    }
                ]
            },
            {
                "name": "validatorData",
                "type": "bytes",
                "internalType": "bytes"
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "getAllValidatorKeys",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "bytes32[]",
                "internalType": "bytes32[]"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getExpiration",
        "inputs": [
            {
                "name": "settings",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "uint40",
                "internalType": "uint40"
            }
        ],
        "stateMutability": "pure"
    },
    {
        "type": "function",
        "name": "getHook",
        "inputs": [
            {
                "name": "settings",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "pure"
    },
    {
        "type": "function",
        "name": "getNonce",
        "inputs": [
            {
                "name": "key",
                "type": "uint192",
                "internalType": "uint192"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "uint64",
                "internalType": "uint64"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getValidatorAt",
        "inputs": [
            {
                "name": "index",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getValidatorCount",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getValidatorSettings",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "validator",
                "type": "address",
                "internalType": "address"
            },
            {
                "name": "hook",
                "type": "address",
                "internalType": "address"
            },
            {
                "name": "expiration",
                "type": "uint40",
                "internalType": "uint40"
            },
            {
                "name": "adminStatus",
                "type": "bool",
                "internalType": "bool"
            },
            {
                "name": "expired",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getVerifiedValidator",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "hasValidator",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "hashTypedData",
        "inputs": [
            {
                "name": "structHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "digest",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "hashTypedDataSansChainId",
        "inputs": [
            {
                "name": "structHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "digest",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "initialize",
        "inputs": [
            {
                "name": "initialOwners",
                "type": "tuple[]",
                "internalType": "struct InitialOwner[]",
                "components": [
                    {
                        "name": "keyHash",
                        "type": "bytes32",
                        "internalType": "bytes32"
                    },
                    {
                        "name": "validator",
                        "type": "address",
                        "internalType": "address"
                    }
                ]
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "isAdmin",
        "inputs": [
            {
                "name": "settings",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "pure"
    },
    {
        "type": "function",
        "name": "isSettingsExpired",
        "inputs": [
            {
                "name": "settings",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "isValidSignature",
        "inputs": [
            {
                "name": "_hash",
                "type": "bytes32",
                "internalType": "bytes32"
            },
            {
                "name": "signature",
                "type": "bytes",
                "internalType": "bytes"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "bytes4",
                "internalType": "bytes4"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "namespaceAndVersion",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "string",
                "internalType": "string"
            }
        ],
        "stateMutability": "pure"
    },
    {
        "type": "function",
        "name": "ownerSettings",
        "inputs": [
            {
                "name": "",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "ownerValidators",
        "inputs": [
            {
                "name": "",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "packSettings",
        "inputs": [
            {
                "name": "adminFlag",
                "type": "bool",
                "internalType": "bool"
            },
            {
                "name": "expiration",
                "type": "uint40",
                "internalType": "uint40"
            },
            {
                "name": "hook",
                "type": "address",
                "internalType": "address"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "pure"
    },
    {
        "type": "function",
        "name": "removeValidator",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "simulateExecuteWithRelayer",
        "inputs": [
            {
                "name": "batchedCall",
                "type": "tuple",
                "internalType": "struct BatchedCall",
                "components": [
                    {
                        "name": "calls",
                        "type": "tuple[]",
                        "internalType": "struct Call[]",
                        "components": [
                            {
                                "name": "target",
                                "type": "address",
                                "internalType": "address"
                            },
                            {
                                "name": "value",
                                "type": "uint256",
                                "internalType": "uint256"
                            },
                            {
                                "name": "data",
                                "type": "bytes",
                                "internalType": "bytes"
                            }
                        ]
                    },
                    {
                        "name": "nonce",
                        "type": "uint256",
                        "internalType": "uint256"
                    },
                    {
                        "name": "expiry",
                        "type": "uint48",
                        "internalType": "uint48"
                    }
                ]
            },
            {
                "name": "validatorData",
                "type": "bytes",
                "internalType": "bytes"
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "simulateRelayerExecution",
        "inputs": [
            {
                "name": "batchedCall",
                "type": "tuple",
                "internalType": "struct BatchedCall",
                "components": [
                    {
                        "name": "calls",
                        "type": "tuple[]",
                        "internalType": "struct Call[]",
                        "components": [
                            {
                                "name": "target",
                                "type": "address",
                                "internalType": "address"
                            },
                            {
                                "name": "value",
                                "type": "uint256",
                                "internalType": "uint256"
                            },
                            {
                                "name": "data",
                                "type": "bytes",
                                "internalType": "bytes"
                            }
                        ]
                    },
                    {
                        "name": "nonce",
                        "type": "uint256",
                        "internalType": "uint256"
                    },
                    {
                        "name": "expiry",
                        "type": "uint48",
                        "internalType": "uint48"
                    }
                ]
            },
            {
                "name": "validatorData",
                "type": "bytes",
                "internalType": "bytes"
            }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "supportsInterface",
        "inputs": [
            {
                "name": "interfaceId",
                "type": "bytes4",
                "internalType": "bytes4"
            }
        ],
        "outputs": [
            {
                "name": "",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "validateUserOp",
        "inputs": [
            {
                "name": "userOp",
                "type": "tuple",
                "internalType": "struct PackedUserOperation",
                "components": [
                    {
                        "name": "sender",
                        "type": "address",
                        "internalType": "address"
                    },
                    {
                        "name": "nonce",
                        "type": "uint256",
                        "internalType": "uint256"
                    },
                    {
                        "name": "initCode",
                        "type": "bytes",
                        "internalType": "bytes"
                    },
                    {
                        "name": "callData",
                        "type": "bytes",
                        "internalType": "bytes"
                    },
                    {
                        "name": "accountGasLimits",
                        "type": "bytes32",
                        "internalType": "bytes32"
                    },
                    {
                        "name": "preVerificationGas",
                        "type": "uint256",
                        "internalType": "uint256"
                    },
                    {
                        "name": "gasFees",
                        "type": "bytes32",
                        "internalType": "bytes32"
                    },
                    {
                        "name": "paymasterAndData",
                        "type": "bytes",
                        "internalType": "bytes"
                    },
                    {
                        "name": "signature",
                        "type": "bytes",
                        "internalType": "bytes"
                    }
                ]
            },
            {
                "name": "userOpHash",
                "type": "bytes32",
                "internalType": "bytes32"
            },
            {
                "name": "missingAccountFunds",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [
            {
                "name": "validationData",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "nonpayable"
    },
    {
        "type": "event",
        "name": "ExecuteSuccessEvent",
        "inputs": [
            {
                "name": "callHash",
                "type": "bytes32",
                "indexed": true,
                "internalType": "bytes32"
            },
            {
                "name": "sender",
                "type": "address",
                "indexed": false,
                "internalType": "address"
            },
            {
                "name": "nonce",
                "type": "uint256",
                "indexed": false,
                "internalType": "uint256"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "Initialized",
        "inputs": [
            {
                "name": "version",
                "type": "uint64",
                "indexed": false,
                "internalType": "uint64"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "NonceConsumed",
        "inputs": [
            {
                "name": "key",
                "type": "uint192",
                "indexed": false,
                "internalType": "uint192"
            },
            {
                "name": "nonce",
                "type": "uint64",
                "indexed": false,
                "internalType": "uint64"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "StorageCreated",
        "inputs": [
            {
                "name": "storageAddress",
                "type": "address",
                "indexed": false,
                "internalType": "address"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "StorageInitialized",
        "inputs": [],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "ValidatorAdded",
        "inputs": [
            {
                "name": "validator",
                "type": "address",
                "indexed": false,
                "internalType": "address"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "ValidatorRemoved",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "indexed": false,
                "internalType": "bytes32"
            }
        ],
        "anonymous": false
    },
    {
        "type": "error",
        "name": "ExpiryPassed",
        "inputs": [
            {
                "name": "expiry",
                "type": "uint48",
                "internalType": "uint48"
            }
        ]
    },
    {
        "type": "error",
        "name": "IndexOutOfBounds",
        "inputs": []
    },
    {
        "type": "error",
        "name": "InvalidInitialization",
        "inputs": []
    },
    {
        "type": "error",
        "name": "InvalidKeyHash",
        "inputs": [
            {
                "name": "keyHash",
                "type": "bytes32",
                "internalType": "bytes32"
            }
        ]
    },
    {
        "type": "error",
        "name": "InvalidNonce",
        "inputs": [
            {
                "name": "nonce",
                "type": "uint256",
                "internalType": "uint256"
            }
        ]
    },
    {
        "type": "error",
        "name": "InvalidSignature",
        "inputs": []
    },
    {
        "type": "error",
        "name": "InvalidValidatorImpl",
        "inputs": [
            {
                "name": "validatorImpl",
                "type": "address",
                "internalType": "address"
            }
        ]
    },
    {
        "type": "error",
        "name": "NonAdminSelfCall",
        "inputs": []
    },
    {
        "type": "error",
        "name": "NotEntryPoint",
        "inputs": []
    },
    {
        "type": "error",
        "name": "NotFromSelf",
        "inputs": []
    },
    {
        "type": "error",
        "name": "NotInitializing",
        "inputs": []
    },
    {
        "type": "error",
        "name": "SimulateExecution",
        "inputs": [
            {
                "name": "executionGas",
                "type": "uint256",
                "internalType": "uint256"
            },
            {
                "name": "totalGas",
                "type": "uint256",
                "internalType": "uint256"
            },
            {
                "name": "errorData",
                "type": "bytes",
                "internalType": "bytes"
            }
        ]
    },
    {
        "type": "error",
        "name": "ValidatorAlreadyExists",
        "inputs": []
    }
];

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


export function loadAbi(): ethers.InterfaceAbi {
    return ABI as ethers.InterfaceAbi;
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

const RELAYER_ADDRESS = process.env.RELAYER_ADDRESS || "0x55f3a93f544e01ce4378d25e927d7c493b863bd6" // Default to Anvil account 1

describe("RelayerFlow Integration Tests", function () {
    let provider: ethers.JsonRpcProvider;
    let walletCore: any;
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
        Calls: [
            { name: 'wallet', type: 'address' },
            { name: 'nonce', type: 'uint256' },
            { name: 'executionGas', type: 'uint256' },
            { name: 'relayerCalls', type: 'Call[]' },
            { name: 'calls', type: 'Call[]' },
        ],
    };

    beforeEach(async function () {
        try {
            console.log("Setting up test environment...");

            // Reset Anvil state to ensure clean environment
            console.log("Resetting Anvil state...");
            provider = new ethers.JsonRpcProvider(ANVIL_RPC_URL);

            // Test connection
            try {
                await provider.getNetwork();
                console.log("Connected to Anvil");
            } catch (error) {
                throw new Error(`Failed to connect to Anvil at ${ANVIL_RPC_URL}. Make sure Anvil is running.`);
            }

            // // Reset Anvil to clean state
            // try {
            //     await provider.send("anvil_reset", []);
            //     console.log("Anvil state reset");
            // } catch (error) {
            //     console.log("Could not reset Anvil state, continuing...");
            // }

            // Create wallets using Anvil's default accounts
            alice = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider); // Account 0
            bob = new ethers.Wallet("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", provider);   // Account 1

            aliceAddress = alice.address;
            bobAddress = bob.address;
            relayerAddress = RELAYER_ADDRESS;

            // give 1000 ether to relayer (after address is set)
            console.log(`Setting balance for relayer: ${relayerAddress}`);
            try {
                await provider.send("anvil_setBalance", [relayerAddress, "0x" + ethers.parseEther("1000000").toString(16)]);
                console.log("anvil_setBalance call successful");
            } catch (error) {
                console.error("anvil_setBalance failed:", error);
                throw error;
            }

            // check relayer balance
            const relayerBalance = await provider.getBalance(relayerAddress);
            console.log(`Relayer balance: ${ethers.formatEther(relayerBalance)} ETH`);

            // Also give Alice some ETH for gas
            console.log(`Setting balance for Alice: ${aliceAddress}`);
            await provider.send("anvil_setBalance", [aliceAddress, "0x" + ethers.parseEther("1000").toString(16)]);
            const aliceBalance = await provider.getBalance(aliceAddress);
            console.log(`Alice balance: ${ethers.formatEther(aliceBalance)} ETH`);

            // Verify balances were set correctly
            expect(Number(ethers.formatEther(relayerBalance))).to.be.greaterThan(999999); // Should be 1M ETH
            expect(Number(ethers.formatEther(aliceBalance))).to.be.greaterThan(999); // Should be 1K ETH

            console.log(`Alice: ${aliceAddress}`);
            console.log(`Bob: ${bobAddress}`);
            console.log(`Relayer: ${relayerAddress}`);

            // Get network info
            const network = await provider.getNetwork();
            chainId = network.chainId;
            console.log(`Chain ID: ${chainId}`);

            // Check account balances
            const aliceBalanceCheck = await provider.getBalance(aliceAddress);
            console.log(`Alice balance: ${ethers.formatEther(aliceBalanceCheck)} ETH`);

            // Get initial nonce
            let deploymentNonce = await provider.getTransactionCount(aliceAddress);
            console.log(`Initial deployment nonce: ${deploymentNonce}`);

            // Load contract artifacts with error handling
            const fs = require('fs');
            const path = require('path');

            console.log("Loading contract artifacts...");

            let ecdsaValidatorArtifact, walletCoreArtifact, mockERC20Artifact;

            try {
                ecdsaValidatorArtifact = JSON.parse(fs.readFileSync(path.join(__dirname, '../out/ECDSAValidator.sol/ECDSAValidator.json'), 'utf8'));
                walletCoreArtifact = JSON.parse(fs.readFileSync(path.join(__dirname, '../out/WalletCore.sol/WalletCore.json'), 'utf8'));
                mockERC20Artifact = JSON.parse(fs.readFileSync(path.join(__dirname, '../out/MockERC20.sol/MockERC20.json'), 'utf8'));
                console.log("Contract artifacts loaded");
            } catch (error) {
                throw new Error(`Failed to load contract artifacts. Run 'forge build' first. Error: ${error.message}`);
            }

            // Deploy ECDSA Validator with explicit nonce
            console.log("Deploying ECDSAValidator...");
            const ECDSAValidatorFactory = new ethers.ContractFactory(ecdsaValidatorArtifact.abi, ecdsaValidatorArtifact.bytecode, alice);
            ecdsaValidator = await ECDSAValidatorFactory.deploy({ nonce: deploymentNonce++ });
            await ecdsaValidator.waitForDeployment();
            console.log(`ECDSAValidator deployed at: ${await ecdsaValidator.getAddress()}`);

            // Deploy WalletCore implementation with explicit nonce
            console.log("Deploying WalletCore implementation...");
            const WalletCoreFactory = new ethers.ContractFactory(walletCoreArtifact.abi, walletCoreArtifact.bytecode, alice);
            const walletCoreImpl = await WalletCoreFactory.deploy({ nonce: deploymentNonce++ });
            await walletCoreImpl.waitForDeployment();
            console.log(`WalletCore implementation deployed at: ${await walletCoreImpl.getAddress()}`);

            // Deploy SmartWalletFactory with explicit nonce
            console.log("Deploying SmartWalletFactory...");
            const factoryArtifact = JSON.parse(fs.readFileSync(path.join(__dirname, '../out/SmartWalletFactory.sol/SmartWalletFactory.json'), 'utf8'));
            const FactoryFactory = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, alice);
            const factory: any = await FactoryFactory.deploy({ nonce: deploymentNonce++ });
            await factory.waitForDeployment();
            console.log(`SmartWalletFactory deployed at: ${await factory.getAddress()}`);

            // Deploy MockERC20 with explicit nonce
            console.log("Deploying MockERC20...");
            const MockERC20Factory = new ethers.ContractFactory(mockERC20Artifact.abi, mockERC20Artifact.bytecode, alice);
            mockToken = await MockERC20Factory.deploy({ nonce: deploymentNonce++ });
            await mockToken.waitForDeployment();
            console.log(`MockERC20 deployed at: ${await mockToken.getAddress()}`);

            // Create Alice's wallet using the factory
            console.log("Creating Alice's wallet via factory...");
            const initialOwners: InitialOwner[] = [{
                keyHash: ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address"], [aliceAddress])),
                validator: await ecdsaValidator.getAddress()
            }];

            const salt = 42; // Deterministic salt
            const createTx = await factory.createAccount(
                await walletCoreImpl.getAddress(),
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
            walletCore = new ethers.Contract(walletAddress, walletCoreArtifact.abi, alice);

            // Give Alice some mock tokens for testing (using explicit nonce)
            console.log("Minting tokens for Alice...");
            const mintTx = await mockToken.mint(aliceAddress, ethers.parseUnits("1000", 18), { nonce: deploymentNonce++ });
            await mintTx.wait();
            console.log("Alice minted 1000 mock tokens");

            // Initialize nonce tracking for tests (after all deployments)
            currentNonce = BigInt(await provider.getTransactionCount(aliceAddress));
            console.log(`Test starting nonce: ${currentNonce}`);

            // Set up EIP-712 domain (use wallet address, not EOA address)
            domain = {
                name: "wallet-core",
                version: "1.0.0",
                chainId: chainId,
                verifyingContract: await walletCore.getAddress(),
            };
            console.log("EIP-712 domain configured");

            // Set up relayer API client
            relayerAxios = axios.create({
                baseURL: RELAYER_API_URL,
                headers: {
                    'Authorization': `Bearer ${RELAYER_AUTH_TOKEN}`,
                    'Content-Type': 'application/json'
                },
                timeout: 30000 // 30 second timeout
            });
            console.log("Relayer API client configured");

            console.log("Test environment setup complete!\n");

        } catch (error) {
            console.error("BeforeEach setup failed:", error.message);
            throw error;
        }
    });

    function constructCallsData(): Call[] {
        return [{
            target: bobAddress,
            value: ethers.parseEther("1"),
            data: "0x"
        }];
    }

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

    async function getValidationTypedHash(calls: Call[], nonce: bigint = 0n, executionGas: bigint = 0n): Promise<string> {
        const value = {
            wallet: await walletCore.getAddress(),
            nonce: nonce,
            executionGas: executionGas,
            relayerCalls: [],
            calls: calls
        };

        return ethers.TypedDataEncoder.hash(domain, types, value);
    }

    async function constructValidatorData(calls: Call[], nonce?: bigint): Promise<string> {
        const useNonce = nonce !== undefined ? nonce : currentNonce++;
        const hash = await getValidationTypedHash(calls, useNonce);
        const signature = await alice.signMessage(ethers.getBytes(hash));
        const keyHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address"], [aliceAddress]));
        return ethers.concat([keyHash, signature]);
    }

    async function simulateGasViaRelayer(
        calls: Call[],
        tokenAddress: string
    ): Promise<SimulateSponsorResult> {
        const iface = new ethers.Interface(["function simulateExecuteWithRelayer(tuple(tuple(address target,uint256 value,bytes data)[] calls,uint256 nonce,uint48 expiry) batchedCall,bytes validatorData)"]);

        const batchedCall = {
            calls: calls,
            nonce: currentNonce,
            expiry: Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
        };


        const mockValidatorData = ethers.getBytes(
            "0x665186aa6b01d30d23f695519c5ace858b2849f42d4c44d7439f49e06ffe10ed1b954470b6234650c6c56b3b650d5a58966cc9a07f8737ea929af8fb07c3b47f1b"
        );

        const calldata = iface.encodeFunctionData("simulateExecuteWithRelayer", [
            batchedCall,
            mockValidatorData,
        ]);

        const requestBody = {
            jsonrpc: "2.0",
            method: "walletcore_simulateSponsor",
            params: {
                calldata: calldata,
                to: await walletCore.getAddress(),
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
    ): Promise<SubmitSponsorResult> {
        const iface = new ethers.Interface(["function executeWithRelayer(tuple(tuple(address target,uint256 value,bytes data)[] calls,uint256 nonce,uint48 expiry) batchedCall,bytes validatorData)"]);

        const batchedCall = {
            calls: calls,
            nonce: currentNonce++,
            expiry: Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
        };

        const calldata = iface.encodeFunctionData("executeWithRelayer", [
            batchedCall,
            validationData,
        ]);

        const requestBody = {
            jsonrpc: "2.0",
            method: "walletcore_freeGasMode",
            params: {
                calldata: calldata,
                to: await walletCore.getAddress(),
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
                    bobAddress,
                    ethers.parseUnits("100000", 18) // sufficient to pass relayer test
                ),
                constructERC20TransferCall(
                    await mockToken.getAddress(),
                    bobAddress,
                    ethers.parseUnits("10", 18)
                )
            ];

            // Construct validation data
            const validatorData = await constructValidatorData(calls);

            const bobBalanceBefore = await provider.getBalance(bobAddress);

            // Submit transaction via relayer API
            const submitResult = await submitSponsorTx(
                calls,
                validatorData,
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
            } while (txStatus.data.status === 'pending' && attempts < maxAttempts);

            expect(txStatus.success).to.be.true;
            expect(txStatus.data.status).to.equal('confirmed');

            // Verify the transaction effect
            const bobBalanceAfter = await provider.getBalance(bobAddress);
            expect(bobBalanceAfter - bobBalanceBefore).to.equal(ethers.parseEther("1"));
        });

        it("should execute with relayer payment via API", async function () {
            // Give alice some tokens first
            await mockToken.transfer(aliceAddress, ethers.parseUnits("100", 18));

            const userCall = constructCallsData()[0];
            const relayerPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                ethers.parseUnits("10", 18)
            );
            const relayerCalls = [relayerPaymentCall];
            const calls = [userCall];

            // Simulate first
            const simulationResult = await simulateGasViaRelayer(
                [relayerPaymentCall, userCall],
                await mockToken.getAddress()
            );

            // Prepare validation data for the combined transaction
            const allCalls = [...relayerCalls, ...calls];
            const validatorData = await constructValidatorData(allCalls);

            const relayerTokenBalanceBefore = await mockToken.balanceOf(relayerAddress);
            const bobBalanceBefore = await provider.getBalance(bobAddress);

            // Submit via relayer API
            const submitResult = await submitSponsorTx(
                calls,
                validatorData,
            );

            // Wait for confirmation
            let txStatus: TransactionStatusResponse;
            let attempts = 0;

            do {
                await new Promise(resolve => setTimeout(resolve, 2000));
                txStatus = await getTransactionStatus(submitResult.relayer_id, submitResult.id);
                attempts++;
            } while (txStatus.data.status === 'pending' && attempts < 30);

            expect(txStatus.success).to.be.true;
            expect(txStatus.data.status).to.equal('confirmed');

            // Verify both the payment and user action succeeded
            const relayerTokenBalanceAfter = await mockToken.balanceOf(relayerAddress);
            const bobBalanceAfter = await provider.getBalance(bobAddress);

            expect(relayerTokenBalanceAfter - relayerTokenBalanceBefore).to.equal(ethers.parseUnits("10", 18));
            expect(bobBalanceAfter - bobBalanceBefore).to.equal(ethers.parseEther("1"));
        });
    });

    describe("End-to-End Relayer Flow", function () {
        it("should complete full sponsored transaction flow", async function () {
            // Give alice tokens for relayer payment
            await mockToken.transfer(aliceAddress, ethers.parseUnits("100", 18));

            const userCall = constructCallsData()[0];
            const sponsorPaymentCall = constructERC20TransferCall(
                await mockToken.getAddress(),
                relayerAddress,
                ethers.parseUnits("5", 18)
            );

            // Step 1: Simulate the transaction
            const simulationResult = await simulateGasViaRelayer(
                [sponsorPaymentCall, userCall],
                await mockToken.getAddress()
            );

            expect(simulationResult.execution_gas).to.be.a('number');
            expect(simulationResult.total_gas).to.be.greaterThan(simulationResult.execution_gas);

            // Step 2: Prepare and sign the transaction
            const allCalls = [sponsorPaymentCall, userCall];
            const validatorData = await constructValidatorData(allCalls);

            // Step 3: Submit the transaction
            const submitResult = await submitSponsorTx(
                allCalls,
                validatorData,
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
            expect(txStatus.data.status).to.equal('confirmed');
            expect(txStatus.data.hash).to.be.a('string');

            // Step 6: Verify on-chain effects
            const relayerTokenBalance = await mockToken.balanceOf(relayerAddress);
            const bobBalance = await provider.getBalance(bobAddress);

            expect(relayerTokenBalance).to.equal(ethers.parseUnits("5", 18));
            expect(bobBalance).to.equal(ethers.parseEther("1"));
        });
    });
});
