// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Vm} from "lib/forge-std/src/Vm.sol";

/// @title EIP2470
/// @notice Library for deploying and interacting with the EIP-2470 Singleton Factory
/// @dev This library ensures the EIP-2470 factory is available for deterministic deployments
library EIP2470 {
    // EIP-2470 Singleton Factory deterministic address
    address public constant SINGLETON_FACTORY =
        0xce0042B868300000d44A59004Da54A005ffdcf9f;

    // Single-use deployment account from Nick's method
    address public constant DEPLOYMENT_ACCOUNT =
        0xBb6e024b9cFFACB947A71991E386681B1Cd1477D;

    // Exact amount needed for deployment (gas limit 247000 * gas price 100 gwei)
    uint256 public constant DEPLOYMENT_FUNDING = 0.0247 ether;

    // Pre-signed deployment transaction for EIP-2470 Singleton Factory
    // This transaction has fixed parameters as per EIP-2470:
    // - nonce: 0
    // - gasPrice: 100 gwei (0x174876e800)
    // - gasLimit: 247000 (0x3c4d8)
    // - value: 0
    // - v: 27, r: 0x247000, s: 0x2470 (special signature values)
    bytes public constant DEPLOYMENT_TX =
        hex"f9016c8085174876e8008303c4d88080b90154608060405234801561001057600080fd5b50610134806100206000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c80634af63f0214602d575b600080fd5b60cf60048036036040811015604157600080fd5b810190602081018135640100000000811115605b57600080fd5b820183602082011115606c57600080fd5b80359060200191846001830284011164010000000083111715608d57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550509135925060eb915050565b604080516001600160a01b039092168252519081900360200190f35b6000818351602085016000f5939250505056fea26469706673582212206b44f8a82cb6b156bfcc3dc6aadd6df4eefd204bc928a4397fd15dacf6d5320564736f6c634300060200331b83247000822470";

    /// @notice Ensures the EIP-2470 Singleton Factory is deployed
    /// @param vm The Forge VM instance for broadcasting transactions
    /// @return The address of the Singleton Factory (always 0xce0042B868300000d44A59004Da54A005ffdcf9f)
    function ensureDeployed(Vm vm) internal returns (address) {
        // Check if already deployed
        if (SINGLETON_FACTORY.code.length > 0) {
            return SINGLETON_FACTORY;
        }

        // Fund the deployment account if needed
        uint256 deploymentBalance = DEPLOYMENT_ACCOUNT.balance;
        if (deploymentBalance < DEPLOYMENT_FUNDING) {
            uint256 amountToSend = DEPLOYMENT_FUNDING - deploymentBalance;
            (bool fundSuccess, ) = DEPLOYMENT_ACCOUNT.call{value: amountToSend}(
                ""
            );
            require(fundSuccess, "Failed to fund deployment account");
        }

        // Broadcast the pre-signed deployment transaction
        vm.broadcastRawTransaction(DEPLOYMENT_TX);

        // Verify deployment
        require(
            SINGLETON_FACTORY.code.length > 0,
            "Singleton Factory deployment failed"
        );

        return SINGLETON_FACTORY;
    }
}
