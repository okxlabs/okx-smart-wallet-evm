// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

contract ValidationTest is Base {
    event NonceConsumed(uint192 key, uint64 nonce);

    function setUp() public override {
        super.setUp();
    }

    function test_RevertWhen_ExecuteFromRelayer_InvalidSignature() public {
        Call[] memory calls = constructCallsData();

        bytes32 hash = _getValidationTypedHash(_aliceWallet, calls);
        // Use alice's keyHash but bob's signature to create invalid signature
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // 0 means no expiry
        // Add validUntil to hash before signing (matching SmartWallet.sol line 141 & 213)
        bytes32 hashWithValidUntil = keccak256(abi.encode(hash, validUntil));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hashWithValidUntil);
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            r,
            s,
            v
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_RevertWhen_ExecuteFromRelayer_InvalidKeyHash() public {
        Call[] memory calls = constructCallsData();

        // Use a keyHash that doesn't exist (bob's keyHash, but bob is not a validator)
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _bob, // Use bob's address for keyHash
            _bobPk, // Use bob's private key for signing
            batchedCall,
            uint48(0)
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidKeyHash.selector,
                bobKeyHash
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_RevertWhen_ExecuteFromRelayer_RemovedValidator() public {
        Call[] memory calls = constructCallsData();

        // Use _bob instead of _aliceWallet to avoid EIP-7702 fallback collision
        // (In test environment, address(this) == _aliceWallet due to setCode)
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            0
        );
        _executeRemoveValidator(_aliceWallet, bobKeyHash);

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _bob, // Using _bob's address
            _bobPk, // Using _bob's private key
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidKeyHash.selector,
                bobKeyHash
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_ExecuteFromRelayer_EmitsNonceConsumed() public {
        vm.prank(_alice);
        uint256 nonce = _getNonce(_aliceWallet);
        Call[] memory calls = constructCallsData();

        vm.expectEmit();
        emit NonceConsumed(uint192(0), uint64(nonce));

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.startPrank(_alice);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(
            _getExecuteWithRelayerHash(
                BatchedCall({calls: calls, nonce: 0}),
                0,
                _aliceWallet
            ),
            _alice,
            0
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0}),
            validatorData
        );
        vm.stopPrank();

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_Nonce_UnchangedAfterInvalidSignatureRevert_Success() public {
        // Get initial nonce
        uint192 nonceKey = uint192(
            uint256(keccak256(abi.encodePacked(_alice))) >> 64
        );
        uint64 initialNonce = INonceManager(_aliceWallet).getNonce(nonceKey);

        // Construct call data
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: (uint256(nonceKey) << 64) | uint256(initialNonce)
        });

        // Create validatorData with invalid signature
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes memory invalidSignature = new bytes(65); // All zeros - invalid signature
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash,
            uint48(0), // validUntil (0 means no expiry)
            invalidSignature
        );

        // Execute transaction that should revert
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify nonce hasn't changed
        uint64 nonceAfterRevert = INonceManager(_aliceWallet).getNonce(
            nonceKey
        );
        assertEq(
            nonceAfterRevert,
            initialNonce,
            "Nonce should not change after reverted transaction"
        );
    }

    function test_IsValidSignature_WithInvalidSigner_ReturnsInvalidValue()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // Wrong signer
        bytes memory signature = abi.encodePacked(_signDigest(hash, _bobPk));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, Static.INVALID_VALUE);
    }

    function test_IsValidSignature_SignatureLengthBoundaries_ReturnsInvalidValue()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // Test empty signature
        bytes memory emptySignature = bytes("");
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            emptySignature
        );
        assertEq(result, Static.INVALID_VALUE);

        // Test oversized signature (100 bytes)
        bytes memory oversizedSignature = bytes(new bytes(100));
        result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            oversizedSignature
        );
        assertEq(result, Static.INVALID_VALUE);
    }

    function test_RevertWhen_Execute_ExpiredOwner() public {
        // Add Bob as owner with 1 day expiration
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 1 days);

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            expiry,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            settings
        );

        // Create a simple call
        Call[] memory calls = constructCallsData();

        // Bob can execute before expiration
        vm.prank(_bob);
        ISmartWallet(_aliceWallet).execute(calls);
        assertEq(address(_bob).balance, 1 ether);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Bob should be rejected after expiration
        vm.prank(_bob);
        vm.expectRevert(ISmartWallet.OwnerExpired.selector);
        ISmartWallet(_aliceWallet).execute(calls);
    }

    function test_Execute_AllowsNonExpiredOwner_Success() public {
        // Add Bob as owner with 7 days expiration
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 7 days);

        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            expiry,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            settings
        );

        // Fast forward but still within expiration
        vm.warp(block.timestamp + 6 days);

        // Create a simple call
        Call[] memory calls = constructCallsData();

        // Bob should still be able to execute
        vm.prank(_bob);
        ISmartWallet(_aliceWallet).execute(calls);
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_RevertWhen_ExecuteWithRelayer_ExpiredBatchedCall() public {
        // Create a BatchedCall with expiry validation
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        uint48 validUntil = uint48(block.timestamp + 1);

        // Sign the BatchedCall with validUntil in the hash
        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            validUntil,
            address(_smartWallet)
        );
        bytes32 hash = ERC712(_aliceWallet).hashTypedData(dataHash);

        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, hash);
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            r,
            s,
            v
        );

        // Fast forward time by 2 seconds to make the BatchedCall expired
        vm.warp(block.timestamp + 2);

        // Should revert with ExpiryPassed error
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.ExpiryPassed.selector,
                validUntil
            )
        );
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_ExecuteWithRelayer_AllowsZeroExpiryBatchedCall_Success()
        public
    {
        // Create a BatchedCall with expiry = 0 (never expires)
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        // Sign the BatchedCall
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Fast forward time by 365 days
        vm.warp(block.timestamp + 365 days);

        // Should still execute successfully since expiry = 0 means never expires
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the transaction was successful
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_SignatureReplayProtection_AcrossIndependentDeployments_Success()
        public
    {
        // Deploy a completely independent SmartWallet and Factory
        // This simulates a third party deploying our open-sourced contracts

        // Deploy a new SmartWallet implementation
        SmartWalletEntry independentImplementation = new SmartWalletEntry();

        // Deploy a new Factory (constructor disables initializers)
        SmartWalletFactory independentFactory = new SmartWalletFactory(
            address(independentImplementation)
        );

        // Create a wallet using the independent factory with same pubKeyHash as alice
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)), // Same pubKeyHash
            address(_ecdsaValidator) // Same validator type
        );

        address independentWallet = independentFactory.createAccount(
            initialOwners,
            0 // Same salt as alice's wallet for maximum similarity
        );

        // Fund the independent wallet
        vm.deal(independentWallet, 10 ether);

        // Create a BatchedCall and sign it for alice's original wallet
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        // Sign for the ORIGINAL alice wallet (from Base.t.sol)
        bytes memory validatorDataForAlice = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Execute on alice's original wallet - should succeed
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorDataForAlice
        );
        assertEq(_bob.balance, 1 ether);

        // Try to replay alice's signature on the independent wallet - should FAIL
        // Even though:
        // 1. Same implementation bytecode
        // 2. Same pubKeyHash installed
        // 3. Same validator type
        // The signature is bound to alice's specific wallet address
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(independentWallet).executeWithRelayer(
            batchedCall,
            validatorDataForAlice
        );

        // Verify bob didn't receive additional funds
        assertEq(_bob.balance, 1 ether);

        // Now create proper signature for the independent wallet
        bytes memory validatorDataForIndependent = _constructRelayerSignature(
            independentWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // This should succeed with proper signature
        vm.prank(relayer);
        ISmartWallet(independentWallet).executeWithRelayer(
            batchedCall,
            validatorDataForIndependent
        );
        assertEq(_bob.balance, 2 ether);
    }

    function test_SignatureReplayProtection_AcrossDifferentWallets_Success()
        public
    {
        // Deploy a second SmartWallet with the same bytecode but different address
        // This simulates a third party deploying our open-sourced contract
        // Deploy second wallet with different salt
        address secondWallet = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)), // Same pubKeyHash as alice's wallet
            address(_ecdsaValidator),
            999 // Different salt to get different address
        );

        // Fund the second wallet
        vm.deal(secondWallet, 10 ether);

        // Create a BatchedCall for the first wallet
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});

        // Sign the BatchedCall for the FIRST wallet (_aliceWallet)
        // Note: The hash includes the wallet address via domain separator
        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Create a relayer address
        address relayer = makeAddr("relayer");

        // Execute on the first wallet - should succeed
        vm.prank(relayer);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
        assertEq(_bob.balance, 1 ether);

        // Try to replay the same signature on the second wallet - should fail
        // Even though both wallets have the same pubKeyHash installed,
        // the signature is bound to the specific wallet address
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartWallet.InvalidSignature.selector)
        );
        ISmartWallet(secondWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify that bob didn't receive additional funds
        assertEq(_bob.balance, 1 ether);

        // Now create a proper signature for the second wallet
        bytes memory validatorDataForSecondWallet = _constructRelayerSignature(
            secondWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // This should succeed because it's properly signed for the second wallet
        vm.prank(relayer);
        ISmartWallet(secondWallet).executeWithRelayer(
            batchedCall,
            validatorDataForSecondWallet
        );
        assertEq(_bob.balance, 2 ether);
    }

    function test_IsValidSignature_ForRemovedValidator_ReturnsInvalidValue()
        public
    {
        // Add validator using _bob to avoid EIP-7702 fallback collision
        // (In test environment, address(this) == _aliceWallet due to setCode)
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            0
        );

        // Remove validator
        _executeRemoveValidator(_aliceWallet, bobKeyHash);

        bytes32 hash = keccak256("test");
        bytes memory sig = _signDigest(hash, _bobPk); // Use _bob's private key
        bytes memory signature = abi.encodePacked(bobKeyHash, uint48(0), sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, Static.INVALID_VALUE);
    }

    function test_IsValidSignature_WithShortSignature_ReturnsInvalidValue()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // signature shorter than 20 bytes
        bytes memory signature = bytes("");

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, Static.INVALID_VALUE);
    }

    function test_IsValidSignature_WithLongerThan85BytesSignature_ReturnsInvalidValue()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // signature have 100 bytes
        bytes memory signature = bytes(new bytes(100));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, Static.INVALID_VALUE);
    }

    function test_IsValidSignature_WithDefaultValidator_ReturnsMagicValue()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry
        bytes memory sig = _signDigestWithValidation(
            hash,
            _alicePk,
            validUntil
        );
        bytes memory signature = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            sig
        );

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, Static.MAGIC_VALUE);
    }

    function test_IsValidSignature_WithValidValidatorSigner_ReturnsMagicValue()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry
        bytes memory sig = _signDigestWithValidation(
            hash,
            _alicePk,
            validUntil
        );
        bytes memory signature = abi.encodePacked(keyHash, validUntil, sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(result, Static.MAGIC_VALUE);
    }

    function test_IsValidSignature_ForPermit_ReturnsMagicValue() public view {
        bytes32 hash = keccak256("721 struct data");
        uint48 validUntil = 0; // No expiry

        // Create bound hash like isValidSignature does with validUntil
        bytes32 digest = _getIsValidSignatureHash(
            hash,
            _aliceWallet,
            validUntil
        );

        // Sign the bound digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, digest);

        // Signature with keyHash and validUntil prefix
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash,
            validUntil,
            r,
            s,
            v
        );

        // Call isValidSignature
        bytes4 result = ISmartWallet(_aliceWallet).isValidSignature(
            hash,
            validatorData
        );
        assertEq(result, Static.MAGIC_VALUE);
    }

    function _signDigest(
        bytes32 hash,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        // Note: Using validUntil = 0 for backwards compatibility
        bytes32 digest = _getIsValidSignatureHash(hash, _aliceWallet, 0);

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        return abi.encodePacked(r, s, v);
    }

    function _signDigestWithValidation(
        bytes32 hash,
        uint256 signerPk,
        uint48 validUntil
    ) internal view returns (bytes memory) {
        bytes32 digest = _getIsValidSignatureHash(
            hash,
            _aliceWallet,
            validUntil
        );

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        return abi.encodePacked(r, s, v);
    }

    function _getValidationTypedHashSansChainId(
        address account,
        BatchedCall memory batchedCall
    ) internal view returns (bytes32) {
        // _getExecuteWithRelayerHash will automatically use hashTypedDataSansChainId
        // when the nonce has CHAIN_LESS_NONCE_KEY
        return
            _getExecuteWithRelayerHash(
                batchedCall,
                0, // validUntil = 0 (no expiry)
                account
            );
    }

    // Test chain ID validation skip logic in executeWithRelayer context
    function test_ExecuteWithRelayer_AllowsChainlessNonceForAddOwner_Success()
        public
    {
        // Create addOwner call
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 newOwnerSettings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                newOwnerSettings
            )
        });

        // Use chainless nonce key (Static.CHAIN_LESS_NONCE_KEY = 196)
        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64; // nonce key = 196, sequence = 0
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should succeed with chainless nonce for addOwner
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify the owner was added
        assertTrue(
            IOwnerManager(_aliceWallet).hasOwner(newOwnerKeyHash),
            "New owner should be added"
        );
    }

    function test_RevertWhen_ExecuteWithRelayer_DoesNotAllowChainlessNonceForUpdateOwner()
        public
    {
        // First add an owner to update
        bytes32 ownerKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            ownerKeyHash,
            address(_ecdsaValidator),
            settings
        );

        // Create updateOwner call
        uint256 newSettings = IOwnerManager(_aliceWallet).packSettings(
            true, // Make admin
            uint40(block.timestamp + 1 days), // Set expiry
            address(0) // No hook
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                ownerKeyHash,
                address(_ecdsaValidator),
                newSettings
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should not succeed with chainless nonce for updateOwner
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithRelayer_DoesNotAllowChainlessNonceForRemoveOwner()
        public
    {
        // First add an owner to remove
        bytes32 ownerKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            ownerKeyHash,
            address(_ecdsaValidator),
            settings
        );

        // Create removeOwner call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                ownerKeyHash
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should NOT succeed with chainless nonce for removeOwner
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithRelayer_RejectsChainlessNonceForUnsupportedSelector()
        public
    {
        // Create a regular execute call (not supported for chainless nonce)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert with InvalidNonceKey for unsupported selector
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    function test_RevertWhen_ExecuteWithRelayer_DoesNotAllowMixedCallsWithSupportedSelectors()
        public
    {
        // Create multiple calls mixing supported and unsupported selectors
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](2);

        // addOwner call (supported for chainless)
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        // updateOwner call (NOT supported for chainless)
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint256 adminSettings = IOwnerManager(_aliceWallet).packSettings(
            true, // Make admin
            0, // No expiry
            address(0) // No hook
        );
        calls[1] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator),
                adminSettings
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should fail because it mixes supported and unsupported selectors
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // Test upgradeToAndCall selector support
    function test_ExecuteWithRelayer_AllowsChainlessNonceForUpgradeToAndCall_Success()
        public
    {
        // Create a mock upgrade call (we don't need a real implementation for this test)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                UUPSUpgradeable.upgradeToAndCall.selector,
                address(0x1234), // Mock new implementation
                "" // No initialization data
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should succeed with chainless nonce for upgradeToAndCall
        // Note: This will likely revert during execution due to invalid implementation,
        // but it should pass the canSkipChainIdValidation check first
        vm.prank(_alice);
        try
            ISmartWallet(_aliceWallet).executeWithRelayer(
                batchedCall,
                validatorData
            )
        {
            // If it succeeds, that's fine too
        } catch (bytes memory reason) {
            // We expect it might fail during actual upgrade execution
            // but not due to InvalidNonceKey (which would happen before execution)
            bytes4 errorSelector = bytes4(reason);
            assertTrue(
                errorSelector != ISmartWallet.InvalidNonceKey.selector,
                "Should not fail with InvalidNonceKey for upgradeToAndCall selector"
            );
        }
    }

    // Test that chainless nonce is rejected when mixed with unsupported operations
    function test_RevertWhen_ExecuteWithRelayer_ComprehensiveChainlessNonceCoverage()
        public
    {
        // Test that mixing supported and unsupported selectors fails
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        // First add an owner that we can later remove
        uint256 settings = OwnerManager(_aliceWallet).packSettings(
            false,
            0,
            address(0)
        );
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            newOwnerKeyHash,
            address(_ecdsaValidator),
            settings
        );

        Call[] memory calls = new Call[](3);

        // 1. addOwner call (supported for chainless)
        bytes32 newOwnerKeyHash2 = keccak256(abi.encodePacked(address(0x123)));
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newOwnerKeyHash2,
                address(_ecdsaValidator),
                0 // Default settings
            )
        });

        // 2. updateOwner call (NOT supported for chainless)
        uint256 adminSettings = IOwnerManager(_aliceWallet).packSettings(
            true,
            0,
            address(0)
        );
        calls[1] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator),
                adminSettings
            )
        });

        // 3. removeOwner call (NOT supported for chainless)
        calls[2] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                newOwnerKeyHash
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        bytes memory validatorData = _constructRelayerSignature(
            _aliceWallet,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should fail because updateOwner and removeOwner are not supported for chainless nonce
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_aliceWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }
}
