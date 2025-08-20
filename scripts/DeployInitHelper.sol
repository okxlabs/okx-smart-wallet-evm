// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "src/WalletCore.sol";
import "src/validator/ECDSAValidator.sol";
import "src/test/DeployFactory.sol";
import "lib/forge-std/src/Test.sol";

library DeployInitHelper {
    function deployContracts(
        DeployFactory deployFactory,
        bytes32 deployFactorySalt
    )
        internal
        returns (
            ECDSAValidator ecdsaValidatorImpl,
            WalletCore walletCoreImpl
        )
    {
        // deploy ECDSAValidator
        address payable ecdsaValidatorAddr = deployFactory.deploy(
            type(ECDSAValidator).creationCode,
            deployFactorySalt
        );
        ecdsaValidatorImpl = ECDSAValidator(ecdsaValidatorAddr);

        // deploy WalletCore
        address payable walletCoreAddr = deployFactory.deploy(
            type(WalletCore).creationCode,
            deployFactorySalt
        );
        walletCoreImpl = WalletCore(walletCoreAddr);
    }
}