// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {LibClone} from "solady/utils/LibClone.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ISmartWalletFactory, InitialOwner} from "./interfaces/ISmartWalletFactory.sol";
import {Call, BatchedCall} from "./Types.sol";

contract SmartWalletFactory is ISmartWalletFactory {
    constructor() {}

    /// @notice create smart account with owners and validators
    /// @param implementation implementation address
    /// @param initialOwners initial owners
    /// @param salt salt
    function createAccount(
        address implementation,
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) public payable returns (address acount) {
        (bool alreadyDeployed, address instance) = LibClone
            .createDeterministicERC1967(
                msg.value,
                implementation,
                _getSalt(initialOwners, salt)
            );

        if (!alreadyDeployed) {
            ISmartWallet(instance).initialize(initialOwners);
        }

        emit AccountCreated(instance, implementation, initialOwners, salt);
        acount = instance;
    }

    /// @notice create smart account with owners and validators
    /// @param implementation implementation address
    /// @param initialOwners initial owners
    /// @param salt salt
    /// @param batchedCall batched call
    /// @param validatorData validator data
    function createAccountWithCall(
        address implementation,
        InitialOwner[] calldata initialOwners,
        uint256 salt,
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external payable returns (address acount) {
        acount = createAccount(implementation, initialOwners, salt);
        ISmartWallet(acount).executeWithRelayer(batchedCall, validatorData);
    }

    /// @notice predict deterministic address
    /// @param implementation implementation address
    /// @param initialOwners initial owners
    /// @param salt salt
    function getAddress(
        address implementation,
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) external view returns (address) {
        return
            LibClone.predictDeterministicAddressERC1967(
                implementation,
                _getSalt(initialOwners, salt),
                address(this)
            );
    }

    /// @notice get account salt
    /// @param initialOwners initial owners
    /// @param salt salt
    function _getSalt(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(initialOwners, salt));
    }
}
