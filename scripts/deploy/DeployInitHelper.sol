// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {OKXSmartWalletEntry} from "src/OKXSmartWalletEntry.sol";
import {IDeployFactory} from "../utils/IDeployFactory.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

library DeployInitHelper {
    function deployContracts(
        IDeployFactory deployFactory,
        bytes32 deployFactorySalt
    )
        internal
        returns (
            OKXSmartWalletEntry smartWalletImpl,
            SmartWalletFactory factoryImpl
        )
    {
        // deploy SmartWallet
        address payable smartWalletAddr = deployFactory.deploy(
            type(OKXSmartWalletEntry).creationCode,
            deployFactorySalt
        );
        smartWalletImpl = OKXSmartWalletEntry(smartWalletAddr);

        factoryImpl = SmartWalletFactory(deployFactory.deploy(
            abi.encodePacked(
                type(SmartWalletFactory).creationCode,
                abi.encode(address(smartWalletImpl))
            ),
            deployFactorySalt
        ));
    }
}