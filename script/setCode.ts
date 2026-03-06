const { ethers } = require('hardhat');

const main = async () => {
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, ethers.provider);
  const chainId = (await ethers.provider.getNetwork()).chainId;

  // Get the contract instance
  const SMART_WALLET_IMPL = "0x0000000000000000000000000000000000000000";
  /// const SMART_WALLET_IMPL = process.env.SMART_WALLET_IMPL;

  console.log("Chain ID: ", chainId);
  console.log("EOA address: ", wallet.address);
  console.log("Setting code for EIP7702 account at: ", SMART_WALLET_IMPL);

  // Encode the execute function call with WalletCore.initialize()
  const calldata = "0x765e827f00000000000000000000000000000000000000000000000000000000000000400000000000000000000000003bceebfcee7d45eb78ff2e24a4007ff065d96c98000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000002ae73eefc0b0a0df3c52577c16c025edb463a1ff000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000140000000000000000000000000001e848000000000000000000000000000061a800000000000000000000000000000000000000000000000000000000000005208000000000000000000000000000000010000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001448dd7712f0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000006250c0459a6565f904b71e2d53c3d2bbb582357c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000004840c10f190000000000000000000000003bceebfcee7d45eb78ff2e24a4007ff065d96c980000000000000000000000000000000000000000000000000de0b6b3a7640000aabbccdd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002863a61a9e5867be922648827ec6d865ea7a03b839fe4ce554c250e562c510c6e180000000000002080e77dc16162c7debbdeaa0bbf2de797d66bb9c42b327f58637699fbe2336aca68486eae03fa39c8567ffd461b254a00171a746eaaee435a91fb06ef53e67c0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000170000000000000000000000000000000000000000000000000000000000000001458b9682fd67e6a36cb03c0ae1280d7a0e111a84048ac131b65582a82cf8b2d65033b9bede936dbebdbe082484a3d593f8996528d80da05e170715e09276a3eb000000000000000000000000000000000000000000000000000000000000002549960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a7b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a227a445854745f765743716c576f4e71436665316a6945644d6a5a4b354c4750334c487a7a6c5551704a7a45222c226f726967696e223a2268747470733a2f2f746573742d7361676c6f62616c2e6f6b672e636f6d227d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

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
    address: SMART_WALLET_IMPL,
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