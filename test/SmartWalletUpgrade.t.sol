// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {BaseAuthorization} from "src/BaseAuthorization.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Call, BatchedCall} from "src/Types.sol";

// SmartWalletEntryV2 - Upgraded version for testing
// Cannot inherit from SmartWalletEntry directly due to custom storage layout
// Instead, inherit from SmartWallet and define the same storage layout
contract SmartWalletEntryV2 is SmartWallet layout at 0xd2f25270280c292d8930a730093bb680163a837f93acc639d858c440b5c53800 {
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
    SmartWalletEntryV2 public smartWalletV2Implementation;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy V2 implementation
        smartWalletV2Implementation = new SmartWalletEntryV2();
    }
    
    function test_UpgradeToAndCall_ThroughExecuteWithRelayer_Success() public {
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
            nonce: 0
        });
        
        // 3. Generate signature (using ECDSA to simulate Passkey)
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, batchedCall
        , uint48(0));
        
        // 4. Execute upgrade through relayer
        vm.prank(_alice); // Anyone can be relayer, using alice for simplicity
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // 5. Verify upgrade was successful
        SmartWalletEntryV2 upgradedWallet = SmartWalletEntryV2(payable(_aliceWallet));
        assertEq(upgradedWallet.getVersion(), "v2");
        assertTrue(upgradedWallet.isUpgraded());
    }
    
    function test_UpgradeToAndCall_PreservesOwnersThroughRelayer_Success() public {
        // Add an additional owner before upgrade
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(true, 0, address(0));
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
            nonce: 0
        });
        
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, batchedCall
        , uint48(0));
        
        // Execute upgrade
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Verify owners are preserved after upgrade
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(keccak256(abi.encodePacked(_alice))));
        assertTrue(IOwnerManager(_aliceWallet).hasOwner(bobKeyHash));
    }
    
    function test_UpgradeToAndCall_PreservesNonceStateThroughRelayer_Success() public {
        // The default nonce key is 0 (not derived from keyHash)
        uint192 nonceKey = 0;
        
        // Execute a few transactions to increment nonce
        for (uint i = 0; i < 3; i++) {
            Call[] memory calls = constructCallsData();
            BatchedCall memory txCall = BatchedCall({
                calls: calls,
                nonce: i  // Using sequential nonce with key 0
            });
            
            bytes memory txValidatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, txCall
            , uint48(0));
            
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
            nonce: 3
        });
        
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, batchedCall
        , uint48(0));
        
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Verify nonce is preserved and incremented correctly
        uint64 nonceAfter = INonceManager(_aliceWallet).getNonce(nonceKey);
        assertEq(nonceAfter, 4);
    }
    
    function test_UpgradeToAndCall_WithInitializationThroughRelayer_Success() public {
        // Deploy V2 with initialization function
        bytes memory initData = abi.encodeWithSelector(
            SmartWalletEntryV2.getVersion.selector
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
            nonce: 0
        });
        
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, batchedCall
        , uint48(0));
        
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        
        // Verify upgrade with initialization succeeded
        SmartWalletEntryV2 upgradedWallet = SmartWalletEntryV2(payable(_aliceWallet));
        assertEq(upgradedWallet.getVersion(), "v2");
    }
    
    function test_RevertWhen_NonAdminOwner_UpgradeThroughRelayer() public {
        // Add bob as a non-admin owner
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(false, 0, address(0));
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
            nonce: bobNonce
        });
        
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _bob, _bobPk, batchedCall
        , uint48(0));
        
        // Should fail because non-admin cannot make self-calls
        vm.prank(makeAddr("relayer"));
        vm.expectRevert(abi.encodeWithSelector(ISmartWallet.NonAdminSelfCall.selector));
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
    }
    
    function test_RevertWhen_Upgrade_WithInvalidSignature() public {
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
            nonce: 0
        });
        
        // Use wrong key to sign (bob's key but claim it's alice's)
        // This creates a signature with alice's keyHash but signed with bob's key
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 hash = _getExecuteWithRelayerHash(batchedCall, uint48(0), _aliceWallet);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hash);
        bytes memory invalidValidatorData = abi.encodePacked(aliceKeyHash, uint48(0), r, s, v);
        
        // Should revert with InvalidSignature
        vm.prank(_alice);
        vm.expectRevert(abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector));
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, invalidValidatorData);
    }
    
    function test_RevertWhen_DirectUpgradeCall_Fails_NotFromSelf() public {
        // Direct call from non-owner should fail with NotFromSelf
        vm.prank(_bob);
        vm.expectRevert(abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector));
        UUPSUpgradeable(_aliceWallet).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
        
        // Direct call from EOA owner also fails with NotFromSelf
        vm.prank(_alice);
        vm.expectRevert(abi.encodeWithSelector(BaseAuthorization.NotFromSelf.selector));
        UUPSUpgradeable(_aliceWallet).upgradeToAndCall(
            address(smartWalletV2Implementation),
            ""
        );
    }
}