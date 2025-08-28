// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {OKXSmartWalletEntry} from "src/OKXSmartWalletEntry.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {DeployFactory} from "src/test/DeployFactory.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

library DeployInitHelper {
    function deployContracts(
        DeployFactory deployFactory,
        bytes32 deployFactorySalt
    )
        internal
        returns (
            ECDSAValidator ecdsaValidatorImpl,
            PasskeyValidator passkeyValidatorImpl,
            OKXSmartWalletEntry smartWalletImpl,
            SmartWalletFactory factoryImpl
        )
    {
        // deploy ECDSAValidator
        address payable ecdsaValidatorAddr = deployFactory.deploy(
            type(ECDSAValidator).creationCode,
            deployFactorySalt
        );
        ecdsaValidatorImpl = ECDSAValidator(ecdsaValidatorAddr);

        // deploy PasskeyValidator
        address payable passkeyValidatorAddr = deployFactory.deploy(
            type(PasskeyValidator).creationCode,
            deployFactorySalt
        );
        passkeyValidatorImpl = PasskeyValidator(passkeyValidatorAddr);

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