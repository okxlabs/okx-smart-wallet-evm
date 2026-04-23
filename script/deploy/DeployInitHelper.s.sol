// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {IDeployFactory} from "./IDeployFactory.s.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

library DeployInitHelper {
    function deployContracts(
        IDeployFactory deployFactory,
        bytes32 deployFactorySalt
    )
        internal
        returns (
            SmartWalletEntry smartWalletImpl,
            SmartWalletFactory factoryImpl
        )
    {
        // deploy SmartWallet
        address payable smartWalletAddr = deployFactory.deploy(
            type(SmartWalletEntry).creationCode,
            deployFactorySalt
        );
        smartWalletImpl = SmartWalletEntry(smartWalletAddr);

        factoryImpl = SmartWalletFactory(
            deployFactory.deploy(
                abi.encodePacked(
                    type(SmartWalletFactory).creationCode,
                    abi.encode(address(smartWalletImpl))
                ),
                deployFactorySalt
            )
        );
    }
}
