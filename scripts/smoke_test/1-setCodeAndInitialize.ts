const { ethers } = require('hardhat');

const main = async () => {
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, ethers.provider);
  const chainId = (await ethers.provider.getNetwork()).chainId;

  // Get the contract instance
  const WALLET_CORE = process.env.WALLET_CORE;
  const WalletCore = await ethers.getContractAt("WalletCore", WALLET_CORE);

  console.log("Chain ID: ", chainId);
  console.log("EOA address: ", wallet.address);
  console.log("Setting code for EIP7702 account at: ", WALLET_CORE);

  // Encode the execute function call with WalletCore.initialize()
  const calldata = WalletCore.interface.encodeFunctionData("initialize");

  const currentNonce = await ethers.provider.getTransactionCount(wallet.address);

  const authorizationData: {
    chainId: any;
    address: string | undefined;
    nonce: any;
    yParity?: string;
    r?: string;
    s?: string;
  } = {
    chainId: ethers.toBeHex(chainId.toString()),
    address: WALLET_CORE,
    nonce: ethers.toBeHex(currentNonce + 1),
  };

  // Encode authorization data according to EIP-712 standard
  const encodedAuthorizationData = ethers.concat([
    '0x05', // MAGIC code for EIP7702
    ethers.encodeRlp([
      authorizationData.chainId,
      authorizationData.address,
      authorizationData.nonce,
    ])
  ]);

  // Generate and sign authorization data hash
  const authorizationDataHash = ethers.keccak256(encodedAuthorizationData);
  const authorizationSignature = wallet.signingKey.sign(authorizationDataHash);

  // Store signature components
  authorizationData.yParity = authorizationSignature.yParity == 0 ? '0x' : '0x01';
  authorizationData.r = authorizationSignature.r;
  authorizationData.s = authorizationSignature.s;

  // Get current gas fee data from the network
  const feeData = await ethers.provider.getFeeData();

  // Prepare complete transaction data structure
  const txData = [
    authorizationData.chainId,
    currentNonce == 0 ? "0x" : ethers.toBeHex(currentNonce),  // Pass "0x" instead of "0x00" when currentNonce is 0
    ethers.toBeHex(feeData.maxPriorityFeePerGas), // Priority fee (tip)
    ethers.toBeHex(feeData.maxFeePerGas), // Maximum total fee willing to pay
    ethers.toBeHex(1000000), // Gas limit
    wallet.address, // Sender address
    '0x', // Value (in addition to batch transfers)
    calldata, // Encoded function call
    [], // Access list (empty for this transaction)
    [
      [
        authorizationData.chainId,
        authorizationData.address,
        authorizationData.nonce,
        authorizationData.yParity,
        authorizationData.r,
        authorizationData.s
      ]
    ]
  ];

  // Encode final transaction data with version prefix
  const encodedTxData = ethers.concat([
    '0x04', // Transaction type identifier
    ethers.encodeRlp(txData)
  ]);

  // Sign the complete transaction
  const txDataHash = ethers.keccak256(encodedTxData);
  const txSignature = wallet.signingKey.sign(txDataHash);

  // Construct the fully signed transaction
  const signedTx = ethers.hexlify(ethers.concat([
    '0x04',
    ethers.encodeRlp([
      ...txData,
      txSignature.yParity == 0 ? '0x' : '0x01',
      txSignature.r,
      txSignature.s
    ])
  ]));

  // Send the raw transaction to the network
  const tx = await ethers.provider.send('eth_sendRawTransaction', [signedTx]);
  console.log('tx sent: ', tx);
}

main().then(() => {
  console.log('Execution completed');
  process.exit(0);
}).catch((error) => {
  console.error(error);
  process.exit(1);
});