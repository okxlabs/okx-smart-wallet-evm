// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Call, BatchedCall} from "src/Types.sol";
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
    
    function test_upgrade_through_executeWithRelayer() public {
        // Simulate Passkey-only wallet upgrade through executeWithRelayer
        // Using ECDSA signature to simulate Passkey scenario (Foundry limitation)
        
        // 1. Create upgrade call - wallet calls its own upgradeToAndCall
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,  // Target is the wallet itself
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
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _aliceWallet,
            _alice,
            _alicePk,
            hash
        );
        
        // 4. Execute upgrade through relayer
        vm.prank(_alice); // Anyone can be relayer, using alice for simplicity
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // 5. Verify upgrade was successful
        OKXSmartWalletEntryV2 upgradedWallet = OKXSmartWalletEntryV2(payable(_aliceWallet));
        assertEq(upgradedWallet.getVersion(), "v2");
        assertTrue(upgradedWallet.isUpgraded());
    }
    
    function test_upgrade_preserves_owners_through_relayer() public {
        // Add an additional owner before upgrade
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnersManager(_aliceWallet).packSettings(true, 0, address(0));
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), settings);
        
        // Create upgrade call
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                ""
            )
        });
        
        BatchedCall memory batchedCall = BatchedCall({
            calls: upgradeCalls,
            nonce: 0,
            expiry: 0
        });
        
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _aliceWallet,
            _alice,
            _alicePk,
            hash
        );
        
        // Execute upgrade
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Verify owners are preserved after upgrade
        assertTrue(IOwnersManager(_aliceWallet).hasOwner(keccak256(abi.encodePacked(_alice))));
        assertTrue(IOwnersManager(_aliceWallet).hasOwner(bobKeyHash));
    }
    
    function test_upgrade_preserves_nonce_state_through_relayer() public {
        // The default nonce key is 0 (not derived from keyHash)
        uint192 nonceKey = 0;
        
        // Execute a few transactions to increment nonce
        for (uint i = 0; i < 3; i++) {
            Call[] memory calls = constructCallsData();
            BatchedCall memory txCall = BatchedCall({
                calls: calls,
                nonce: i,  // Using sequential nonce with key 0
                expiry: 0
            });
            
            bytes32 txHash = ERC712(_aliceWallet).hashTypedData(
                BatchedCallLib.hash(txCall, address(_smartWallet))
            );
            bytes memory txValidatorData = constructValidatorData(
                _aliceWallet,
                _alice,
                _alicePk,
                txHash
            );
            
            vm.prank(_alice);
            ISmartWallet(_aliceWallet).executeWithRelayer(txCall, txValidatorData);
        }
        
        // Verify nonce was incremented
        uint64 nonceBefore = INonceManager(_aliceWallet).getNonce(nonceKey);
        assertEq(nonceBefore, 3);
        
        // Perform upgrade
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                ""
            )
        });
        
        BatchedCall memory batchedCall = BatchedCall({
            calls: upgradeCalls,
            nonce: 3,
            expiry: 0
        });
        
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _aliceWallet,
            _alice,
            _alicePk,
            hash
        );
        
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Verify nonce is preserved and incremented correctly
        uint64 nonceAfter = INonceManager(_aliceWallet).getNonce(nonceKey);
        assertEq(nonceAfter, 4);
    }
    
    function test_upgrade_with_initialization_through_relayer() public {
        // Deploy V2 with initialization function
        bytes memory initData = abi.encodeWithSelector(
            OKXSmartWalletEntryV2.getVersion.selector
        );
        
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                initData
            )
        });
        
        BatchedCall memory batchedCall = BatchedCall({
            calls: upgradeCalls,
            nonce: 0,
            expiry: 0
        });
        
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _aliceWallet,
            _alice,
            _alicePk,
            hash
        );
        
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Verify upgrade with initialization succeeded
        OKXSmartWalletEntryV2 upgradedWallet = OKXSmartWalletEntryV2(payable(_aliceWallet));
        assertEq(upgradedWallet.getVersion(), "v2");
    }
    
    function test_non_admin_owner_cannot_upgrade_through_relayer() public {
        // Add bob as a non-admin owner
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnersManager(_aliceWallet).packSettings(false, 0, address(0));
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), settings);
        
        // Bob (non-admin) tries to upgrade through executeWithRelayer
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                ""
            )
        });
        
        // Use bob's nonce key
        uint192 bobNonceKey = uint192(uint256(bobKeyHash) >> 64);
        uint256 bobNonce = (uint256(bobNonceKey) << 64) | 0;
        
        BatchedCall memory batchedCall = BatchedCall({
            calls: upgradeCalls,
            nonce: bobNonce,
            expiry: 0
        });
        
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        
        // Sign with bob's key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hash);
        bytes memory validatorData = abi.encodePacked(bobKeyHash, r, s, v);
        
        // Should fail because non-admin cannot make self-calls
        vm.prank(makeAddr("relayer"));
        vm.expectRevert(abi.encodeWithSelector(Errors.NonAdminSelfCall.selector));
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
    }
    
    function test_upgrade_fails_with_invalid_signature() public {
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(smartWalletV2Implementation),
                ""
            )
        });
        
        BatchedCall memory batchedCall = BatchedCall({
            calls: upgradeCalls,
            nonce: 0,
            expiry: 0
        });
        
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        
        // Use wrong key to sign (bob's key for alice's wallet)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hash);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes memory invalidValidatorData = abi.encodePacked(aliceKeyHash, r, s, v);
        
        // Should revert with InvalidSignature
        vm.prank(_alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSignature.selector));
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, invalidValidatorData);
    }
    
    function test_direct_upgrade_call_fails() public {
        // Direct call from non-owner should fail with NotFromSelf
        vm.prank(_bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        UUPSUpgradeable(_aliceWallet).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Direct call from EOA owner also fails with NotFromSelf
        vm.prank(_alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFromSelf.selector));
        UUPSUpgradeable(_aliceWallet).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
    }
}