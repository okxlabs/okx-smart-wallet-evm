// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "src/SmartWallet.sol";
import "src/validator/ECDSAValidator.sol";
import "src/test/DeployFactory.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import "lib/forge-std/src/Test.sol";
import {Helper} from "src/test/Helper.sol";

library DeployInitHelper {
    function deployContracts(
        DeployFactory deployFactory,
        bytes32 deployFactorySalt
    )
        internal
        returns (
            ECDSAValidator ecdsaValidatorImpl,
            SmartWallet smartWalletImpl,
            SmartWalletFactory factoryImpl,
            Helper helperImpl
        )
    {
        // deploy ECDSAValidator
        address payable ecdsaValidatorAddr = deployFactory.deploy(
            type(ECDSAValidator).creationCode,
            deployFactorySalt
        );
        ecdsaValidatorImpl = ECDSAValidator(ecdsaValidatorAddr);

        // deploy SmartWallet
        address payable smartWalletAddr = deployFactory.deploy(
            type(SmartWallet).creationCode,
            deployFactorySalt
        );
        smartWalletImpl = SmartWallet(smartWalletAddr);

        factoryImpl = SmartWalletFactory(deployFactory.deploy(
            type(SmartWalletFactory).creationCode,
            deployFactorySalt
        ));

        helperImpl = Helper(deployFactory.deploy(
            type(Helper).creationCode,
            deployFactorySalt
        ));
    }
}