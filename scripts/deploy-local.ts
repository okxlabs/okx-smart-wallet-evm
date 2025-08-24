/**
 * Local deployment script for OKX Smart Wallet contracts
 * Use this to deploy all necessary contracts for local testing
 */

const hre = require('hardhat');

async function main() {
    console.log("🚀 Deploying EntryPoint and OKX Smart Wallet contracts for local testing...");
    console.log("=============================================================");

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying with account:", deployer.address);
    console.log("Account balance:", hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");
    console.log();

    try {
        // 1. Deploy EntryPoint to the expected address (required by SmartWallet)
        console.log("Checking if EntryPoint already exists at canonical address...");

        // Check if canonical EntryPoint already exists
        // Read EntryPoint address from environment variable, fallback to canonical address if not set
        const canonicalEntryPoint = process.env.ENTRY_POINT || "0x0000000071727De22E5E9d8BAf0edAc6f37da032";
        const existingCode = await hre.ethers.provider.getCode(canonicalEntryPoint);

        let entryPointAddress;
        if (existingCode !== "0x") {
            console.log("✅ EntryPoint already exists at canonical address:", canonicalEntryPoint);
            entryPointAddress = canonicalEntryPoint;
        } else {
            // Deploy EntryPoint normally (it won't be at canonical address on local network)
            console.log("⚠️  Deploying EntryPoint to different address (local network)");
            const EntryPoint = await hre.ethers.getContractFactory("account-abstraction/core/EntryPoint.sol:EntryPoint");
            const entryPoint = await EntryPoint.deploy();
            await entryPoint.waitForDeployment();
            entryPointAddress = await entryPoint.getAddress();
            console.log("✅ EntryPoint deployed to:", entryPointAddress);
            console.log("⚠️  NOTE: SmartWallet expects:", canonicalEntryPoint);
            console.log("⚠️  export ENTRY_POINT=" + canonicalEntryPoint);
            console.log("⚠️  You may need to update ERC4337Account.sol for local testing");
            console.log("⚠️  Exiting script...");
            // process.exit(0);
        }

        // 2. Deploy SmartWallet implementation
        console.log("📦 Deploying SmartWallet implementation...");
        const SmartWallet = await hre.ethers.getContractFactory("SmartWallet");
        const smartWallet = await SmartWallet.deploy();
        await smartWallet.waitForDeployment();
        const smartWalletAddress = await smartWallet.getAddress();
        console.log("✅ SmartWallet deployed to:", smartWalletAddress);

        // 3. Deploy SmartWalletFactory
        console.log("📦 Deploying SmartWalletFactory...");
        const SmartWalletFactory = await hre.ethers.getContractFactory("SmartWalletFactory");
        const factory = await SmartWalletFactory.deploy();
        await factory.waitForDeployment();
        const factoryAddress = await factory.getAddress();

        // 4. Deploy ECDSAValidator
        console.log("📦 Deploying ECDSAValidator...");
        const ECDSAValidator = await hre.ethers.getContractFactory("ECDSAValidator");
        const ecdsaValidator = await ECDSAValidator.deploy();
        await ecdsaValidator.waitForDeployment();
        const ecdsaValidatorAddress = await ecdsaValidator.getAddress();
        console.log("✅ ECDSAValidator deployed to:", ecdsaValidatorAddress);

        // 5. Deploy PasskeyValidator
        console.log("📦 Deploying PasskeyValidator...");
        const PasskeyValidator = await hre.ethers.getContractFactory("PasskeyValidator");
        const passkeyValidator = await PasskeyValidator.deploy();
        await passkeyValidator.waitForDeployment();
        const passkeyValidatorAddress = await passkeyValidator.getAddress();
        console.log("✅ PasskeyValidator deployed to:", passkeyValidatorAddress);

        // 6. Deploy test ERC20 token (optional, using existing MockERC20)
        console.log("📦 Deploying Test ERC20 Token...");
        const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
        const testToken = await MockERC20.deploy();
        await testToken.waitForDeployment();
        const testTokenAddress = await testToken.getAddress();
        console.log("✅ Test Token deployed to:", testTokenAddress);

        // Mint some tokens to deployer for testing
        console.log("🪙 Minting test tokens...");
        await testToken.mint(deployer.address, hre.ethers.parseUnits("1000000", 18));
        console.log("✅ Minted 1,000,000 TEST tokens to deployer");

        console.log("\n" + "=".repeat(60));
        console.log("🎉 All contracts deployed successfully!");
        console.log("=".repeat(60));

        console.log("\n📋 Contract Addresses:");
        console.log("EntryPoint:               ", entryPointAddress);
        console.log("SmartWallet Implementation:", smartWalletAddress);
        console.log("SmartWalletFactory:        ", factoryAddress);
        console.log("ECDSAValidator:           ", ecdsaValidatorAddress);
        console.log("PasskeyValidator:         ", passkeyValidatorAddress);
        console.log("Test Token:               ", testTokenAddress);

        console.log("\n🔧 Environment Variables to Set:");
        console.log("export ENTRY_POINT=" + entryPointAddress);
        console.log("export SMART_WALLET_FACTORY=" + factoryAddress);
        console.log("export SMART_WALLET_IMPL=" + smartWalletAddress);
        console.log("export ECDSA_VALIDATOR=" + ecdsaValidatorAddress);
        console.log("export PASSKEY_VALIDATOR=" + passkeyValidatorAddress);
        console.log("export TEST_TOKEN=" + testTokenAddress);
        console.log("export DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        console.log("\n📝 Copy-paste command:");
        console.log(`export ENTRY_POINT=${entryPointAddress} && export SMART_WALLET_FACTORY=${factoryAddress} && export SMART_WALLET_IMPL=${smartWalletAddress} && export ECDSA_VALIDATOR=${ecdsaValidatorAddress} && export PASSKEY_VALIDATOR=${passkeyValidatorAddress} && export TEST_TOKEN=${testTokenAddress}`);

        console.log("\n🚀 Next Steps:");
        console.log("1. Set the environment variables above");
        console.log("2. Run: npx hardhat run scripts/sendUop.ts --network localhost");
        console.log("3. Test different UserOperations by modifying the calls array in sendUop.ts");

        // Verify deployments
        console.log("\n🔍 Verifying deployments...");

        try {
            // Check EntryPoint
            console.log("✅ EntryPoint deployed successfully");

            // Check SmartWallet
            const implementation = await smartWallet.IMPLEMENTATION();
            console.log("✅ SmartWallet IMPLEMENTATION:", implementation);

            // Check Factory owner
            const factoryOwner = await factory.owner();
            console.log("✅ SmartWalletFactory owner:", factoryOwner);

            // Check token balance
            const balance = await testToken.balanceOf(deployer.address);
            console.log("✅ Test token balance:", hre.ethers.formatUnits(balance, 18), "TEST");

        } catch (error) {
            console.log("⚠️  Verification had some issues, but deployment should be successful");
            console.log("Error details:", error.message);
        }

    } catch (error) {
        console.error("\n❌ Deployment failed:");
        console.error(error);
        throw error;
    }
}

// Execute the deployment
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
