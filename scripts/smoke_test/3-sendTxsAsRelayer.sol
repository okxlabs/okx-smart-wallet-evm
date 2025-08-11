// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "lib/forge-std/src/Script.sol";
import "src/WalletCore.sol";
import "src/interfaces/IStorage.sol";
import "src/ValidationLogic.sol";
import "src/Types.sol";

/// @title CreateDeployFactory
/// @notice A script for creating a deploy factory
contract SendTxsAsRelayer is Script {
    function run() external {
        uint256 senderPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(senderPk);

        address payable sender = payable(vm.addr(senderPk));
        address receiver = address(0xFeeCC911175C2B6D46BaE4fd357c995a4DC43C60);
        console.log("Sender: ", sender);
        console.log("Receiver: ", receiver);

        // Construct the call data for the WalletCore.execute() function
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: receiver, value: 0.00001 ether, data: ""});
        // calls[1] = Call({target: receiver, value: 0.00002 ether, data: ""});

        uint256 nonce = IStorage(WalletCore(sender).getMainStorage())
            .getNonce();
        bytes32 hash = ValidationLogic(sender).getValidationTypedHash(
            nonce,
            calls
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        address validator = address(1);
        IWalletCore(sender).executeWithValidator(calls, validator, signature);

        console.log("Completed ExecuteWithValidator script");
        vm.stopBroadcast();
    }
}
