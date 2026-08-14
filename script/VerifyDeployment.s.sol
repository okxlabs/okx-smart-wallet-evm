// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

/// @title VerifyDeployment
/// @notice Read-only post-deploy verification template for a SmartWallet deployment.
/// @dev Stage 9 deployment material. Pure read-only — performs NO broadcast, requires NO private
///      key, and sends NO transactions. Run against an RPC (or fork) after deployment:
///        SMART_WALLET=<impl> SMART_WALLET_FACTORY=<factory> \
///          forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"
///      Optionally set EXPECTED_CHAIN_ID to assert the connected chain.
///      Does NOT perform live explorer verification (that is an operator step, not part of Stage 9).
contract VerifyDeployment is Script {
    address constant DEPLOY_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    address constant EXPECTED_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    bytes4 constant TWA_INTERFACE_ID = 0x86c5a9e1;

    function run() external view {
        address impl = vm.envAddress("SMART_WALLET");
        address factory = vm.envAddress("SMART_WALLET_FACTORY");
        uint256 expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", uint256(0));

        console.log("=== VerifyDeployment (read-only) ===");
        console.log("chainid:", block.chainid);
        console.log("implementation:", impl);
        console.log("factory:", factory);

        if (expectedChainId != 0) {
            require(block.chainid == expectedChainId, "chain id mismatch");
        }

        // Both addresses must have code.
        require(impl.code.length > 0, "no code at implementation address");
        require(factory.code.length > 0, "no code at factory address");

        // Neither contract may be the singleton factory.
        require(impl != DEPLOY_FACTORY, "implementation collides with singleton factory");
        require(factory != DEPLOY_FACTORY, "factory collides with singleton factory");

        // Factory must point at the implementation.
        require(
            SmartWalletFactory(factory).IMPLEMENTATION() == impl,
            "factory IMPLEMENTATION mismatch"
        );

        // Implementation self-reference (set in SmartWallet constructor).
        require(
            SmartWalletEntry(payable(impl)).IMPLEMENTATION() == impl,
            "implementation self-reference mismatch"
        );

        // Canonical EntryPoint v0.7.
        require(
            SmartWalletEntry(payable(impl)).entryPoint() == EXPECTED_ENTRYPOINT,
            "unexpected EntryPoint"
        );

        // TWA interface id advertised.
        require(
            SmartWalletEntry(payable(impl)).supportsInterface(TWA_INTERFACE_ID),
            "TWA interface id not advertised"
        );

        console.log("All read-only post-deploy checks passed.");
    }
}
