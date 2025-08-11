// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IValidation} from "src/interfaces/IValidation.sol";
import "src/libraries/Errors.sol";
import {Static} from "src/libraries/Static.sol";

contract ValidatorTest is Base {
    using Clones for address;
    address internal _charlie;
    uint256 internal _charliePk;

    event ValidatorAdded(address validator);
    event ValidatorRemoved(address validator);
    error FailedDeployment();

    function setUp() public override {
        (_charlie, _charliePk) = makeAddrAndKey("charlie");
        super.setUp();
    }

    function test_addValidator_reverts_for_non_owner() public {
        vm.prank(_bob);

        address validatorAddress = _getEdcsaValidatorAddress(
            _alice,
            _charlie,
            address(_ecdsaValidatorImpl)
        );

        // Expect not from self revert
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        IWalletCore(_alice).addValidator(
            keccak256(abi.encodePacked(address(this))),
            validatorAddress
        );
    }

    function test_addValidator_reverts_for_invalid_implementation() public {
        vm.prank(_alice);
        address dave = vm.addr(2);

        // Expect invalid validator implementation revert - for new interface, just pass invalid address
        vm.expectRevert();
        IWalletCore(_alice).addValidator(
            keccak256(abi.encodePacked(address(this))),
            dave // Invalid validator address
        );
    }

    function test_addValidator_reverts_for_duplicate() public {
        // Deploy and add validator using helper
        address validatorAddress = _addValidator(_alice);

        // Expect failed if duplicate validator (same keyHash)
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        vm.prank(_alice);
        vm.expectRevert();
        IWalletCore(_alice).addValidator(keyHash, validatorAddress);
    }

    function test_validator_can_be_added() public {
        // Compute validator address (both should be the same)
        address charlieValidator = _getEdcsaValidatorAddress(
            _alice,
            _charlie,
            address(_ecdsaValidatorImpl)
        );

        // Expect validator added event
        vm.expectEmit();
        emit ValidatorAdded(charlieValidator);

        // Deploy and add validator using the helper
        address deployedValidator = _addValidator(_alice, _charlie);

        assertEq(ECDSAValidator(deployedValidator).getSigner(), _charlie);
    }

    function test_new_validator_can_validate_transactions() public {
        // Deploy and add validator using helper
        _addValidator(_alice, _charlie);

        Call[] memory calls = _construct_calls_data();
        uint256 executionGas = _get_execution_gas(calls.length);

        // Relayer executes with Charlie signature
        vm.prank(_bob);
        bytes32 hash = _getValidationTypedHash(
            _alice,
            relayerCalls,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _charlie,
            _charliePk,
            hash
        );
        IWalletCore(_alice).executeFromRelayer(calls, validatorData);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_validator_management_succeeds() public {
        // First add a valid validator
        address aliceECDSAValidator = _addValidator(_alice);
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));

        vm.startPrank(_alice);
        // Test that we can add another validator for the same keyHash (this should work as setValidator allows overwriting)
        IStorage(WalletCore(payable(_alice)).getMainStorage()).setValidator(
            keyHash,
            aliceECDSAValidator
        );

        // Test removing the validator
        IStorage(WalletCore(payable(_alice)).getMainStorage()).removeValidator(
            keyHash
        );
    }
}
