// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base} from "./Base.t.sol";
import {Call} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

contract UserOpSelectorTest is Base {
    function setUp() public override {
        super.setUp();
        _aliceWallet = payable(
            _deployAccountSingleOwner(_aliceWalletKeyHash, address(1), 111)
        );
        vm.deal(_aliceWallet, 10 ether);
    }

    function testFuzz_ValidateUserOp_RejectsWrongSelector(
        bytes4 selector,
        bool chainless
    ) external {
        vm.assume(selector != IERC4337Account.executeUserOp.selector);
        PackedUserOperation memory userOp = _signedUserOp(
            abi.encodePacked(selector, abi.encode(_addOwnerCalls())),
            chainless
        );

        assertEq(
            _testValidateUserOp(_aliceWallet, userOp, 0),
            Static.SIG_VALIDATION_FAILED
        );
        assertEq(INonceManager(_aliceWallet).getChainlessQueueState(0), 0);
    }

    function testFuzz_ValidateUserOp_RejectsShortCallData(
        uint8 length,
        bool chainless
    ) external {
        PackedUserOperation memory userOp = _signedUserOp(
            new bytes(bound(length, 0, 3)),
            chainless
        );

        // Reject without reverting on the selector slice or changing the queue.
        assertEq(
            _testValidateUserOp(_aliceWallet, userOp, 0),
            Static.SIG_VALIDATION_FAILED
        );
        assertEq(INonceManager(_aliceWallet).getChainlessQueueState(0), 0);
    }

    function test_ValidateUserOp_CallbackSelectorDoesNotConsumeChainlessQueue()
        external
    {
        PackedUserOperation memory userOp = _signedUserOp(
            abi.encodePacked(bytes4(0x150b7a02), abi.encode(_addOwnerCalls())),
            true
        );
        assertEq(
            _testValidateUserOp(_aliceWallet, userOp, 0),
            Static.SIG_VALIDATION_FAILED
        );
        assertEq(INonceManager(_aliceWallet).getChainlessQueueState(0), 0);
    }

    function test_RevertWhen_HandleOps_RegularCallbackSelector() external {
        _assertCallbackSelectorRejected(false);
    }

    function test_RevertWhen_HandleOps_ChainlessCallbackSelector() external {
        _assertCallbackSelectorRejected(true);
    }

    function _assertCallbackSelectorRejected(bool chainless) private {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _signedUserOp(
            abi.encodePacked(bytes4(0x150b7a02), abi.encode(_addOwnerCalls())),
            chainless
        );
        uint256 walletBalance = _aliceWallet.balance;

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA24 signature error"
            )
        );
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(_dave));

        assertEq(INonceManager(_aliceWallet).getChainlessQueueState(0), 0);
        assertEq(
            IEntryPoint(ENTRYPOINT_ADDRESS).getNonce(
                _aliceWallet,
                uint192(ops[0].nonce >> 64)
            ),
            ops[0].nonce
        );
        assertFalse(IOwnerManager(_aliceWallet).hasOwner(_makeKeyHash(_bob)));
        assertEq(_aliceWallet.balance, walletBalance);
    }

    function _signedUserOp(
        bytes memory callData,
        bool chainless
    ) private view returns (PackedUserOperation memory userOp) {
        userOp.sender = _aliceWallet;
        userOp.nonce = chainless ? _chainlessNonce(0, 7, 0) : 0;
        userOp.callData = callData;
        userOp.accountGasLimits = bytes32(
            (uint256(3_000_000) << 128) | uint256(500_000)
        );
        userOp.preVerificationGas = 21_000;
        userOp.gasFees = bytes32(
            (uint256(1 gwei) << 128) | uint256(1 gwei)
        );
        (userOp.signature, ) = _prepareAndSignUserOp(
            userOp,
            _alice,
            _alicePk,
            _aliceWallet
        );
    }

    function _addOwnerCalls() private view returns (Call[] memory) {
        return _buildAddOwnerCalls(
            _aliceWallet,
            _makeKeyHash(_bob),
            address(1),
            0
        );
    }
}
