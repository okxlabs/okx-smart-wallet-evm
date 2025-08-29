// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import {EIP2470} from "./EIP2470.sol";

/// @title DeploySingletonFactory
/// @notice Deploys the EIP-2470 Singleton Factory for deterministic contract deployment
/// @dev Uses the EIP2470 library for standardized deployment
contract DeploySingletonFactory is Script {
    
    function run() external returns (address) {
        uint256 deployerPk = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d));
        
        vm.startBroadcast(deployerPk);
        
        console.log("=== EIP-2470 Singleton Factory Deployment ===");
        
        // Use the library to ensure the factory is deployed
        address factoryAddress = EIP2470.ensureDeployed(vm);
        
        if (factoryAddress == EIP2470.SINGLETON_FACTORY) {
            console.log("EIP-2470 Singleton Factory is ready at:", factoryAddress);
        }
        
        console.log("\n=== Deployment Complete ===");
        
        vm.stopBroadcast();
        
        // Return the Singleton Factory address for compatibility
        return factoryAddress;
    }
}