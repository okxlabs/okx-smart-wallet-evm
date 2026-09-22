// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base} from "./Base.t.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";

/// @dev Target contract delegatecalled by `delegateAndRevert` (runs in the wallet's storage context).
contract DelegateTarget {
    function returns42() external pure returns (uint256) {
        return 42;
    }

    function boom() external pure {
        revert();
    }

    function writeSlot(uint256 slot, uint256 val) external {
        assembly {
            sstore(slot, val)
        }
    }
}

/// @notice Tests for the simulation helper `delegateAndRevert`, which delegatecalls an arbitrary target
///         and ALWAYS reverts with `DelegateAndRevert(success, returndata)` so no state change persists.
contract DelegateAndRevertTest is Base {
    DelegateTarget internal target;

    function setUp() public override {
        super.setUp();
        target = new DelegateTarget();
    }

    function test_delegateAndRevert_bubblesSuccessAndReturnData() public {
        bytes memory data = abi.encodeCall(DelegateTarget.returns42, ());
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.DelegateAndRevert.selector, true, abi.encode(uint256(42)))
        );
        ISmartWallet(_aliceWallet).delegateAndRevert(address(target), data);
    }

    function test_delegateAndRevert_bubblesFailure() public {
        bytes memory data = abi.encodeCall(DelegateTarget.boom, ());
        vm.expectRevert(abi.encodeWithSelector(ISmartWallet.DelegateAndRevert.selector, false, bytes("")));
        ISmartWallet(_aliceWallet).delegateAndRevert(address(target), data);
    }

    function test_delegateAndRevert_rollsBackStateWrite() public {
        uint256 slot = 0x1234;
        assertEq(uint256(vm.load(_aliceWallet, bytes32(slot))), 0, "slot starts empty");

        bytes memory data = abi.encodeCall(DelegateTarget.writeSlot, (slot, 999));
        vm.expectRevert(); // always reverts
        ISmartWallet(_aliceWallet).delegateAndRevert(address(target), data);

        // The terminal revert rolls back the delegatecall's storage write: nothing persists.
        assertEq(uint256(vm.load(_aliceWallet, bytes32(slot))), 0, "state write rolled back by revert");
    }
}
