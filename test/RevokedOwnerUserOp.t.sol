// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base} from "./Base.t.sol";
import {IHook} from "src/interfaces/IHook.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Call} from "src/Types.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

contract RejectAllUserOpHook is IHook {
    function preCheck(
        Call[] calldata,
        address
    ) external payable returns (bytes memory) {
        revert("blocked");
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(
        address,
        bytes32,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }
}

contract RevokedOwnerUserOpTest is Base {
    function test_RevertWhen_OwnerExpiredEarlierInSameBundle() external {
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));

        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(1),
            _packSettings(false, 0, address(0))
        );

        vm.warp(100);
        uint256 expiredSettings = _packSettings(false, 99, address(0));

        Call[] memory expiration = new Call[](1);
        expiration[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeCall(
                IOwnerManager.updateOwner,
                (bobKeyHash, address(1), expiredSettings)
            )
        });

        Call[] memory transfer = new Call[](1);
        transfer[0] = Call({target: _bob, value: 1 ether, data: ""});

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = _buildUserOp(0, expiration);
        (ops[0].signature, ) = _prepareAndSignUserOp(
            ops[0],
            _alice,
            _alicePk,
            _aliceWallet
        );

        ops[1] = _buildUserOp(1, transfer);
        (ops[1].signature, ) = _prepareAndSignUserOp(
            ops[1],
            _bob,
            _bobPk,
            _aliceWallet
        );

        uint256 bobBalanceBefore = _bob.balance;
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(_dave));

        assertTrue(
            IOwnerManager(_aliceWallet).hasOwner(bobKeyHash),
            "expired owner must remain registered"
        );
        assertEq(
            _getOwnerSettings(_aliceWallet, bobKeyHash),
            expiredSettings,
            "expired owner settings must remain readable"
        );
        (address validator, ) = IOwnerManager(_aliceWallet).getOwnerConfig(
            bobKeyHash
        );
        assertEq(
            validator,
            address(0),
            "expired owner must not have an active validator"
        );
        assertEq(
            _bob.balance,
            bobBalanceBefore,
            "expired owner must not execute after validation"
        );
    }

    function test_RevertWhen_RestrictedOwnerRemovedEarlierInSameBundle()
        external
    {
        RejectAllUserOpHook hook = new RejectAllUserOpHook();
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 bobSettings = _packSettings(
            false,
            0,
            address(hook)
        );

        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(1),
            bobSettings
        );
        assertEq(
            _getOwnerSettings(_aliceWallet, bobKeyHash),
            bobSettings
        );

        Call[] memory removal = new Call[](1);
        removal[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeCall(IOwnerManager.removeOwner, (bobKeyHash))
        });

        Call[] memory transfer = new Call[](1);
        transfer[0] = Call({target: _bob, value: 1 ether, data: ""});

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = _buildUserOp(0, removal);
        (ops[0].signature, ) = _prepareAndSignUserOp(
            ops[0],
            _alice,
            _alicePk,
            _aliceWallet
        );

        ops[1] = _buildUserOp(1, transfer);
        (ops[1].signature, ) = _prepareAndSignUserOp(
            ops[1],
            _bob,
            _bobPk,
            _aliceWallet
        );

        uint256 bobBalanceBefore = _bob.balance;
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(_dave));

        assertFalse(IOwnerManager(_aliceWallet).hasOwner(bobKeyHash));
        (address validator, uint256 settings) = IOwnerManager(_aliceWallet)
            .getOwnerConfig(bobKeyHash);
        assertEq(validator, address(0));
        assertEq(settings, 0);
        assertEq(
            _bob.balance,
            bobBalanceBefore,
            "revoked owner must not execute after its hook is deleted"
        );
    }

    function _buildUserOp(
        uint256 nonce,
        Call[] memory calls
    ) private view returns (PackedUserOperation memory userOp) {
        userOp.sender = _aliceWallet;
        userOp.nonce = nonce;
        userOp.callData = abi.encodePacked(
            IERC4337Account.executeUserOp.selector,
            abi.encode(calls)
        );
        userOp.accountGasLimits = bytes32(
            (uint256(3_000_000) << 128) | uint256(500_000)
        );
        userOp.preVerificationGas = 21_000;
        userOp.gasFees = bytes32(
            (uint256(1 gwei) << 128) | uint256(1 gwei)
        );
    }
}
