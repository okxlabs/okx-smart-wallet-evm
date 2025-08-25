// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "src/test/Helper.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC4337Account} from "src/ERC4337Account.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";

contract ValidateUserOpTest is Base {
    ECDSAValidator ecdsaValidator;
    PasskeyValidator passkeyValidator;

    function setUp() public override {
        super.setUp();

        // Deploy validators
        ecdsaValidator = new ECDSAValidator();
        passkeyValidator = new PasskeyValidator();
    }

    // Helper function to directly test validateUserOp by pranking as EntryPoint
    struct _TestTemps {
        bytes32 userOpHash;
        address signer;
        uint256 privateKey;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 missingAccountFunds;
    }

    function test_validateUserOp_with_eoa_signer() external {
        vm.prank(_alice);

        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(1)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        t.userOpHash = keccak256("123");
        t.signer = _alice;
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        PackedUserOperation memory userOp;
        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            0
        );
        assertEq(
            address(ENTRYPOINT_ADDRESS).balance,
            100 ether + t.missingAccountFunds
        );

        // Failure returns 1.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, bytes32(uint256(t.s) ^ 1), t.v)
        );

        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            1 << 96
        );
        assertEq(
            address(ENTRYPOINT_ADDRESS).balance,
            100 ether + t.missingAccountFunds * 2
        );
        // Not entry point reverts.
        vm.expectRevert(Errors.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            t.userOpHash,
            t.missingAccountFunds
        );
    }

    function test_validateUserOp_with_eoa_signer_and_chain_less_nonce()
        external
    {
        vm.prank(_alice);

        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes32 _bobKeyHash = keccak256(abi.encodePacked(_bob));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(1)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(account),
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                _bobKeyHash,
                address(1),
                0
            )
        });

        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        t.userOpHash = IERC4337Account(account).getUserOpHashWithoutChainId(
            userOp
        );
        t.signer = _alice;
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            0
        );
        assertEq(
            address(ENTRYPOINT_ADDRESS).balance,
            100 ether + t.missingAccountFunds
        );
    }

    function test_uopHash_error_validateUserOp_with_eoa_signer_and_chain_less_nonce()
        external
    {
        vm.prank(_alice);

        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes32 _bobKeyHash = keccak256(abi.encodePacked(_bob));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(1)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(account),
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                _bobKeyHash,
                address(1),
                0
            )
        });

        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        t.userOpHash = keccak256("123");
        t.signer = _alice;
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED
        );
    }

    function test_calldata_error_validateUserOp_with_eoa_signer_and_chain_less_nonce()
        external
    {
        vm.prank(_alice);

        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(1)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(account),
            value: 0,
            data: abi.encodeWithSelector(OwnersManager.ownerCount.selector)
        });

        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        t.userOpHash = keccak256("123");
        t.signer = _alice;
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED
        );
    }

    function test_validateUserOp_with_ecdsa_validator() external {
        // Create account with ECDSA validator
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        t.userOpHash = keccak256("test_ecdsa_validation");
        t.privateKey = _alicePk;
        t.missingAccountFunds = 1000;
        vm.deal(address(account), 2 ether);

        // Create ECDSA signature - ECDSAValidator expects direct hash, not eth signed message hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(t.privateKey, t.userOpHash);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp;
        // Test valid ECDSA signature
        userOp.signature = abi.encodePacked(_aliceKeyHash, ecdsaSignature);

        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            0,
            "Valid ECDSA signature should return 0"
        );

        // Test invalid ECDSA signature
        bytes memory invalidSignature = abi.encodePacked(
            r,
            bytes32(uint256(s) ^ 1),
            v
        );
        userOp.signature = abi.encodePacked(_aliceKeyHash, invalidSignature);

        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            1 << 96,
            "Invalid ECDSA signature should fail"
        );
    }

    function test_validateUserOp_with_passkey_validator() external {
        // Create account with Passkey validator
        bytes32 passkeyHash = keccak256(
            abi.encodePacked(_passkeyPubX, _passkeyPubY)
        );
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: passkeyHash,
            validator: address(passkeyValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        // Use a specific hash that matches the passkey test signature
        t
            .userOpHash = 0x34753a30843cdf97fd7c7f1cf2556d397c93bdfa6732b0b8b79bad029f5875e5;
        t.missingAccountFunds = 1000;
        vm.deal(address(account), 2 ether);

        (, , bytes32 messageHash) = HelperLib.getPasskeyMessageHash(
            t.userOpHash
        );
        (bytes32 r, bytes32 s) = vm.signP256(_passkeyPrivateKey, messageHash);

        // Create Passkey signature with WebAuthn auth
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            t.userOpHash,
            uint256(r),
            uint256(s)
        );

        bytes memory sig = abi.encode(auth, new bytes32[](0)); // No merkle proofs
        bytes memory validatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            sig
        );

        PackedUserOperation memory userOp;
        userOp.signature = abi.encodePacked(passkeyHash, validatorData);

        // Test valid Passkey signature
        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            0,
            "Valid Passkey signature should return 0"
        );

        // Test invalid Passkey signature (wrong public key)
        bytes memory invalidValidatorData = abi.encodePacked(
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: 0x1111111111111111111111111111111111111111111111111111111111111111,
                    pubKeyY: 0x2222222222222222222222222222222222222222222222222222222222222222
                })
            ),
            sig
        );
        userOp.signature = abi.encodePacked(passkeyHash, invalidValidatorData);

        assertEq(
            _testValidateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            1 << 96,
            "Invalid Passkey should fail"
        );
    }

    function test_validateUserOp_onlyEntryPoint_modifier() external {
        // Create account
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("test");
        uint256 missingAccountFunds = 100;

        // Test 1: Direct call from non-EntryPoint should revert
        vm.expectRevert(Errors.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );

        // Test 2: Call from another EOA should revert
        vm.prank(_bob);
        vm.expectRevert(Errors.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );

        // Test 3: Call from the account itself should still revert (not EntryPoint)
        vm.prank(account);
        vm.expectRevert(Errors.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );

        // Test 4: Only the actual EntryPoint can call
        // Create valid signature - use raw hash directly for ECDSA validator
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(r, s, v)
        );

        vm.deal(account, 1 ether);

        // This should succeed when called from EntryPoint
        uint256 result = _testValidateUserOp(
            address(account),
            userOp,
            userOpHash,
            missingAccountFunds
        );

        assertEq(result, 0, "Should succeed when called from EntryPoint");
    }

    function test_validateUserOp_signature_validation_edge_cases() external {
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(account, 1 ether);

        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("edge_case_test");
        uint256 missingAccountFunds = 100;

        // Test 1: Empty signature - needs at least 32 bytes for keyHash
        userOp.signature = new bytes(32); // 32 bytes of zeros
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            1 << 96,
            "Empty signature should fail"
        );

        // Test 2: Only keyHash, no actual signature
        userOp.signature = abi.encodePacked(_aliceKeyHash);
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            1 << 96,
            "Missing signature data should fail"
        );

        // Test 3: Wrong keyHash with valid signature format
        bytes32 wrongKeyHash = keccak256(abi.encodePacked(_bob));
        // Use raw hash directly for ECDSA validator
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            wrongKeyHash,
            abi.encodePacked(r, s, v)
        );

        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            1 << 96,
            "Wrong keyHash should fail"
        );

        // Test 4: Malformed signature (wrong length)
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            bytes32(0),
            bytes32(0)
        );
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            1 << 96,
            "Malformed signature should fail"
        );
    }

    // Test canSkipChainIdValidation logic in validateUserOp context
    function test_validateUserOp_allows_chainless_nonce_for_addOwner()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(account, 2 ether);

        // Create addOwner call
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash,
                address(ecdsaValidator),
                0
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64; // Use chainless nonce
        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        // Get hash without chain ID for chainless nonce
        bytes32 userOpHash = IERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);

        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should succeed for addOwner with chainless nonce
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            0,
            "addOwner should succeed with chainless nonce"
        );
    }

    function test_validateUserOp_allows_chainless_nonce_for_updateOwner()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(account, 2 ether);

        // Create updateOwner call (make alice admin)
        uint256 adminSettings = IOwnersManager(account).packSettings(
            true,
            0,
            address(0)
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                _aliceKeyHash,
                address(ecdsaValidator),
                adminSettings
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        bytes32 userOpHash = IERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should succeed for updateOwner with chainless nonce
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            0,
            "updateOwner should succeed with chainless nonce"
        );
    }

    function test_validateUserOp_allows_chainless_nonce_for_removeOwner()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bytes32 _bobKeyHash = keccak256(abi.encodePacked(_bob));
        InitialOwner[] memory initialOwners = new InitialOwner[](2);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });
        initialOwners[1] = InitialOwner({
            keyHash: _bobKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(account, 2 ether);

        // Create removeOwner call (remove bob)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeOwner.selector,
                _bobKeyHash
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        bytes32 userOpHash = IERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should succeed for removeOwner with chainless nonce
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            0,
            "removeOwner should succeed with chainless nonce"
        );
    }

    function test_validateUserOp_rejects_chainless_nonce_for_unsupported_selector()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(account, 2 ether);

        // Create regular transfer call (not supported for chainless nonce)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        bytes32 userOpHash = IERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should return SIG_VALIDATION_FAILED for unsupported selector
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED,
            "Should return validation failed for unsupported selector with chainless nonce"
        );
    }

    function test_validateUserOp_comprehensive_chainless_nonce_coverage()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(ecdsaValidator)
        });

        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(account, 2 ether);

        // Create multiple supported calls in one batch
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](2);

        // 1. addOwner call
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash,
                address(ecdsaValidator),
                0
            )
        });

        // 2. updateOwner call (make alice admin)
        uint256 adminSettings = IOwnersManager(account).packSettings(
            true,
            0,
            address(0)
        );
        calls[1] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                _aliceKeyHash,
                address(ecdsaValidator),
                adminSettings
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        bytes32 userOpHash = IERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should succeed with all supported selectors
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            0,
            "Multiple supported selectors should succeed with chainless nonce"
        );
    }
}

// Mock contract moved from mocks/MockEntryPoint.sol
contract MockEntryPoint {
    mapping(address => uint256) public balanceOf;

    function depositTo(address to) public payable {
        balanceOf[to] += msg.value;
    }

    function withdrawTo(address to, uint256 amount) public payable {
        balanceOf[msg.sender] -= amount;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success);
    }

    function validateUserOp(
        address account,
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public payable returns (uint256 validationData) {
        validationData = IERC4337Account(payable(account)).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );
    }

    receive() external payable {
        depositTo(msg.sender);
    }
}
