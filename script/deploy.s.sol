// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {IDeployFactory} from "./IDeployFactory.s.sol";
import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

/// @title DeployInit
/// @notice Deploys SmartWalletEntry (UUPS account implementation) and SmartWalletFactory
///         deterministically via the EIP-2470 Singleton Factory (CREATE2), with a plain-CREATE
///         fallback on chains where that factory is not present.
/// @dev Stage 9 deployment material. Run WITHOUT `--broadcast`/`--verify` for a dry run; the
///      operator appends those flags for real deployment (see docs/delivery/DEPLOY_RUNBOOK.md).
///      Both deployed contracts are CREATE2-eligible: neither binds any construction-time
///      privilege to msg.sender (the factory), so nothing is locked to the factory.
///        - SmartWalletEntry: constructor sets IMPLEMENTATION=address(this) and _disableInitializers();
///          the implementation is never owned (per-proxy owners are set later via initialize()).
///        - SmartWalletFactory: constructor sets the IMPLEMENTATION immutable from a parameter; ownerless.
contract DeployInit is Script {
    // EIP-2470 Singleton Factory — same canonical address on all chains (CREATE2; msg.sender==factory).
    address constant DEPLOY_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;

    // Canonical ERC-4337 v0.7 EntryPoint (hardcoded in ERC4337Account.entryPoint()).
    address constant EXPECTED_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    // TWA interface id (TransferWithAuthorization.INTERFACE_ID).
    bytes4 constant TWA_INTERFACE_ID = 0x86c5a9e1;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        address deployOwner = vm.addr(deployerKey);
        console.log("Deployer:", deployOwner);
        console.log("Deploy factory salt:");
        console.logBytes32(deployFactorySalt);
        console.log("Singleton factory:", DEPLOY_FACTORY);
        console.log("Singleton factory present on chain:", DEPLOY_FACTORY.code.length > 0);

        vm.startBroadcast(deployerKey);

        // 1) SmartWalletEntry implementation (no constructor args).
        bytes memory implInitCode = type(SmartWalletEntry).creationCode;
        address payable smartWalletAddr = payable(
            _deployDeterministic(implInitCode, deployFactorySalt, "SmartWalletEntry")
        );

        // 2) SmartWalletFactory(implementation) — constructor arg is the implementation address.
        bytes memory factoryInitCode = abi.encodePacked(
            type(SmartWalletFactory).creationCode,
            abi.encode(smartWalletAddr)
        );
        address payable factoryAddr = payable(
            _deployDeterministic(factoryInitCode, deployFactorySalt, "SmartWalletFactory")
        );

        vm.stopBroadcast();

        // --- Read-only post-deploy verification (simulation-time asserts) ---
        console.log("=== Deployment Verification ===");

        // Implementation wiring: the factory must point at the implementation we just deployed.
        require(
            SmartWalletFactory(factoryAddr).IMPLEMENTATION() == smartWalletAddr,
            "Factory implementation mismatch"
        );

        // The singleton factory must never be a privileged address. These contracts expose no
        // owner/admin/role setter, so privilege-to-factory is impossible by construction; we still
        // assert the factory is distinct from the deployed contracts as a defensive sanity check.
        require(factoryAddr != DEPLOY_FACTORY, "factory address collision");
        require(smartWalletAddr != DEPLOY_FACTORY, "impl address collision");

        // EntryPoint must be the canonical v0.7 address.
        require(
            SmartWalletEntry(smartWalletAddr).entryPoint() == EXPECTED_ENTRYPOINT,
            "Unexpected EntryPoint"
        );

        console.log("SmartWallet implementation verified on SmartWalletFactory!");
        console.log("=== Deployment Summary ===");
        console.log("Deployer:", deployOwner);
        console.log("SmartWallet Implementation address:", smartWalletAddr);
        console.log("SmartWalletFactory address:", factoryAddr);
        console.log("DeployInit script completed successfully");
    }

    /// @notice Deploys `initCode` deterministically via the EIP-2470 factory (CREATE2) when present,
    ///         otherwise falls back to plain CREATE from the SAME `initCode`.
    /// @dev CREATE2 path asserts the deployed address equals the predicted deterministic address.
    ///      CREATE fallback addresses depend on deployer nonce (not cross-chain deterministic) and
    ///      only occur where the singleton factory is absent.
    /// @param initCode Full creation code (creationCode || abi.encode(constructor args)).
    /// @param salt     CREATE2 salt (also logged for reproducibility).
    /// @param label    Human-readable contract label for logs.
    /// @return addr    The deployed contract address.
    function _deployDeterministic(
        bytes memory initCode,
        bytes32 salt,
        string memory label
    ) internal returns (address addr) {
        console.log("--- deploying", label);
        if (DEPLOY_FACTORY.code.length > 0) {
            // CREATE2 via the canonical singleton factory.
            address predicted = _predictCreate2Address(DEPLOY_FACTORY, salt, initCode);
            console.log("  method: create2 (EIP-2470 singleton factory)");
            console.log("  predicted address:", predicted);
            addr = IDeployFactory(DEPLOY_FACTORY).deploy(initCode, salt);
            require(addr != address(0), "create2 failed (already deployed at salt or factory error)");
            require(addr == predicted, "create2 address mismatch");
        } else {
            // Fallback: plain CREATE from the SAME initCode (reason: factory-unavailable).
            console.log("  method: create (fallback, reason=factory-unavailable)");
            assembly {
                addr := create(0, add(initCode, 0x20), mload(initCode))
            }
            require(addr != address(0), "create failed");
        }
        require(addr.code.length > 0, "no code at deployed address");
        console.log("  deployed at:", addr);
    }

    /// @notice Computes the EIP-2470 / standard CREATE2 address for `initCode` and `salt`.
    /// @dev EIP-2470 uses the provided salt directly (no msg.sender mixing).
    function _predictCreate2Address(
        address factory,
        bytes32 salt,
        bytes memory initCode
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), factory, salt, keccak256(initCode))
        );
        return address(uint160(uint256(hash)));
    }
}
