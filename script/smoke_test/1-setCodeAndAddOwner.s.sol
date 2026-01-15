// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {Call} from "src/Types.sol";

/// @title SetCodeAndAddOwner
/// @notice A script for setting code on EOA using EIP-7702 and adding an owner
contract SetCodeAndAddOwner is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address smartWalletImpl = vm.envAddress("SMART_WALLET");

        vm.startBroadcast(deployerPk);

        address deployer = vm.addr(deployerPk);
        console.log("EOA address: ", deployer);
        console.log(
            "Setting code for EIP7702 account with implementation: ",
            smartWalletImpl
        );

        // Sign and attach delegation to set the EOA's code to the SmartWallet implementation
        // This combines signing the EIP-7702 authorization and attaching it in one step
        vm.signAndAttachDelegation(smartWalletImpl, deployerPk);

        // Now the EOA has the SmartWallet code and built-in address(this) owner
        // Use execute to add a random owner (demonstrating the built-in owner privilege)
        address randomOwner = address(0x1234567890AbcdEF1234567890aBcdef12345678);
        bytes32 randomOwnerKeyHash = keccak256(abi.encodePacked(randomOwner));
        
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: deployer,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                randomOwnerKeyHash,
                address(0x0000000000000000000000000000000000000001), // ECDSA validator
                0 // no hook
            )
        });
        
        // Execute using the built-in address(this) owner privilege
        ISmartWallet(deployer).execute(calls);

        console.log("Added random owner successfully using built-in address(this) privilege");

        // Verify the code was set
        bytes memory code = deployer.code;
        console.log("EOA code length after delegation: ", code.length);

        vm.stopBroadcast();
    }
}