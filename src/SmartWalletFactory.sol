// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {LibClone} from "solady/utils/LibClone.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {ISmartWalletFactory, InitialOwner} from "./interfaces/ISmartWalletFactory.sol";
import {BatchedCall} from "./Types.sol";

contract SmartWalletFactory is ISmartWalletFactory {
    address public immutable implementation;

    /// @notice constructor
    /// @param _implementation implementation address
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /// @notice create smart account with owners and validators
    /// @param initialOwners initial owners
    /// @param salt salt
    function createAccount(
        InitialOwner[] calldata initialOwners,
        uint256 salt
    ) public payable returns (address account) {
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
        account = instance;
    }

    /// @notice create smart account with owners and validators
    /// @param initialOwners initial owners
    /// @param salt salt
    /// @param batchedCall batched call
    /// @param validatorData validator data
    function createAccountWithCall(
        InitialOwner[] calldata initialOwners,
        uint256 salt,
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external payable returns (address acount) {
        acount = createAccount(initialOwners, salt);
        ISmartWallet(acount).executeWithRelayer(batchedCall, validatorData);
    }

    /// @notice predict deterministic address
    /// @param initialOwners initial owners
    /// @param salt salt
    function getAddress(
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
