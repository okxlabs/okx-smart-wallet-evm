/**
 * Update EntryPoint Address Utility
 * Helper script to update EntryPoint addresses across the project
 */

import * as fs from 'fs';
import * as path from 'path';

const hre = require('hardhat');

interface EntryPointUpdate {
    oldAddress: string;
    newAddress: string;
    filesUpdated: string[];
    success: boolean;
}

async function main() {
    const args = process.argv.slice(2);

    if (args.length < 1) {
        console.log("📖 Usage: npx hardhat run scripts/update-entrypoint.ts --network <network> -- <NEW_ENTRY_POINT_ADDRESS>");
        console.log("Example: npx hardhat run scripts/update-entrypoint.ts --network localhost -- 0x1234567890123456789012345678901234567890");
        return;
    }

    const newEntryPointAddress = args[0];

    if (!hre.ethers.isAddress(newEntryPointAddress)) {
        console.error("❌ Invalid address format:", newEntryPointAddress);
        return;
    }

    console.log("🔄 EntryPoint Address Update Utility");
    console.log("====================================");
    console.log("New EntryPoint address:", newEntryPointAddress);

    try {
        // Define files that need to be updated
        const filesToUpdate = [
            {
                path: 'src/ERC4337Account.sol',
                pattern: /return 0x[a-fA-F0-9]{40};/g,
                replacement: `return ${newEntryPointAddress};`,
                description: 'ERC4337Account entryPoint() function'
            }
        ];

        const updateResult: EntryPointUpdate = {
            oldAddress: '',
            newAddress: newEntryPointAddress,
            filesUpdated: [],
            success: true
        };

        for (const file of filesToUpdate) {
            const filePath = path.join(process.cwd(), file.path);

            if (!fs.existsSync(filePath)) {
                console.log(`⚠️  File not found: ${file.path}`);
                continue;
            }

            console.log(`📝 Updating ${file.path}...`);

            // Read current file content
            const content = fs.readFileSync(filePath, 'utf8');

            // Extract old address for tracking
            const oldAddressMatch = content.match(/return (0x[a-fA-F0-9]{40});/);
            if (oldAddressMatch && !updateResult.oldAddress) {
                updateResult.oldAddress = oldAddressMatch[1];
            }

            // Check if update is needed
            if (content.includes(newEntryPointAddress)) {
                console.log(`✅ ${file.path} already has correct EntryPoint address`);
                continue;
            }

            // Perform replacement
            const updatedContent = content.replace(file.pattern, file.replacement);

            if (content === updatedContent) {
                console.log(`⚠️  No changes made to ${file.path} - pattern not found`);
                continue;
            }

            // Write updated content
            fs.writeFileSync(filePath, updatedContent, 'utf8');
            updateResult.filesUpdated.push(file.path);
            console.log(`✅ Updated ${file.path}`);
        }

        // Update environment variable suggestion
        console.log("\n🔧 Environment Variable Update:");
        console.log("===============================");
        console.log(`export ENTRY_POINT=${newEntryPointAddress}`);

        // Verify the update by checking contract deployment
        console.log("\n🔍 Verifying EntryPoint...");
        const code = await hre.ethers.provider.getCode(newEntryPointAddress);
        if (code === "0x") {
            console.log("⚠️  Warning: No contract found at EntryPoint address");
            console.log("   Make sure the EntryPoint is deployed to this address");
        } else {
            console.log("✅ EntryPoint contract found");
            console.log("   Code length:", code.length, "bytes");
        }

        // Summary
        console.log("\n📊 Update Summary:");
        console.log("==================");
        console.log("Old EntryPoint:", updateResult.oldAddress || "N/A");
        console.log("New EntryPoint:", updateResult.newAddress);
        console.log("Files updated: ", updateResult.filesUpdated.length);
        updateResult.filesUpdated.forEach(file => console.log(`  - ${file}`));

        if (updateResult.filesUpdated.length > 0) {
            console.log("\n🚀 Next Steps:");
            console.log("1. Recompile contracts: yarn hardhat compile");
            console.log("2. Redeploy SmartWallet and other contracts");
            console.log("3. Update environment variables");
            console.log("4. Test with the new EntryPoint address");
        }

        console.log("\n✨ EntryPoint address update completed!");

    } catch (error) {
        console.error("\n❌ Update failed:");
        console.error(error.message);
        throw error;
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
