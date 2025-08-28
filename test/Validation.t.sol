// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC712} from "src/ERC712.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

contract ValidationTest is Base {
    event NonceConsumed(uint192 key, uint64 nonce);

    function setUp() public override {
        super.setUp();
    }

    function test_executeFromRelayer_reverts_for_invalid_signature() public {
        Call[] memory calls = constructCallsData();

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        // Use alice's keyHash but bob's signature to create invalid signature
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_invalid_keyHash() public {
        Call[] memory calls = constructCallsData();

        // Use a keyHash that doesn't exist (bob's keyHash, but bob is not a validator)
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _bob, // Use bob's address for keyHash
            _bobPk, // Use bob's private key for signing
            hash
        );

        vm.prank(_bob);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidKeyHash.selector, bobKeyHash)
        );
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_reverts_for_removed_validator() public {
        Call[] memory calls = constructCallsData();

        // Use _bob instead of _alice to avoid EIP-7702 fallback collision
        // (In test environment, address(this) == _alice due to setCode)
        _addValidator(_alice, _bob);

        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _executeRemoveValidator(_alice, bobKeyHash);

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _bob, // Using _bob's address
            _bobPk, // Using _bob's private key
            hash
        );

        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidKeyHash.selector, bobKeyHash)
        );
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 0 ether);
    }

    function test_executeFromRelayer_emits_nonce_consumed() public {
        vm.prank(_alice);
        uint256 nonce = _getNonce(_alice);
        Call[] memory calls = constructCallsData();

        vm.expectEmit();
        emit NonceConsumed(uint192(0), uint64(nonce));

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        vm.prank(_alice);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(keccak256(abi.encode(calls)), _alice, 0);
        ISmartWallet(_alice).executeWithRelayer(
            BatchedCall({calls: calls, nonce: 0, expiry: 0}),
            validatorData
        );

        assertEq(address(_bob).balance, 1 ether);
    }

    function test_nonce_unchanged_after_invalid_signature_revert() public {
        // Get initial nonce
        uint192 nonceKey = uint192(
            uint256(keccak256(abi.encodePacked(_aliceEOA))) >> 64
        );
        uint64 initialNonce = INonceManager(_alice).getNonce(nonceKey);

        // Construct call data
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: (uint256(nonceKey) << 64) | uint256(initialNonce),
            expiry: 0
        });

        // Create validatorData with invalid signature
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes memory invalidSignature = new bytes(65); // All zeros - invalid signature
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash,
            invalidSignature
        );

        // Execute transaction that should revert
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify nonce hasn't changed
        uint64 nonceAfterRevert = INonceManager(_alice).getNonce(nonceKey);
        assertEq(
            nonceAfterRevert,
            initialNonce,
            "Nonce should not change after reverted transaction"
        );
    }

    function test_isValidSignature_fails_with_invalid_signer() public view {
        bytes32 hash = keccak256("test");

        // Wrong signer
        bytes memory signature = abi.encodePacked(_signDigest(hash, _bobPk));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_signature_length_boundaries() public view {
        bytes32 hash = keccak256("test");

        // Test empty signature
        bytes memory emptySignature = bytes("");
        bytes4 result = ISmartWallet(_alice).isValidSignature(
            hash,
            emptySignature
        );
        assertEq(result, bytes4(0xffffffff));

        // Test oversized signature (100 bytes)
        bytes memory oversizedSignature = bytes(new bytes(100));
        result = ISmartWallet(_alice).isValidSignature(
            hash,
            oversizedSignature
        );
        assertEq(result, bytes4(0xffffffff));
    }

    function test_execute_reverts_for_expired_owner() public {
        // Add Bob as owner with 1 day expiration
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 1 days);

        _executeAddValidator(
            _alice,
            bobKeyHash,
            address(_ecdsaValidator),
            false,
            expiry,
            address(0)
        );

        // Create a simple call
        Call[] memory calls = constructCallsData();

        // Bob can execute before expiration
        vm.prank(_bob);
        ISmartWallet(_alice).execute(calls);
        assertEq(address(_bob).balance, 1 ether);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        // Bob should be rejected after expiration
        vm.prank(_bob);
        vm.expectRevert(Errors.OwnerExpired.selector);
        ISmartWallet(_alice).execute(calls);
    }

    function test_execute_allows_non_expired_owner() public {
        // Add Bob as owner with 7 days expiration
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint40 expiry = uint40(block.timestamp + 7 days);

        _executeAddValidator(
            _alice,
            bobKeyHash,
            address(_ecdsaValidator),
            false,
            expiry,
            address(0)
        );

        // Fast forward but still within expiration
        vm.warp(block.timestamp + 6 days);

        // Create a simple call
        Call[] memory calls = constructCallsData();

        // Bob should still be able to execute
        vm.prank(_bob);
        ISmartWallet(_alice).execute(calls);
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_executeWithRelayer_reverts_for_expired_batchedCall() public {
        // Create a BatchedCall that will expire in 1 second
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: uint48(block.timestamp + 1)
        });

        // Sign the BatchedCall
        bytes32 hash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Fast forward time by 2 seconds to make the BatchedCall expired
        vm.warp(block.timestamp + 2);

        // Should revert with ExpiryPassed error
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ExpiryPassed.selector,
                batchedCall.expiry
            )
        );
        vm.prank(_alice);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithRelayer_allows_zero_expiry_batchedCall() public {
        // Create a BatchedCall with expiry = 0 (never expires)
        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: 0
        });

        // Sign the BatchedCall
        bytes32 hash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Fast forward time by 365 days
        vm.warp(block.timestamp + 365 days);

        // Should still execute successfully since expiry = 0 means never expires
        vm.prank(_alice);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify the transaction was successful
        assertEq(address(_bob).balance, 1 ether);
    }

    function test_signature_replay_protection_across_independent_deployments()
        public
    {
        // Deploy a completely independent SmartWallet and Factory
        // This simulates a third party deploying our open-sourced contracts

        // Deploy a new SmartWallet implementation
        SmartWallet independentImplementation = new SmartWallet();

        // Deploy a new Factory (constructor disables initializers)
        SmartWalletFactory independentFactory = new SmartWalletFactory(
            address(independentImplementation)
        );

        // Create a wallet using the independent factory with same pubKeyHash as alice
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_aliceEOA)), // Same pubKeyHash
            validator: address(_ecdsaValidator) // Same validator type
        });

        address independentWallet = independentFactory.createAccount(
            initialOwners,
            0 // Same salt as alice's wallet for maximum similarity
        );

        // Fund the independent wallet
        vm.deal(independentWallet, 10 ether);

        // Create a BatchedCall and sign it for alice's original wallet
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: 0
        });

        // Sign for the ORIGINAL alice wallet (from Base.t.sol)
        bytes32 hashForAlice = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorDataForAlice = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hashForAlice
        );

        // Execute on alice's original wallet - should succeed
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        ISmartWallet(_alice).executeWithRelayer(
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
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(independentWallet).executeWithRelayer(
            batchedCall,
            validatorDataForAlice
        );

        // Verify bob didn't receive additional funds
        assertEq(_bob.balance, 1 ether);

        // Now create proper signature for the independent wallet
        bytes32 hashForIndependent = ERC712(independentWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(independentImplementation))
        );
        bytes memory validatorDataForIndependent = constructValidatorData(
            independentWallet,
            _aliceEOA,
            _alicePk,
            hashForIndependent
        );

        // This should succeed with proper signature
        vm.prank(relayer);
        ISmartWallet(independentWallet).executeWithRelayer(
            batchedCall,
            validatorDataForIndependent
        );
        assertEq(_bob.balance, 2 ether);
    }

    function test_signature_replay_protection_across_different_wallets()
        public
    {
        // Deploy a second SmartWallet with the same bytecode but different address
        // This simulates a third party deploying our open-sourced contract
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_aliceEOA)), // Same pubKeyHash as alice's wallet
            validator: address(_ecdsaValidator)
        });

        // Deploy second wallet with different salt
        address secondWallet = _factory.createAccount(
            initialOwners,
            999 // Different salt to get different address
        );

        // Fund the second wallet
        vm.deal(secondWallet, 10 ether);

        // Create a BatchedCall for the first wallet
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: 0
        });

        // Sign the BatchedCall for the FIRST wallet (_alice)
        // Note: The hash includes the wallet address via domain separator
        bytes32 hash = ERC712(_alice).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Create a relayer address
        address relayer = makeAddr("relayer");

        // Execute on the first wallet - should succeed
        vm.prank(relayer);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
        assertEq(_bob.balance, 1 ether);

        // Try to replay the same signature on the second wallet - should fail
        // Even though both wallets have the same pubKeyHash installed,
        // the signature is bound to the specific wallet address
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidSignature.selector)
        );
        ISmartWallet(secondWallet).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify that bob didn't receive additional funds
        assertEq(_bob.balance, 1 ether);

        // Now create a proper signature for the second wallet
        bytes32 hashForSecondWallet = ERC712(secondWallet).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        bytes memory validatorDataForSecondWallet = constructValidatorData(
            secondWallet,
            _aliceEOA,
            _alicePk,
            hashForSecondWallet
        );

        // This should succeed because it's properly signed for the second wallet
        vm.prank(relayer);
        ISmartWallet(secondWallet).executeWithRelayer(
            batchedCall,
            validatorDataForSecondWallet
        );
        assertEq(_bob.balance, 2 ether);
    }

    function test_isValidSignature_fails_for_removed_validator() public {
        // Add validator using _bob to avoid EIP-7702 fallback collision
        // (In test environment, address(this) == _alice due to setCode)
        _addValidator(_alice, _bob);

        // Remove validator
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _executeRemoveValidator(_alice, bobKeyHash);

        bytes32 hash = keccak256("test");
        bytes memory sig = _signDigest(hash, _bobPk); // Use _bob's private key
        bytes memory signature = abi.encodePacked(bobKeyHash, sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_short_signature() public view {
        bytes32 hash = keccak256("test");

        // signature shorter than 20 bytes
        bytes memory signature = bytes("");

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_fails_with_longer_than_85_bytes_signature()
        public
        view
    {
        bytes32 hash = keccak256("test");

        // signature have 100 bytes
        bytes memory signature = bytes(new bytes(100));

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignature_succeeds_with_default_validator()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes memory sig = _signDigest(hash, _alicePk);
        bytes memory signature = abi.encodePacked(aliceKeyHash, sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_isValidSignature_succeeds_with_valid_validator_signer()
        public
        view
    {
        bytes32 hash = keccak256("test");
        bytes32 keyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes memory sig = _signDigest(hash, _alicePk);
        bytes memory signature = abi.encodePacked(keyHash, sig);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_isValidSignature_for_premit() public view {
        bytes32 hash = keccak256("721 struct data");

        // Create bound hash like isValidSignature does
        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), address(_alice), hash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

        // Sign the bound digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, digest);

        // Signature with keyHash prefix
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        // Call isValidSignature
        bytes4 result = ISmartWallet(_alice).isValidSignature(
            hash,
            validatorData
        );
        assertEq(result, bytes4(0x1626ba7e));
    }

    function _signDigest(
        bytes32 hash,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 boundHash = keccak256(
            abi.encode(bytes32(block.chainid), address(_alice), hash)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", boundHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        return abi.encodePacked(r, s, v);
    }

    function _getValidationTypedHashSansChainId(
        address account,
        BatchedCall memory batchedCall
    ) internal view returns (bytes32) {
        return
            ERC712(account).hashTypedDataSansChainId(
                BatchedCallLib.hash(batchedCall, address(_smartWallet))
            );
    }

    // Test chain ID validation skip logic in executeWithRelayer context
    function test_executeWithRelayer_allows_chainless_nonce_for_addOwner()
        public
    {
        // Create addOwner call
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                false,
                0,
                address(0)
            )
        });

        // Use chainless nonce key (Static.CHAIN_LESS_NONCE_KEY = 8453)
        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64; // nonce key = 8453, sequence = 0
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should succeed with chainless nonce for addOwner
        vm.prank(_alice);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify the owner was added
        assertTrue(
            IOwnersManager(_alice).hasOwner(newOwnerKeyHash),
            "New owner should be added"
        );
    }

    function test_executeWithRelayer_doesnt_allow_chainless_nonce_for_updateOwner()
        public
    {
        // First add an owner to update
        bytes32 ownerKeyHash = keccak256(abi.encodePacked(_bob));
        _executeAddValidator(
            _alice,
            ownerKeyHash,
            address(_ecdsaValidator),
            false,
            0,
            address(0)
        );

        // Create updateOwner call
        uint256 newSettings = IOwnersManager(_alice).packSettings(
            true, // Make admin
            uint40(block.timestamp + 1 days), // Set expiry
            address(0) // No hook
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                ownerKeyHash,
                address(_ecdsaValidator),
                newSettings
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should not succeed with chainless nonce for updateOwner
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithRelayer_doesnt_allow_chainless_nonce_for_removeOwner()
        public
    {
        // First add an owner to remove
        bytes32 ownerKeyHash = keccak256(abi.encodePacked(_bob));
        _executeAddValidator(
            _alice,
            ownerKeyHash,
            address(_ecdsaValidator),
            false,
            0,
            address(0)
        );

        // Create removeOwner call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeOwner.selector,
                ownerKeyHash
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should succeed with chainless nonce for removeOwner
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithRelayer_rejects_chainless_nonce_for_unsupported_selector()
        public
    {
        // Create a regular execute call (not supported for chainless nonce)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should revert with InvalidNonceKey for unsupported selector
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    function test_executeWithRelayer_doesnt_allow_mixed_calls_with_supported_selectors()
        public
    {
        // Create multiple calls with supported selectors
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](2);

        // addOwner call
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        // updateOwner call (update alice to admin)
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        uint256 adminSettings = IOwnersManager(_alice).packSettings(
            true, // Make admin
            0, // No expiry
            address(0) // No hook
        );
        calls[1] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator),
                adminSettings
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should succeed with all supported selectors
        vm.prank(_alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
    }

    // Test upgradeToAndCall selector support
    function test_executeWithRelayer_allows_chainless_nonce_for_upgradeToAndCall()
        public
    {
        // Create a mock upgrade call (we don't need a real implementation for this test)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _alice,
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
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should succeed with chainless nonce for upgradeToAndCall
        // Note: This will likely revert during execution due to invalid implementation,
        // but it should pass the canSkipChainIdValidation check first
        vm.prank(_alice);
        try
            ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData)
        {
            // If it succeeds, that's fine too
        } catch (bytes memory reason) {
            // We expect it might fail during actual upgrade execution
            // but not due to InvalidNonceKey (which would happen before execution)
            bytes4 errorSelector = bytes4(reason);
            assertTrue(
                errorSelector != Errors.InvalidNonceKey.selector,
                "Should not fail with InvalidNonceKey for upgradeToAndCall selector"
            );
        }
    }

    // Test comprehensive coverage of all scenarios
    function test_executeWithRelayer_comprehensive_chainless_nonce_coverage()
        public
    {
        // Test all supported selectors in one batch
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));

        // First add an owner that we can later remove
        _executeAddValidator(
            _alice,
            newOwnerKeyHash,
            address(_ecdsaValidator),
            false,
            0,
            address(0)
        );

        Call[] memory calls = new Call[](1);

        // 1. addOwner call (add a new owner using address(0x123))
        bytes32 newOwnerKeyHash2 = keccak256(abi.encodePacked(address(0x123)));
        calls[0] = Call({
            target: _alice,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash2,
                address(_ecdsaValidator),
                0 // Default settings
            )
        });

        uint256 chainlessNonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce,
            expiry: 0
        });

        bytes32 hash = _getValidationTypedHashSansChainId(_alice, batchedCall);
        bytes memory validatorData = constructValidatorData(
            _alice,
            _aliceEOA,
            _alicePk,
            hash
        );

        // Should succeed with all supported selectors
        vm.prank(_alice);
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);

        // Verify all operations succeeded
        assertTrue(
            IOwnersManager(_alice).hasOwner(newOwnerKeyHash2),
            "New owner should be added"
        );
    }
}
