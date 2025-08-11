// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {MockERC20} from "src/test/MockERC20.sol";

import "forge-std/console.sol";

contract ExecutionTest is Base {
    MockERC20 mockToken;
    MockERC20 mockToken2;

    function setUp() public override {
        super.setUp();

        vm.prank(_alice);
        mockToken = new MockERC20();

        vm.prank(_bob);
        mockToken2 = new MockERC20();
    }

    function test_executeFromSelf_succeeds_for_owner() public {
        vm.prank(_alice);
        Call[] memory calls = _construct_calls_data();
        IWalletCore(_alice).executeFromSelf(calls);
    }

    function test_executeFromSelf_reverts_for_non_owner() public {
        vm.prank(_bob);
        Call[] memory calls = _construct_calls_data();
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        IWalletCore(_alice).executeFromSelf(calls);
    }

    function test_executeFromSelf_reverts_on_failed_call() public {
        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1000 ether, data: ""}); // will fail
        vm.expectRevert(
            abi.encodeWithSelector(Errors.CallFailed.selector, 1, 0, "")
        );
        IWalletCore(_alice).executeFromSelf(calls);
    }

    function test_executeWithRelayer_succeeds_as_owner() public {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_alice);
        Call[] memory calls = _construct_calls_data();
        uint256 executionGas = _get_execution_gas(calls.length);
        bytes32 hash = _getValidationTypedHash(
            _alice,
            emptyRelayerCalls,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        uint256 gasStart = gasleft();

        IWalletCore(_alice).executeFromRelayer(calls, validatorData);

        uint256 gasEnd = gasleft();
        console.log("gas used", gasStart - gasEnd);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeWithRelayer_succeeds_as_relayer() public {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_bob);
        Call[] memory calls = _construct_calls_data();
        uint256 executionGas = _get_execution_gas(calls.length);
        bytes32 hash = _getValidationTypedHash(
            _alice,
            emptyRelayerCalls,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        uint256 gasStart = gasleft();

        IWalletCore(_alice).executeFromRelayer(calls, validatorData);

        uint256 gasEnd = gasleft();
        console.log("gas used", gasStart - gasEnd);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeWithRelayer_initialization_on_first_time() public {
        (address charlie, uint256 charliePk) = makeAddrAndKey("charlie");
        vm.deal(charlie, 1 ether);
        _setCodeToEOA(address(_walletCore), charlie);

        // Initialize charlie's wallet storage
        vm.prank(charlie);
        IWalletCore(charlie).initialize();

        // Add validator for charlie before executing
        _addValidator(charlie);

        Call[] memory calls = _construct_calls_data();
        uint256 executionGas = _get_execution_gas(calls.length);

        vm.prank(_alice);
        bytes32 hash = _getValidationTypedHash(
            charlie,
            relayerCalls,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            charlie,
            charliePk,
            hash
        );
        IWalletCore(charlie).executeFromRelayer(calls, validatorData);

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeWithRelayer_reverts_on_failed_payment() public {
        // Register validator first
        _addValidator(_alice);

        assertEq(mockToken2.balanceOf(_alice), 0);
        vm.prank(_alice);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        uint256 executionGas = _get_execution_gas(calls.length);

        Call[] memory failingRelayerPayment = new Call[](1);
        failingRelayerPayment[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken2)),
            _bob,
            10
        );

        bytes32 hash = _getValidationTypedHash(
            _alice,
            failingRelayerPayment,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        vm.expectRevert();
        IWalletCore(_alice).executeFromRelayer(calls, validatorData);
    }

    function test_executeWithRelayer_succeeds_on_payment() public {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_alice);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        uint256 executionGas = _get_execution_gas(calls.length);

        Call[] memory relayerPayment = new Call[](1);
        relayerPayment[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken)),
            _bob,
            10
        );

        bytes32 hash = _getValidationTypedHash(
            _alice,
            relayerPayment,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );
        IWalletCore(_alice).executeFromRelayer(calls, validatorData);

        assertEq(mockToken.balanceOf(_bob), 10);
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeWithRelayer_payment_succeeds_even_with_failed_call()
        public
    {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_alice);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1000 ether, data: ""});
        uint256 executionGas = _get_execution_gas(calls.length);

        Call[] memory relayerPayment = new Call[](1);
        relayerPayment[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken)),
            _bob,
            10
        );

        bytes32 hash = _getValidationTypedHash(
            _alice,
            relayerPayment,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );
        IWalletCore(_alice).executeFromRelayer(calls, validatorData);

        assertEq(mockToken.balanceOf(_bob), 10);
        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeWithRelayer_succeeds_on_free_gas_mode() public {
        // Register validator first
        _addValidator(_alice);

        vm.prank(_bob);
        Call[] memory calls = new Call[](1);
        // calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[0] = _construct_erc20_transfer_call(
            IERC20(address(mockToken)),
            _bob,
            10
        );

        uint256 executionGas = _get_execution_gas(calls.length);

        Call[] memory relayerPayment = new Call[](0); // Empty for free gas mode

        bytes32 hash = _getValidationTypedHash(
            _alice,
            relayerPayment,
            calls,
            executionGas
        );
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );
        IWalletCore(_alice).executeFromRelayer(calls, validatorData);

        assertEq(mockToken.balanceOf(_bob), 10);
        // assertEq(address(_bob).balance, 0 ether);
    }
}
