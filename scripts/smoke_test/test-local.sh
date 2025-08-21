#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# Start anvil in the background
anvil --port 8545 --chain-id 31337 --accounts 10 --balance 10000 > anvil.log 2>&1 &
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
echo -e "${YELLOW}🔗 Node URL: http://localhost:8545${NC}"
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
    cast send --rpc-url http://localhost:8545 \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
        --value 1000ether \
        $DEPLOYER_ADDRESS > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully funded deployer account${NC}"
    else
        echo -e "${RED}❌ Failed to fund deployer account${NC}"
    fi
fi

echo -e "${YELLOW}🏗️  Deploying SmartWallet contracts...${NC}"

# Deploy the SmartWallet contracts  
forge script scripts/DeployInit.sol --rpc-url http://localhost:8545 --broadcast
DEPLOY_RESULT=$?

if [ $DEPLOY_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ SmartWallet contracts deployed successfully!${NC}"
else
    echo -e "${RED}❌ SmartWallet contract deployment failed with exit code $DEPLOY_RESULT${NC}"
    exit $DEPLOY_RESULT
fi

echo -e "${YELLOW}🧪 Running smoke test scripts...${NC}"

# Test 1: Set Code and Initialize (Hardhat script)
echo -e "${YELLOW}📝 Test 1: EIP-7702 Set Code and Initialize${NC}"
npx hardhat run scripts/smoke_test/1-setCodeAndInitialize.ts --network localhost
TEST1_RESULT=$?

if [ $TEST1_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 1: EIP-7702 initialization completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 1: EIP-7702 initialization failed with exit code $TEST1_RESULT${NC}"
    exit $TEST1_RESULT
fi

# Test 2: Send Direct Transactions (Forge script)
echo -e "${YELLOW}📝 Test 2: Direct execution from SmartWallet${NC}"
forge script scripts/smoke_test/2-sendTxs.sol --rpc-url http://localhost:8545 --broadcast
TEST2_RESULT=$?

if [ $TEST2_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 2: Direct execution completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 2: Direct execution failed with exit code $TEST2_RESULT${NC}"
    exit $TEST2_RESULT
fi

# Test 3: Send Transactions with Relayer (Forge script)
echo -e "${YELLOW}📝 Test 3: Relayer-based execution (executeWithRelayer)${NC}"
forge script scripts/smoke_test/3-sendTxsAsRelayer.sol --rpc-url http://localhost:8545 --broadcast
TEST3_RESULT=$?

if [ $TEST3_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 3: Relayer execution completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 3: Relayer execution failed with exit code $TEST3_RESULT${NC}"
    exit $TEST3_RESULT
fi

echo -e "${GREEN}🎉 All smoke tests completed successfully!${NC}"

echo -e "${YELLOW}📋 Anvil logs:${NC}"
cat anvil.log

# Keep the node running for manual testing (optional)
read -p "$(echo -e ${YELLOW}Keep node running for manual testing? [y/N]:${NC} )" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🔄 Node is still running. Press Ctrl+C to stop.${NC}"
    wait $ANVIL_PID
fi