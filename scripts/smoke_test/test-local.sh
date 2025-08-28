#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# RPC URL configuration
RPC_URL="http://localhost:8545"

echo -e "${GREEN}🚀 Starting Smart Wallet Local Test${NC}"

# Check if anvil is installed
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}❌ Anvil not found. Please install Foundry first.${NC}"
    exit 1
fi

# Check if npx is available
if ! command -v npx &> /dev/null; then
    echo -e "${RED}❌ npx not found. Please install Node.js and npm first.${NC}"
    exit 1
fi

echo -e "${YELLOW}📡 Starting Foundry local node...${NC}"

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo -e "${YELLOW}📄 Loading .env file...${NC}"
    source .env
fi

# Start anvil in the background with Prague hardfork for EIP-7702 support
anvil --port 8545 --chain-id 31337 --hardfork prague --accounts 10 --balance 10000 > anvil.log 2>&1 &
ANVIL_PID=$!

# Wait for anvil to start
sleep 3

# Check if anvil is running
if ! kill -0 $ANVIL_PID 2>/dev/null; then
    echo -e "${RED}❌ Failed to start anvil${NC}"
    cat anvil.log
    exit 1
fi

echo -e "${GREEN}✅ Foundry node started (PID: $ANVIL_PID)${NC}"
echo -e "${YELLOW}🔗 Node URL: $RPC_URL${NC}"
echo -e "${YELLOW}🆔 Chain ID: 31337${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}🧹 Cleaning up...${NC}"
    kill $ANVIL_PID 2>/dev/null
    rm -f anvil.log
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Set trap to cleanup on script exit
trap cleanup EXIT

# Wait a bit more to ensure node is fully ready
sleep 2

# Fund custom deployer account if needed
if [ -n "$DEPLOYER_PRIVATE_KEY" ]; then
    echo -e "${YELLOW}💰 Funding custom deployer account...${NC}"
    # Calculate the address from private key and send ETH from first default account
    DEPLOYER_ADDRESS=$(cast wallet address $DEPLOYER_PRIVATE_KEY)
    echo -e "${YELLOW}📍 Deployer address: $DEPLOYER_ADDRESS${NC}"
    cast send --rpc-url $RPC_URL \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
        --value 1000ether \
        $DEPLOYER_ADDRESS > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully funded deployer account${NC}"
    else
        echo -e "${RED}❌ Failed to fund deployer account${NC}"
    fi
fi

echo -e "${YELLOW}🏭 Deploying DeployFactory (EIP-2470)...${NC}"

# Deploy the DeployFactory first
bash scripts/smoke_test/deploy-factory.sh
FACTORY_RESULT=$?

if [ $FACTORY_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ DeployFactory deployed successfully!${NC}"
else
    echo -e "${RED}❌ DeployFactory deployment failed with exit code $FACTORY_RESULT${NC}"
    exit $FACTORY_RESULT
fi

echo -e "${YELLOW}🏗️  Deploying SmartWallet contracts...${NC}"

# Deploy the SmartWallet contracts and capture output
DEPLOY_OUTPUT=$(yarn deploy $RPC_URL --broadcast 2>&1)
DEPLOY_RESULT=$?

if [ $DEPLOY_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ SmartWallet contracts deployed successfully!${NC}"
    
    # Extract SmartWallet address from deployment output
    SMART_WALLET_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "SmartWallet address:" | sed 's/.*SmartWallet address: //')
    
    if [ -n "$SMART_WALLET_ADDRESS" ]; then
        echo -e "${YELLOW}📝 SmartWallet implementation address: $SMART_WALLET_ADDRESS${NC}"
        export SMART_WALLET=$SMART_WALLET_ADDRESS
        echo -e "${GREEN}✅ Exported SMART_WALLET environment variable${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not extract SmartWallet address from deployment output${NC}"
    fi
    
    # Extract ECDSAValidator address from deployment output
    ECDSA_VALIDATOR_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "ECDSAValidator address:" | sed 's/.*ECDSAValidator address: //')
    
    if [ -n "$ECDSA_VALIDATOR_ADDRESS" ]; then
        echo -e "${YELLOW}📝 ECDSAValidator address: $ECDSA_VALIDATOR_ADDRESS${NC}"
        export ECDSA_VALIDATOR=$ECDSA_VALIDATOR_ADDRESS
        echo -e "${GREEN}✅ Exported ECDSA_VALIDATOR environment variable${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not extract ECDSAValidator address from deployment output${NC}"
    fi
    
    # Show deployment logs for debugging
    echo "$DEPLOY_OUTPUT" | grep -E "SmartWallet|ECDSAValidator|PasskeyValidator|Factory|Helper"
else
    echo -e "${RED}❌ SmartWallet contract deployment failed with exit code $DEPLOY_RESULT${NC}"
    echo "$DEPLOY_OUTPUT"
    exit $DEPLOY_RESULT
fi

echo -e "${YELLOW}🧪 Running smoke test scripts...${NC}"

# Test 1: Set Code and Initialize (Using yarn command from package.json)
echo -e "${YELLOW}📝 Test 1: EIP-7702 Set Code and Initialize${NC}"
yarn 1-setCodeAndInitialize $RPC_URL --broadcast --evm-version prague --skip-simulation
TEST1_RESULT=$?

if [ $TEST1_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 1: EIP-7702 initialization completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 1: EIP-7702 initialization failed with exit code $TEST1_RESULT${NC}"
    exit $TEST1_RESULT
fi

# Test 2: Send Direct Transactions (Using yarn command from package.json)
echo -e "${YELLOW}📝 Test 2: Direct execution from SmartWallet${NC}"
yarn 2-sendTxs $RPC_URL --broadcast
TEST2_RESULT=$?

if [ $TEST2_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 2: Direct execution completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 2: Direct execution failed with exit code $TEST2_RESULT${NC}"
    exit $TEST2_RESULT
fi

# Test 3: Send Transactions with Relayer (Using yarn command from package.json)
echo -e "${YELLOW}📝 Test 3: Relayer-based execution (executeWithRelayer)${NC}"
yarn 3-sendTxsAsRelayer $RPC_URL --broadcast
TEST3_RESULT=$?

if [ $TEST3_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 3: Relayer execution completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 3: Relayer execution failed with exit code $TEST3_RESULT${NC}"
    exit $TEST3_RESULT
fi

echo -e "${GREEN}🎉 All smoke tests completed successfully!${NC}"

# Anvil logs are saved to anvil.log - uncomment below to display them
# echo -e "${YELLOW}📋 Anvil logs:${NC}"
# cat anvil.log

# Keep the node running for manual testing (optional)
read -p "$(echo -e ${YELLOW}Keep node running for manual testing? [y/N]:${NC} )" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🔄 Node is still running. Press Ctrl+C to stop.${NC}"
    wait $ANVIL_PID
fi