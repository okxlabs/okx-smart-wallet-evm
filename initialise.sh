EOA_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 # anvil account 2
EOA_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d # anvil account 2
DEPLOYER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # can be any address
RELAYER_ADDRESS="0x55f3a93f544e01ce4378d25e927d7c493b863bd6" # Address of the relayer

# Deploy the factory
forge script scripts/CreateDeployFactory.sol --broadcast --rpc-url localhost:8545

# Extract WalletCore address from deployment output
WALLET_CORE_ADDRESS=$(forge script scripts/DeployInit.sol --broadcast --rpc-url localhost:8545 | grep "WalletCore address:" | awk '{print $3}')

# Extract ERC20 token address from deployment output
ERC20_ADDRESS=$(forge script scripts/DeployTestToken.sol:DeployTestToken --sig "run(address)" $EOA_ADDRESS --broadcast --rpc-url localhost:8545 | grep "TestToken deployed at:" | awk '{print $4}')

AAVE_ADDRESS=$(forge script scripts/DeployAAVEToken.sol:DeployAAVEToken --sig "run(address)" $EOA_ADDRESS --broadcast --rpc-url localhost:8545 | grep "AAVEToken deployed at:" | awk '{print $4}')

# Send 1000000000000000000 to the relayer
cast send $RELAYER_ADDRESS --value 1000000000000000000 --private-key $DEPLOYER_PRIVATE_KEY --rpc-url http://localhost:8545

echo "Balance of relayer"
cast balance $RELAYER_ADDRESS --rpc-url http://localhost:8545

echo "CallData to sending 10 tokens to the relayer"
cast calldata "transfer(address,uint256)" $RELAYER_ADDRESS 10

echo "Upgrading EOA into 7702"
cast send $(cast az) --auth $WALLET_CORE_ADDRESS --private-key $EOA_PRIVATE_KEY --rpc-url http://localhost:8545
cast send $EOA_ADDRESS "initialize()" --private-key $EOA_PRIVATE_KEY --rpc-url http://localhost:8545

cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url http://localhost:8545 --value 10000 
cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url http://localhost:8545 --value 10000 
cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url http://localhost:8545 --value 10000 
cast send $WALLET_CORE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url http://localhost:8545 --value 10000 

echo -e "\033[1;36m\n----------------------------VARIABLES----------------------------\033[0m"

echo "WalletCore address: $WALLET_CORE_ADDRESS"
echo "ERC20 address: $ERC20_ADDRESS"
echo "AAVE address: $AAVE_ADDRESS"
echo "Relayer address: $RELAYER_ADDRESS"
echo "EOA address: $EOA_ADDRESS"
echo ""
echo "CallData to send 10 tokens to the relayer"
cast calldata "transfer(address,uint256)" $RELAYER_ADDRESS 10
