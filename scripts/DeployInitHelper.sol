// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "src/Storage.sol";
import "src/WalletCore.sol";
import "src/validator/ECDSAValidator.sol";
import "src/test/DeployFactory.sol";
import "lib/forge-std/src/Test.sol";

library DeployInitHelper {
    function deployContracts(
        DeployFactory deployFactory,
        bytes32 deployFactorySalt,
        string memory walletCoreName,
        string memory walletCoreVersion
    )
        internal
        returns (
            Storage storageImpl,
            ECDSAValidator ecdsaValidatorImpl,
            WalletCore walletCoreImpl
        )
    {
        // deploy Storage
        address payable storageAddr = deployFactory.deploy(
            type(Storage).creationCode,
            deployFactorySalt
        );
        storageImpl = Storage(storageAddr);

        // deploy ECDSAValidator
        address payable ecdsaValidatorAddr = deployFactory.deploy(
            type(ECDSAValidator).creationCode,
            deployFactorySalt
        );
        ecdsaValidatorImpl = ECDSAValidator(ecdsaValidatorAddr);

        // deploy WalletCore
        address payable walletCoreAddr = deployFactory.deploy(
            abi.encodePacked(
                type(WalletCore).creationCode,
                abi.encode(storageAddr, walletCoreName, walletCoreVersion) // constructor args
            ),
            deployFactorySalt
        );
        walletCoreImpl = WalletCore(walletCoreAddr);
    }
}
