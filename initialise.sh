set -e

RPC_URL=http://localhost:8545
EOA_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 # anvil account 2
EOA_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d # anvil account 2
export DEPLOYER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # can be any address
RELAYER_ADDRESS="0x55f3a93f544e01ce4378d25e927d7c493b863bd6" # Address of the relayer

# Deploy the factory
forge script scripts/CreateDeployFactory.sol --broadcast --rpc-url $RPC_URL

# Extract WalletCore address from deployment output  
DEPLOYMENT_OUTPUT=$(forge script scripts/DeployInit.sol --broadcast --rpc-url $RPC_URL)
WALLET_CORE_ADDRESS=$(echo "$DEPLOYMENT_OUTPUT" | grep "WalletCore address:" | awk '{print $3}')
ECDSA_VALIDATOR_ADDRESS=$(echo "$DEPLOYMENT_OUTPUT" | grep "ECDSAValidator address:" | awk '{print $3}')

# Check if addresses were extracted successfully
if [ -z "$WALLET_CORE_ADDRESS" ] || [ -z "$ECDSA_VALIDATOR_ADDRESS" ]; then
    echo "Error: Failed to extract contract addresses from deployment output"
    echo "WALLET_CORE_ADDRESS: $WALLET_CORE_ADDRESS"
    echo "ECDSA_VALIDATOR_ADDRESS: $ECDSA_VALIDATOR_ADDRESS"
    exit 1
fi

# Extract ERC20 token address from deployment output
ERC20_ADDRESS=$(forge script scripts/DeployTestToken.sol:DeployTestToken --sig "run(address)" $EOA_ADDRESS --broadcast --rpc-url $RPC_URL | grep "TestToken deployed at:" | awk '{print $4}')

AAVE_ADDRESS=$(forge script scripts/DeployAAVEToken.sol:DeployAAVEToken --sig "run(address)" $EOA_ADDRESS --broadcast --rpc-url $RPC_URL | grep "AAVEToken deployed at:" | awk '{print $4}')

# Send 1000000000000000000 to the relayer
cast send $RELAYER_ADDRESS --value 1000000000000000000 --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL

echo "Balance of relayer"
cast balance $RELAYER_ADDRESS --rpc-url $RPC_URL

echo "CallData to sending 10 tokens to the relayer"
cast calldata "transfer(address,uint256)" $RELAYER_ADDRESS 10

echo "Upgrading EOA into 7702"
cast send $(cast az) --auth $WALLET_CORE_ADDRESS --private-key $EOA_PRIVATE_KEY --rpc-url $RPC_URL

echo "Initializing wallet with EOA as owner and ECDSAValidator"
# Create keyHash from EOA address (keccak256(abi.encode(address)))
KEY_HASH=$(cast keccak $(cast abi-encode "f(address)" $EOA_ADDRESS))
echo "Key hash: $KEY_HASH"
echo "Using ECDSAValidator: $ECDSA_VALIDATOR_ADDRESS"

# Create InitialOwner struct and call initialize using cast rpc instead of cast send
# Generate complete calldata for the initialize function
INIT_CALLDATA=$(cast calldata "initialize((bytes32,address)[])" "[($KEY_HASH,$ECDSA_VALIDATOR_ADDRESS)]")
echo "Initialize calldata: $INIT_CALLDATA"

# Use cast send with proper escaping for the tuple array
# cast send $EOA_ADDRESS "initialize((bytes32,address)[])" "[(${KEY_HASH},${ECDSA_VALIDATOR_ADDRESS})]" --private-key $EOA_PRIVATE_KEY --rpc-url $RPC_URL

cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL --value 10000
cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL --value 10000
cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL --value 10000
cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL --value 10000

echo -e "\033[1;36m\n----------------------------VARIABLES----------------------------\033[0m"

echo "WalletCore address: $WALLET_CORE_ADDRESS"
echo "ECDSAValidator address: $ECDSA_VALIDATOR_ADDRESS"
echo "ERC20 address: $ERC20_ADDRESS"
echo "AAVE address: $AAVE_ADDRESS"
echo "Relayer address: $RELAYER_ADDRESS"
echo "EOA address: $EOA_ADDRESS"
echo "Key hash: $KEY_HASH"
echo ""
echo "CallData to send 10 tokens to the relayer:"
cast calldata "transfer(address,uint256)" $RELAYER_ADDRESS 10
