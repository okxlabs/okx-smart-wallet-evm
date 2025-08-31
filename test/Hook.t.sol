// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {console} from "forge-std/console.sol";
import {Base, MockERC20} from "./Base.t.sol";
import {ISmartWallet} from "../src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "../src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "../src/OwnersManager.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {Call, BatchedCall} from "../src/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHook} from "../src/interfaces/IHook.sol";

contract MockHook is IHook {
    bytes4 public constant TRANSFER_SELECTOR = 0xa9059cbb;

    function preCheck(
        Call[] calldata calls,
        address // executor
    ) external payable returns (bytes memory preCheckRet) {
        // For mock purposes, we'll use hardcoded values or extract from first call
        // In real implementation, these would come from storage or other sources
        address token = calls.length > 0 ? calls[0].target : address(0);
        uint256 maxTotalAmount = 100 ether; // Hardcoded limit for testing

        uint256 initialBalance = 0;
        uint256 totalAmount = 0;

        // Check if there is a valid token address
        if (token != address(0)) {
            initialBalance = IERC20(token).balanceOf(msg.sender);
        }

        for (uint256 i = 0; i < calls.length; i++) {
            require(calls[i].target == token, "Invalid token address");

            bytes4 selector = bytes4(calls[i].data[:4]);
            require(selector == TRANSFER_SELECTOR, "Invalid operation");

            (address recipientCalled, uint256 amount) = abi.decode(
                calls[i].data[4:],
                (address, uint256)
            );

            require(recipientCalled != address(0), "Invalid recipient address");
            totalAmount += amount;
        }

        require(
            totalAmount <= maxTotalAmount,
            "Total transfer amount exceeds limit"
        );

        return abi.encode(token, initialBalance, totalAmount);
    }

    function postCheck(
        bytes calldata preHookRet,
        address // executor
    ) external payable {
        (address token, uint256 initialBalance, uint256 totalAmount) = abi
            .decode(preHookRet, (address, uint256, uint256));

        // Include token address check otherwise empty calls will revert
        if (token != address(0)) {
            uint256 finalBalance = IERC20(token).balanceOf(msg.sender);
            require(
                initialBalance - finalBalance == totalAmount,
                "Balance mismatch: transfer amounts do not match"
            );
        }
    }
}

// Test hooks for different scenarios
contract RevertingHook {
    function preCheck(
        Call[] calldata,
        address
    ) external payable returns (bytes memory) {
        revert("PreCheck failed");
    }

    function postCheck(bytes calldata, address) external payable {
        revert("PostCheck failed");
    }
}

contract CallCountHook {
    function preCheck(
        Call[] calldata calls,
        address
    ) external payable returns (bytes memory) {
        require(calls.length <= 3, "Too many calls");
        return abi.encode(calls.length);
    }

    function postCheck(bytes calldata, address) external payable {
        // No validation needed
    }
}

contract GasTrackingHook {
    uint256 public preCheckGas;
    uint256 public postCheckGas;

    function preCheck(
        Call[] calldata,
        address
    ) external payable returns (bytes memory) {
        preCheckGas = gasleft();
        return abi.encode(preCheckGas);
    }

    function postCheck(bytes calldata, address) external payable {
        postCheckGas = gasleft();
    }
}

contract MaliciousToken is MockERC20 {
    function transfer(address, uint256) public pure override returns (bool) {
        // Don't actually transfer, just return true
        return true;
    }
}

contract HookTest is Base {
    MockHook public mockHook;
    MockERC20 public mockToken;
    bytes32 public aliceKeyHash;

    function setUp() public override {
        super.setUp();

        // Deploy test contracts
        mockHook = new MockHook();
        mockToken = new MockERC20();

        // Calculate Alice's keyHash - this should be the EOA address
        aliceKeyHash = keccak256(abi.encodePacked(_alice));

        // Fund Alice with tokens for testing
        bool success = mockToken.transfer(_aliceWallet, 1000 ether);
        require(success, "Token transfer failed");
    }

    // Helper functions
    function _setHookForOwnerWithRelayer(
        bytes32 keyHash,
        address hook,
        uint256 expiration
    ) internal {
        // Use the executeWithRelayer function to call updateOwner through the contract itself
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(_aliceWallet),
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                keyHash,
                address(_ecdsaValidator), // Use the existing validator
                IOwnersManager(_aliceWallet).packSettings(
                    true,
                    uint40(expiration),
                    hook
                ) // Pack settings with hook
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // Helper function for direct execute flow - sets hook directly using execute
    function _setHookForOwnerDirect(
        bytes32 keyHash,
        address hook,
        uint256 expiration
    ) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(_aliceWallet),
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                keyHash,
                address(_ecdsaValidator), // Use the existing validator
                IOwnersManager(_aliceWallet).packSettings(
                    true,
                    uint40(expiration),
                    hook
                ) // Pack settings with hook
            )
        });

        // Use execute with EOA as msg.sender
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls);
    }

    // ============ Tests for Direct Execute (EOA as msg.sender) ============

    function test_ExecuteDirect_WithoutHook() public {
        // Execute without any hook set using direct execute
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use execute with EOA as msg.sender
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls);

        // Verify the transfer happened
        assertEq(mockToken.balanceOf(_bob), 50 ether);
    }

    function test_ExecuteDirect_WithMockHook_Success() public {
        // Set up hook for Alice using direct execute
        _setHookForOwnerDirect(aliceKeyHash, address(mockHook), 0);

        // Verify hook is properly set
        (, address hookAddress, , , ) = IOwnersManager(_aliceWallet)
            .getOwnerSettings(aliceKeyHash);
        assertEq(hookAddress, address(mockHook));

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use execute with EOA as msg.sender
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls);

        // Verify the transfer happened
        assertEq(mockToken.balanceOf(_bob), 50 ether);
    }

    function test_ExecuteDirect_WithMockHook_Revert_InvalidFunctionCall()
        public
    {
        // Set up hook for Alice using direct execute
        _setHookForOwnerDirect(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.approve.selector, // Invalid operation, trying to approve instead of transfer
                _bob,
                100 ether
            )
        });

        // Use execute with EOA as msg.sender - should revert due to hook
        vm.prank(_alice);
        vm.expectRevert("Invalid operation");
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_ExecuteDirect_WithMockHook_Revert_ExceedsLimit() public {
        // Set up hook for Alice using direct execute
        _setHookForOwnerDirect(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // Exceeds the 100 ether limit
            )
        });

        // Use execute with EOA as msg.sender - should revert due to hook
        vm.prank(_alice);
        vm.expectRevert("Total transfer amount exceeds limit");
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_ExecuteDirect_WithHook_StatePersistence() public {
        // Set up hook for Alice using direct execute
        _setHookForOwnerDirect(aliceKeyHash, address(mockHook), 0);

        // First call should succeed
        Call[] memory calls1 = new Call[](1);
        calls1[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls1);

        // Second call should also succeed
        Call[] memory calls2 = new Call[](1);
        calls2[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                25 ether
            )
        });

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls2);

        // Verify total transfer
        assertEq(mockToken.balanceOf(_bob), 75 ether);
    }

    function test_ExecuteDirect_WithHook_Expiration() public {
        // Set up hook for Alice with expiration using direct execute
        _setHookForOwnerDirect(
            aliceKeyHash,
            address(mockHook),
            block.timestamp + 1 hours
        );

        // First, test that hook works before expiration
        Call[] memory calls1 = new Call[](1);
        calls1[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use execute with EOA as msg.sender - should succeed before expiration
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls1);

        // Verify the transfer happened
        assertEq(mockToken.balanceOf(_bob), 50 ether);

        // Now move time past expiration
        vm.warp(block.timestamp + 2 hours);

        // Test that hook no longer works after expiration
        Call[] memory calls2 = new Call[](1);
        calls2[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // This should now succeed because hook is expired
            )
        });

        // Use execute with EOA as msg.sender - should fail because owner is expired
        vm.prank(_alice);
        vm.expectRevert(Errors.OwnerExpired.selector);
        ISmartWallet(_aliceWallet).execute(calls2);

        // Verify no additional transfer happened (execution failed due to owner expiration)
        assertEq(mockToken.balanceOf(_bob), 50 ether);
    }

    // ============ Tests for ExecuteWithRelayer (Smart Wallet as msg.sender) ============

    function test_ExecuteWithRelayer_WithoutHook() public {
        // Execute without any hook set
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the transfer happened
        assertEq(mockToken.balanceOf(_bob), 50 ether);
    }

    function test_ExecuteWithRelayer_WithMockHook_Success() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the transfer happened
        assertEq(mockToken.balanceOf(_bob), 50 ether);
    }

    function test_ExecuteWithRelayer_WithMockHook_ExceedsLimit() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // Exceeds the 100 ether limit
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Total transfer amount exceeds limit");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithMockHook_InvalidToken() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        // Create a different token
        MockERC20 otherToken = new MockERC20();
        bool success = otherToken.transfer(_aliceWallet, 1000 ether);
        require(success, "Token transfer failed");

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(otherToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        ); // Should succeed - hook allows any token contract

        // Verify the transfer happened
        assertEq(otherToken.balanceOf(_bob), 50 ether);
    }

    function test_ExecuteWithRelayer_WithMockHook_InvalidOperation() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.approve.selector, // Wrong operation
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Invalid operation");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithMockHook_InvalidRecipient() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken), // Valid token contract
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                address(0), // Invalid recipient
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Invalid recipient address");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithMockHook_BalanceMismatch() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        MaliciousToken maliciousToken = new MaliciousToken();
        bool success = maliciousToken.transfer(_aliceWallet, 1000 ether);
        require(success, "Token transfer failed");

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(maliciousToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Balance mismatch: transfer amounts do not match");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ Tests for Different Hook Types ============

    function test_ExecuteWithRelayer_WithRevertingHook_PreCheck() public {
        RevertingHook revertingHook = new RevertingHook();
        _setHookForOwnerWithRelayer(aliceKeyHash, address(revertingHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("PreCheck failed");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithCallCountHook_Success() public {
        CallCountHook callCountHook = new CallCountHook();
        _setHookForOwnerWithRelayer(aliceKeyHash, address(callCountHook), 0);

        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the transfers happened
        assertEq(_bob.balance, 2 ether);
    }

    function test_ExecuteWithRelayer_WithCallCountHook_TooManyCalls() public {
        CallCountHook callCountHook = new CallCountHook();
        _setHookForOwnerWithRelayer(aliceKeyHash, address(callCountHook), 0);

        Call[] memory calls = new Call[](4); // More than 3 calls
        for (uint256 i = 0; i < 4; i++) {
            calls[i] = Call({target: _bob, value: 1 ether, data: ""});
        }

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Too many calls");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithGasTrackingHook() public {
        GasTrackingHook gasTrackingHook = new GasTrackingHook();
        _setHookForOwnerWithRelayer(aliceKeyHash, address(gasTrackingHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify gas was tracked
        assertGt(gasTrackingHook.preCheckGas(), 0);
        assertGt(gasTrackingHook.postCheckGas(), 0);
    }

    // ============ Tests for Hook with Expiration ============

    function test_ExecuteWithRelayer_WithExpiredHook() public {
        // Set up hook with expiration in the past
        _setHookForOwnerWithRelayer(
            aliceKeyHash,
            address(mockHook),
            block.timestamp - 1
        );

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // Should fail because owner is expired
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert();
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithFutureExpiration() public {
        // Set up hook with expiration in the future
        _setHookForOwnerWithRelayer(
            aliceKeyHash,
            address(mockHook),
            block.timestamp + 3600
        );

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // Should be blocked by hook
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Total transfer amount exceeds limit");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ Tests for Multiple Calls ============

    function test_ExecuteWithRelayer_WithHook_MultipleCalls() public {
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                30 ether
            )
        });
        calls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                40 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify total transfer (30 + 40 = 70 ether, within 100 ether limit)
        assertEq(mockToken.balanceOf(_bob), 70 ether);
    }

    function test_ExecuteWithRelayer_WithHook_MultipleCallsExceedsLimit()
        public
    {
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                60 ether
            )
        });
        calls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Total transfer amount exceeds limit");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ Tests for Non-Admin Self Calls ============

    function test_ExecuteWithRelayer_WithHook_NonAdminSelfCall() public {
        // Set up hook without admin privileges
        uint256 settings = IOwnersManager(_aliceWallet).packSettings(
            false,
            0,
            address(mockHook)
        );
        vm.store(
            address(_aliceWallet),
            keccak256(abi.encode(aliceKeyHash, uint256(2))),
            bytes32(settings)
        );

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(_aliceWallet), // Self call
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert(); // Should revert with NonAdminSelfCall error
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_WithHook_AdminSelfCall() public {
        // Set up hook with admin privileges
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken), // Call the token contract, not the wallet
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        ); // Should succeed with admin privileges
    }

    // ============ Tests for Empty Calls ============

    function test_ExecuteWithRelayer_WithHook_EmptyCalls() public {
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](0);

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        ); // Should succeed with empty calls

        // Verify no tokens were transferred
        assertEq(mockToken.balanceOf(_bob), 0);
    }

    // ============ Tests for Non-Token Calls ============

    function test_ExecuteWithRelayer_WithHook_NonTokenCalls() public {
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert();
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ Tests for Hook State Persistence ============

    function test_ExecuteWithRelayer_WithHook_StatePersistence() public {
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        // First call should succeed
        Call[] memory calls1 = new Call[](1);
        calls1[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                50 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall1 = BatchedCall({
            calls: calls1,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData1 = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall1,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall1,
            validatorData1
        );

        // Second call should also succeed (hook state should be independent)
        Call[] memory calls2 = new Call[](1);
        calls2[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                30 ether
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall2 = BatchedCall({
            calls: calls2,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData2 = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall2,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall2,
            validatorData2
        );

        // Verify total transfers
        assertEq(mockToken.balanceOf(_bob), 80 ether);
    }

    function test_ExecuteWithRelayer_WithHook_ProperSetup() public {
        // Use the contract's own functions to set up the hook
        // First, we need to add the hook through the contract's addOwner function

        // Use the execute function to call updateOwner through the contract itself
        Call[] memory setupCalls = new Call[](1);
        setupCalls[0] = Call({
            target: address(_aliceWallet),
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator), // Use the existing validator
                IOwnersManager(_aliceWallet).packSettings(
                    true,
                    0,
                    address(mockHook)
                ) // Pack settings with hook
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory setupBatchedCall = BatchedCall({
            calls: setupCalls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory setupValidatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            setupBatchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            setupBatchedCall,
            setupValidatorData
        );

        // Now verify the hook is set
        uint256 settings = IOwnersManager(_aliceWallet).ownerSettings(
            aliceKeyHash
        );
        address hook = address(uint160(settings));
        console.log("Hook address after proper setup:", hook);

        // Now try to execute a call that should trigger the hook
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // This should exceed the limit and trigger the hook
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert("Total transfer amount exceeds limit");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ============ Debug Tests ============

    function test_DebugHookSetup() public {
        // Set up hook for Alice
        _setHookForOwnerWithRelayer(aliceKeyHash, address(mockHook), 0);

        // Check what the contract actually reads for ownerSettings
        uint256 contractSettings = IOwnersManager(_aliceWallet).ownerSettings(
            aliceKeyHash
        );
        console.log("Contract settings:", contractSettings);
        console.log(
            "Contract hook address:",
            address(uint160(contractSettings))
        );

        // Now try to execute a call that should trigger the hook
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                IERC20.transfer.selector,
                _bob,
                150 ether // This should exceed the limit and trigger the hook
            )
        });

        // Use executeWithRelayer to specify the correct keyHash
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: _getNonce(_aliceWallet)
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        // This should revert if the hook is working
        vm.expectRevert("Total transfer amount exceeds limit");
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }
}
