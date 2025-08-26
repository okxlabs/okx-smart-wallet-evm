// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {OKXSmartWalletEntry} from "src/OKXSmartWalletEntry.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";

// OKXSmartWalletEntryV2 - Upgraded version for testing
// Cannot inherit from OKXSmartWalletEntry directly due to custom storage layout
// Instead, inherit from SmartWallet and define the same storage layout
contract OKXSmartWalletEntryV2 is SmartWallet layout at 0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00 {
    // New state variable (append only to maintain storage layout)
    string public constant VERSION = "v2";
    
    // New function in V2
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }
    
    // New function to test upgraded functionality
    function isUpgraded() external pure returns (bool) {
        return true;
    }
}

contract SmartWalletUpgradeTest is Base {
    OKXSmartWalletEntryV2 public smartWalletV2Implementation;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy V2 implementation
        smartWalletV2Implementation = new OKXSmartWalletEntryV2();
    }
    
    function test_upgrade_only_owner_can_upgrade() public {
        // Non-owner tries to upgrade - should fail
        vm.prank(_bob);
        vm.expectRevert();
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Owner can upgrade successfully
        vm.prank(_aliceEOA);
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Verify upgrade succeeded by calling V2 function
        assertEq(OKXSmartWalletEntryV2(_alice).getVersion(), "v2");
        assertTrue(OKXSmartWalletEntryV2(_alice).isUpgraded());
    }
    
    function test_upgrade_preserves_owners() public {
        // Get initial owners
        bytes32[] memory initialOwners = IOwnersManager(_alice).getOwnerKeys();
        uint256 initialOwnerCount = IOwnersManager(_alice).ownerCount();
        
        // Verify alice owner exists before upgrade
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        assertTrue(IOwnersManager(_alice).hasOwner(aliceKeyHash));
        
        // Perform upgrade
        vm.prank(_aliceEOA);
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Verify owners are preserved after upgrade
        bytes32[] memory afterOwners = IOwnersManager(_alice).getOwnerKeys();
        uint256 afterOwnerCount = IOwnersManager(_alice).ownerCount();
        
        assertEq(afterOwnerCount, initialOwnerCount, "Owner count should be preserved");
        assertEq(afterOwners.length, initialOwners.length, "Owner keys length should be preserved");
        
        // Verify alice is still an owner
        assertTrue(IOwnersManager(_alice).hasOwner(aliceKeyHash), "Alice should still be an owner");
        
        // Verify owner can still execute transactions
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _bob,
            value: 0.1 ether,
            data: ""
        });
        
        vm.prank(_aliceEOA);
        ISmartWallet(_alice).execute(calls);
        
        assertEq(_bob.balance, 0.1 ether, "Owner should still be able to execute transactions");
    }
    
    function test_upgrade_preserves_validator_settings() public {
        // Add another owner with specific settings before upgrade
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = IOwnersManager(_alice).packSettings(
            true, // isAdmin
            uint40(block.timestamp + 1 days), // expiration
            address(0) // no hook
        );
        
        // Add bob as owner from alice wallet
        vm.prank(_alice);
        IOwnersManager(_alice).addOwner(
            bobKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            settings
        );
        
        // Get settings before upgrade
        (
            address validatorBefore,
            address hookBefore,
            uint40 expirationBefore,
            bool isAdminBefore,
            bool isExpiredBefore
        ) = IOwnersManager(_alice).getOwnerSettings(bobKeyHash);
        
        // Perform upgrade
        vm.prank(_aliceEOA);
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Get settings after upgrade
        (
            address validatorAfter,
            address hookAfter,
            uint40 expirationAfter,
            bool isAdminAfter,
            bool isExpiredAfter
        ) = IOwnersManager(_alice).getOwnerSettings(bobKeyHash);
        
        // Verify all settings are preserved
        assertEq(validatorAfter, validatorBefore, "Validator should be preserved");
        assertEq(hookAfter, hookBefore, "Hook should be preserved");
        assertEq(expirationAfter, expirationBefore, "Expiration should be preserved");
        assertEq(isAdminAfter, isAdminBefore, "Admin status should be preserved");
        assertEq(isExpiredAfter, isExpiredBefore, "Expired status should be preserved");
    }
    
    function test_upgrade_preserves_nonce_state() public {
        // Prepare a BatchedCall with relayer to increment nonce
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _bob,
            value: 0.05 ether,
            data: ""
        });
        
        // Create BatchedCall with nonce
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0, // First nonce
            expiry: 0  // No expiry
        });
        
        // Create signature for the batchedCall
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, hash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);
        
        // Execute with relayer to increment nonce
        vm.prank(address(0xCAFE)); // Any address can be relayer
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
        
        // Get nonce after first execution
        uint256 nonceBefore = INonceManager(_alice).getNonce(0);
        assertEq(nonceBefore, 1, "Nonce should be 1 after first execution");
        
        // Perform upgrade
        vm.prank(_aliceEOA);
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Get nonce after upgrade
        uint256 nonceAfter = INonceManager(_alice).getNonce(0);
        assertEq(nonceAfter, nonceBefore, "Nonce should be preserved after upgrade");
        
        // Execute another transaction with relayer to verify nonce still works
        BatchedCall memory secondBatchedCall = BatchedCall({
            calls: calls,
            nonce: 1, // Next nonce
            expiry: 0
        });
        
        // Create new signature for second call - use V2 implementation address
        bytes32 hash2 = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(secondBatchedCall, address(smartWalletV2Implementation))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_alicePk, hash2);
        bytes memory validatorData2 = abi.encodePacked(aliceKeyHash, r2, s2, v2);
        
        vm.prank(address(0xCAFE));
        ISmartWallet(_alice).executeWithRelayer(secondBatchedCall, validatorData2);
        
        uint256 nonceAfterExecution = INonceManager(_alice).getNonce(0);
        assertEq(nonceAfterExecution, 2, "Nonce should be 2 after second execution");
    }
    
    function test_upgrade_from_wallet_itself() public {
        // Prepare upgrade call from wallet to itself
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                ""
            )
        });
        
        // Execute upgrade through wallet's execute function
        vm.prank(_aliceEOA);
        ISmartWallet(_alice).execute(calls);
        
        // Verify upgrade succeeded
        assertEq(OKXSmartWalletEntryV2(_alice).getVersion(), "v2");
        assertTrue(OKXSmartWalletEntryV2(_alice).isUpgraded());
    }
    
    function test_upgrade_with_initialization_call() public {
        // Create initialization data for a hypothetical init function
        bytes memory initData = abi.encodeWithSelector(
            OKXSmartWalletEntryV2.getVersion.selector
        );
        
        // Upgrade with initialization call
        vm.prank(_aliceEOA);
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            initData
        );
        
        // Verify upgrade succeeded
        assertEq(OKXSmartWalletEntryV2(_alice).getVersion(), "v2");
        assertTrue(OKXSmartWalletEntryV2(_alice).isUpgraded());
    }
    
    function test_cannot_upgrade_to_non_uups_contract() public {
        // Deploy a non-UUPS contract
        address nonUUPS = address(new NonUUPSContract());
        
        // Try to upgrade to non-UUPS contract - should fail
        vm.prank(_aliceEOA);
        vm.expectRevert(UUPSUpgradeable.UpgradeFailed.selector);
        UUPSUpgradeable(_alice).upgradeToAndCall(nonUUPS, "");
    }
    
    function test_multiple_owners_can_upgrade() public {
        // Add bob as another owner
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        vm.prank(_alice);
        IOwnersManager(_alice).addOwner(
            bobKeyHash,
            Static.ECDSA_VALIDATOR_ADDRESS,
            0
        );
        
        // Bob (as owner) can also upgrade
        vm.prank(_bob);
        UUPSUpgradeable(_alice).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Verify upgrade succeeded
        assertEq(OKXSmartWalletEntryV2(_alice).getVersion(), "v2");
    }
    
    function test_upgrade_through_executeWithRelayer() public {
        // This test simulates how a Passkey-only wallet would upgrade
        // Using ECDSA for convenience in Foundry testing
        
        // 1. Create upgrade call - wallet calls its own upgradeToAndCall
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _alice,  // Target is the wallet itself
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                ""
            )
        });
        
        // 2. Wrap in BatchedCall
        BatchedCall memory batchedCall = BatchedCall({
            calls: upgradeCalls,
            nonce: 0,
            expiry: 0
        });
        
        // 3. Generate signature (using ECDSA to simulate Passkey)
        bytes32 hash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, hash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);
        
        // 4. Execute through relayer (simulating Passkey-only wallet upgrade path)
        address relayer = address(0xCAFE);
        vm.prank(relayer);  // Any address can be the relayer
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
        
        // 5. Verify upgrade succeeded
        assertEq(OKXSmartWalletEntryV2(_alice).getVersion(), "v2");
        assertTrue(OKXSmartWalletEntryV2(_alice).isUpgraded());
        
        // 6. Verify wallet still works after upgrade with executeWithRelayer
        Call[] memory postUpgradeCalls = new Call[](1);
        postUpgradeCalls[0] = Call({
            target: _bob,
            value: 0.01 ether,
            data: ""
        });
        
        BatchedCall memory postUpgradeBatch = BatchedCall({
            calls: postUpgradeCalls,
            nonce: 1,  // Next nonce
            expiry: 0
        });
        
        // Generate signature with V2 implementation address
        bytes32 postHash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(postUpgradeBatch, address(smartWalletV2Implementation))
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_alicePk, postHash);
        bytes memory postValidatorData = abi.encodePacked(aliceKeyHash, r2, s2, v2);
        
        uint256 bobBalanceBefore = _bob.balance;
        vm.prank(relayer);
        ISmartWallet(_alice).executeWithRelayer(postUpgradeBatch, postValidatorData);
        
        // Verify transaction succeeded
        assertEq(_bob.balance - bobBalanceBefore, 0.01 ether, "Post-upgrade transaction should succeed");
    }
}

// Helper contract for testing non-UUPS upgrade attempts
contract NonUUPSContract {
    function someFunction() external pure returns (uint256) {
        return 42;
    }
}