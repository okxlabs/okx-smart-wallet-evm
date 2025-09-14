// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base, MockERC20} from "./Base.t.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC712} from "src/ERC712.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";

// Test contract with various test functions
contract TestTarget {
    uint256 public value = 42;

    function returnSuccess() public pure returns (bool) {
        return true;
    }

    function returnValue() public view returns (uint256) {
        return value;
    }

    function returnConstant() public pure returns (uint256) {
        return 42;
    }

    function setValue(uint256 _value) public {
        value = _value;
    }

    function failingFunction() public pure {
        revert("Intentional failure");
    }

    function customErrorFunction() public pure {
        revert CustomError("Custom message");
    }

    function requireFunction(bool condition) public pure {
        require(condition, "Condition not met");
    }

    error CustomError(string message);
}

contract SimulationTest is Base {
    TestTarget public target;
    MockERC20 public token;

    // Helper to decode DelegateAndRevert error
    function decodeDelegateAndRevert(
        bytes memory errorData
    ) internal pure returns (bool success, bytes memory returnData) {
        // Skip the error selector (4 bytes)
        require(errorData.length >= 4, "Error data too short");

        // The error is: DelegateAndRevert(bool success, bytes returnData)
        // Decode the ABI-encoded parameters
        (success, returnData) = abi.decode(
            slice(errorData, 4, errorData.length - 4),
            (bool, bytes)
        );
    }

    // Helper function to slice bytes
    function slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    function setUp() public override {
        super.setUp();
        target = new TestTarget();
        token = new MockERC20();

        // Fund the wallet
        vm.deal(_aliceWallet, 10 ether);
        token.mint(_aliceWallet, 1000 * 1e18);
    }

    // ============ DelegateAndRevert Basic Tests ============

    function test_DelegateAndRevert_SuccessfulCall_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.returnSuccess.selector
        );

        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(target),
                callData
            )
        {
            revert("Should have reverted with DelegateAndRevert");
        } catch (bytes memory revertData) {
            // Decode the DelegateAndRevert error
            (bool success, bytes memory returnData) = decodeDelegateAndRevert(
                revertData
            );

            assertTrue(success, "Call should have succeeded");
            assertEq(
                returnData,
                abi.encode(true),
                "Return value should be true"
            );
        }
    }

    function test_DelegateAndRevert_WithReturnData_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.returnConstant.selector
        );

        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(target),
                callData
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, bytes memory returnData) = decodeDelegateAndRevert(
                revertData
            );

            assertTrue(success, "Call should have succeeded");
            uint256 returnedValue = abi.decode(returnData, (uint256));
            assertEq(returnedValue, 42, "Return value should be 42");
        }
    }

    function test_DelegateAndRevert_FailedCall_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.failingFunction.selector
        );

        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(target),
                callData
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, bytes memory returnData) = decodeDelegateAndRevert(
                revertData
            );

            assertFalse(success, "Call should have failed");
            // The return data contains the revert reason
            assertTrue(returnData.length > 0, "Should have revert data");
        }
    }

    function test_DelegateAndRevert_WithRevert_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.requireFunction.selector,
            false
        );

        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(target),
                callData
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, ) = decodeDelegateAndRevert(revertData);
            assertFalse(success, "Call should have failed");
        }
    }

    function test_DelegateAndRevert_WithCustomError_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.customErrorFunction.selector
        );

        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(target),
                callData
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, ) = decodeDelegateAndRevert(revertData);
            assertFalse(success, "Call should have failed");
        }
    }

    function test_DelegateAndRevert_InvalidTarget_Success() public {
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.returnSuccess.selector
        );

        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(0), // Invalid target (EOA with no code)
                callData
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, ) = decodeDelegateAndRevert(revertData);
            // EVM's delegatecall to address 0 (or any EOA) returns success but executes no code
            assertTrue(
                success,
                "Call to address 0 should return success (no code executed)"
            );
        }
    }

    function test_DelegateAndRevert_EmptyCalldata_Success() public {
        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(target),
                "" // Empty calldata
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, ) = decodeDelegateAndRevert(revertData);
            // The behavior with empty calldata depends on the target's fallback
            // In this case, TestTarget doesn't have a fallback, so it should fail
            assertFalse(success, "Call should have failed");
        }
    }

    // ============ Simulation via DelegateAndRevert Tests ============

    function test_DelegateAndRevert_Simulate_Execute_Success() public {
        // Prepare a simple execute call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(token),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                100 * 1e18
            )
        });

        // Encode the execute function call
        bytes memory executeCalldata = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        // Check initial balance
        uint256 initialBalance = token.balanceOf(_bob);

        // Simulate the execute call
        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                _aliceWallet, // Delegate to self
                executeCalldata
            )
        {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            (bool success, ) = decodeDelegateAndRevert(revertData);
            assertTrue(success, "Simulation should succeed");
        }

        // Verify that the actual state wasn't changed
        assertEq(
            token.balanceOf(_bob),
            initialBalance,
            "Token balance should not have changed"
        );
    }

    // Additional simulation tests would need to be reimplemented
    // based on the actual SmartWalletSimulator interface

    // ============ Helper Functions ============

    function _getNonce(
        address wallet,
        bytes32 keyHash
    ) internal view returns (uint256) {
        return INonceManager(wallet).getNonce(uint192(uint256(keyHash)));
    }

    function _getTypedDataHash(
        address wallet,
        BatchedCall memory batchedCall,
        uint48 validUntil
    ) internal view returns (bytes32) {
        // Import BatchedCallLib to use the hash function
        bytes32 intentHash = keccak256(
            abi.encode(
                batchedCall.calls,
                batchedCall.nonce,
                validUntil,
                ISmartWallet(wallet).IMPLEMENTATION()
            )
        );
        return ERC712(wallet).hashTypedData(intentHash);
    }

    function _addOwnerAsAdmin(
        address admin,
        address wallet,
        bytes32 newKeyHash,
        address validator,
        uint256 settings
    ) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: wallet,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newKeyHash,
                validator,
                settings
            )
        });

        vm.prank(admin);
        ISmartWallet(wallet).execute(calls);
    }

    // ============ delegateAndRevert Edge Cases ============

    function test_DelegateAndRevert_simulation_wallet() public {
        TestTarget localTarget = new TestTarget();
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.returnSuccess.selector
        );

        try _simulator.delegateAndRevert(address(localTarget), callData) {
            revert("Should have reverted");
        } catch (bytes memory revertData) {
            // Decode the DelegateAndRevert error
            (bool success, bytes memory ret) = decodeDelegateAndRevert(
                revertData
            );

            assertTrue(success, "Call should have succeeded");
            assertEq(ret, abi.encode(true), "Return value should be true");
        }
    }

    function test_DelegateAndRevert_gas_comparison() public {
        TestTarget localTarget = new TestTarget();
        bytes memory callData = abi.encodeWithSelector(
            TestTarget.returnSuccess.selector
        );

        // Test gas usage of direct call vs delegateAndRevert
        uint256 directGasBefore = gasleft();
        localTarget.returnSuccess();
        uint256 directGasAfter = gasleft();
        uint256 directGasUsed = directGasBefore - directGasAfter;

        uint256 delegateGasBefore = gasleft();
        try
            ISmartWallet(_aliceWallet).delegateAndRevert(
                address(localTarget),
                callData
            )
        {
            revert("Should have reverted");
        } catch (bytes memory) {
            uint256 delegateGasAfter = gasleft();
            uint256 delegateGasUsed = delegateGasBefore - delegateGasAfter;

            console.log("Direct call gas used:", directGasUsed);
            console.log("DelegateAndRevert gas used:", delegateGasUsed);
            console.log("Overhead:", delegateGasUsed - directGasUsed);

            // DelegateAndRevert should use more gas due to delegatecall overhead
            assertTrue(
                delegateGasUsed > directGasUsed,
                "DelegateAndRevert should use more gas"
            );
        }
    }
}
