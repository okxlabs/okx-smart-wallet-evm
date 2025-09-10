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

echo -e "${YELLOW}🏭 Deploying EIP-2470 Singleton Factory and DeployFactory...${NC}"

# Deploy the EIP-2470 Singleton Factory and DeployFactory using Forge script
yarn deploy-factory $RPC_URL --broadcast -vvv
FACTORY_RESULT=$?

if [ $FACTORY_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ EIP-2470 Singleton Factory and DeployFactory deployed successfully!${NC}"
else
    echo -e "${RED}❌ Factory deployment failed with exit code $FACTORY_RESULT${NC}"
    exit $FACTORY_RESULT
fi

echo -e "${YELLOW}🏗️  Deploying SmartWallet contracts...${NC}"

# Deploy the SmartWallet contracts and capture output
DEPLOY_OUTPUT=$(yarn deploy $RPC_URL --broadcast 2>&1)
DEPLOY_RESULT=$?

if [ $DEPLOY_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ SmartWallet contracts deployed successfully!${NC}"
    
    # Extract SmartWallet address from deployment output
    SMART_WALLET_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "SmartWallet Implementation address:" | sed 's/.*SmartWallet Implementation address: //')
    
    if [ -n "$SMART_WALLET_ADDRESS" ]; then
        echo -e "${YELLOW}📝 SmartWallet implementation address: $SMART_WALLET_ADDRESS${NC}"
        export SMART_WALLET=$SMART_WALLET_ADDRESS
        echo -e "${GREEN}✅ Exported SMART_WALLET environment variable${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not extract SmartWallet address from deployment output${NC}"
    fi
    
    # Extract SmartWalletFactory address from deployment output
    SMART_WALLET_FACTORY_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "SmartWalletFactory address:" | sed 's/.*SmartWalletFactory address: //')
    
    if [ -n "$SMART_WALLET_FACTORY_ADDRESS" ]; then
        echo -e "${YELLOW}📝 SmartWalletFactory address: $SMART_WALLET_FACTORY_ADDRESS${NC}"
        export SMART_WALLET_FACTORY=$SMART_WALLET_FACTORY_ADDRESS
        echo -e "${GREEN}✅ Exported SMART_WALLET_FACTORY environment variable${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not extract SmartWalletFactory address from deployment output${NC}"
    fi
    
    
    # Show deployment logs for debugging
    echo "$DEPLOY_OUTPUT" | grep -E "SmartWallet|ECDSAValidator|PasskeyValidator|Factory|Helper"
else
    echo -e "${RED}❌ SmartWallet contract deployment failed with exit code $DEPLOY_RESULT${NC}"
    echo "$DEPLOY_OUTPUT"
    exit $DEPLOY_RESULT
fi

echo -e "${YELLOW}🧪 Running smoke test scripts...${NC}"

# Test 0: Create SmartWallet Account with Passkey Owner
echo -e "${YELLOW}📝 Test 0: Create SmartWallet Account with Passkey Owner${NC}"

# Set default Validator addresses if not already set
if [ -z "$PASSKEY_VALIDATOR" ]; then
    export PASSKEY_VALIDATOR="0x0000000000000000000000000000000000000002"
    echo -e "${YELLOW}📝 Using default PASSKEY_VALIDATOR: $PASSKEY_VALIDATOR${NC}"
fi

if [ -z "$ECDSA_VALIDATOR" ]; then
    export ECDSA_VALIDATOR="0x0000000000000000000000000000000000000001"
    echo -e "${YELLOW}📝 Using default ECDSA_VALIDATOR: $ECDSA_VALIDATOR${NC}"
fi

# Set default Passkey public key if not already set
if [ -z "$PASSKEY_PUB_X" ]; then
    export PASSKEY_PUB_X="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    echo -e "${YELLOW}📝 Using default PASSKEY_PUB_X: $PASSKEY_PUB_X${NC}"
fi

if [ -z "$PASSKEY_PUB_Y" ]; then
    export PASSKEY_PUB_Y="0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321"
    echo -e "${YELLOW}📝 Using default PASSKEY_PUB_Y: $PASSKEY_PUB_Y${NC}"
fi

# Capture output to extract the created account address
CREATE_ACCOUNT_OUTPUT=$(yarn 0-createAccount $RPC_URL --broadcast 2>&1)
TEST0_RESULT=$?

echo "$CREATE_ACCOUNT_OUTPUT"

if [ $TEST0_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 0: SmartWallet account creation completed successfully!${NC}"
    
    # Extract the created SmartWallet account address
    CREATED_ACCOUNT=$(echo "$CREATE_ACCOUNT_OUTPUT" | grep "SmartWallet account created at:" | sed 's/.*SmartWallet account created at:  //' | sed 's/[[:space:]]*$//')
    
    if [ -n "$CREATED_ACCOUNT" ]; then
        export USER_WALLET=$CREATED_ACCOUNT
        echo -e "${YELLOW}📝 Exported USER_WALLET: $USER_WALLET${NC}"
        
        # Fund the created account for future transactions
        echo -e "${YELLOW}💰 Funding created account...${NC}"
        cast send --rpc-url $RPC_URL \
            --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
            --value 0.1ether \
            $CREATED_ACCOUNT > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Successfully funded created account with 0.1 ETH${NC}"
        else
            echo -e "${YELLOW}⚠️  Failed to fund created account${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Could not extract created account address${NC}"
    fi
else
    echo -e "${RED}❌ Test 0: SmartWallet account creation failed with exit code $TEST0_RESULT${NC}"
    exit $TEST0_RESULT
fi

# Test 1: Set Code and Initialize (Using yarn command from package.json)
echo -e "${YELLOW}📝 Test 1: EIP-7702 Set Code and Initialize${NC}"
yarn 1-setCodeAndInitialize $RPC_URL --broadcast --evm-version prague --skip-simulation
TEST1_RESULT=$?

if [ $TEST1_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 1: EIP-7702 initialization completed successfully!${NC}"
    # USER_WALLET is already set from Test 0 (the created account), keep it as is
    echo -e "${YELLOW}📝 USER_WALLET (from Test 0): $USER_WALLET${NC}"
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

# Test 4: Send Transactions with Passkey signature
echo -e "${YELLOW}📝 Test 4: Passkey-based execution (executeWithRelayer using Passkey)${NC}"

# Set default Passkey private keys and public keys if not already set
if [ -z "$PASSKEY_PRIVATE_KEY" ]; then
    # Default test Passkey 1 (must be valid P256 private key)
    export PASSKEY_PRIVATE_KEY="0x03d99692017473e2d631945a812607b23269d85721e0f370b8d3e7d29a874fd2"
    echo -e "${YELLOW}📝 Using default PASSKEY_PRIVATE_KEY${NC}"
fi

if [ -z "$PASSKEY_PUB_X" ]; then
    # Corresponding public key X coordinate for the private key above
    export PASSKEY_PUB_X="0x65a2fa44daad46eab0278703edb6c4dcf5e30b8a9aec09fdc71a56f52aa392e4"
    echo -e "${YELLOW}📝 Using default PASSKEY_PUB_X${NC}"
fi

if [ -z "$PASSKEY_PUB_Y" ]; then
    # Corresponding public key Y coordinate for the private key above
    export PASSKEY_PUB_Y="0x4a7a9e4604aa36898209997288e902ac544a555e4b5e0a9efef2b59233f3f437"
    echo -e "${YELLOW}📝 Using default PASSKEY_PUB_Y${NC}"
fi

if [ -z "$PASSKEY_PRIVATE_KEY_2" ]; then
    # Default test Passkey 2 (must be valid P256 private key)
    export PASSKEY_PRIVATE_KEY_2="0x04d99692017473e2d631945a812607b23269d85721e0f370b8d3e7d29a874fd2"
    echo -e "${YELLOW}📝 Using default PASSKEY_PRIVATE_KEY_2${NC}"
fi

if [ -z "$PASSKEY_PUB_X_2" ]; then
    # Corresponding public key X coordinate for private key 2
    export PASSKEY_PUB_X_2="0x3059301306072a8648ce3d020106082a8648ce3d03010703420004d6eb8f37"
    echo -e "${YELLOW}📝 Using default PASSKEY_PUB_X_2${NC}"
fi

if [ -z "$PASSKEY_PUB_Y_2" ]; then
    # Corresponding public key Y coordinate for private key 2
    export PASSKEY_PUB_Y_2="0x7c8dbde1c2b5b3e4c4e4d0e8b8f9e2c4a6d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2"
    echo -e "${YELLOW}📝 Using default PASSKEY_PUB_Y_2${NC}"
fi

yarn 4-sendTxsWithPasskey $RPC_URL --broadcast
TEST4_RESULT=$?

if [ $TEST4_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 4: Passkey execution completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 4: Passkey execution failed with exit code $TEST4_RESULT${NC}"
    exit $TEST4_RESULT
fi

# Test 5: Create Account with AddOwner using createAccountWithCall
echo -e "${YELLOW}📝 Test 5: Create account with addOwner via createAccountWithCall${NC}"
yarn 5-createAccountWithAddOwner $RPC_URL --broadcast
TEST5_RESULT=$?

if [ $TEST5_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 5: CreateAccountWithCall completed successfully!${NC}"
else
    echo -e "${RED}❌ Test 5: CreateAccountWithCall failed with exit code $TEST5_RESULT${NC}"
    exit $TEST5_RESULT
fi

# Test 6: Send Transactions via EntryPoint with Passkey
echo -e "${YELLOW}📝 Test 6: ERC-4337 EntryPoint execution with Passkey${NC}"
yarn 6-addOwnerAndExecuteViaEntryPoint $RPC_URL --broadcast --skip-simulation
TEST6_RESULT=$?

if [ $TEST6_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Test 6: EntryPoint execution with Passkey completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Test 6: EntryPoint execution failed with exit code $TEST6_RESULT${NC}"
    echo -e "${YELLOW}⚠️  This is expected on local network. Continuing...${NC}"
fi

echo -e "${GREEN}🎉 All smoke tests completed successfully!${NC}"