// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {Ownable} from "solady/auth/Ownable.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {ISmartWallet} from "./interfaces/ISmartWallet.sol";
import {IFactory} from "./interfaces/IFactory.sol";

contract Factory is Ownable, UUPSUpgradeable, Initializable, IFactory {

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        _initializeOwner(msg.sender);
    }

    /// @notice create smart account with owners and validators
    /// @param implementation: implementation address
    /// @param owners: user's owner, eoa, passkey
    /// @param validators: contract address, can verify signatrue
    /// @param salt: salt
    function createAccount(
        address implementation,
        bytes32[] calldata owners,
        address[] calldata validators,
        uint256 salt
    ) external payable returns(address acount) {
        (bool alreadyDeployed, address instance) = LibClone.createDeterministicERC1967(
            msg.value,
            implementation, 
            _getSalt(owners, validators, salt)
        );

        if(!alreadyDeployed) {
            ISmartWallet(instance).initilize(owners, validators);
        }

        emit AccountCreated(instance, implementation, owners, validators, salt);
        acount = instance;
    }

    /// @notice predict deterministic address
    /// @param implementation: implementation address
    /// @param owners: user's owner, eoa, passkey
    /// @param validators: contract address, can verify signatrue
    /// @param salt: salt
    function getAddress(
        address implementation,
        bytes32[] calldata owners,  
        address[] calldata validators,
        uint256 salt
    ) external view returns(address) {
        return LibClone.predictDeterministicAddressERC1967(
            implementation, 
            _getSalt(owners, validators, salt),
            address(this)
        );
    }

    /// @notice get account salt
    /// @param owners: user's owner, eoa, passkey
    /// @param validators: contract address, can verify signatrue
    /// @param salt: salt
    function _getSalt(
        bytes32[] calldata owners,
        address[] calldata validators,
        uint256 salt
    ) internal pure returns(bytes32) {
        return keccak256(abi.encode(owners, validators, salt));
    }


    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
}   