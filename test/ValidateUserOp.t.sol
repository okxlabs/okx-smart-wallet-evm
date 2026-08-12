// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {ECDSAValidator} from "./validators/ECDSAValidator.sol";
import {PasskeyValidator} from "./validators/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "./utils/Helper.s.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC4337Account} from "src/ERC4337Account.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call} from "src/Types.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Mock contract moved from end of file
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

contract ValidateUserOpTest is Base {
    ECDSAValidator ecdsaValidator;
    PasskeyValidator passkeyValidator;

    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );

    function setUp() public override {
        super.setUp();

        // Deploy validators
        ecdsaValidator = new ECDSAValidator();
        passkeyValidator = new PasskeyValidator();
    }

    function test_EntryPoint_ReturnsCorrectAddress() public view {
        // Test that the entryPoint function returns the correct address
        address expectedEntryPoint = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
        address actualEntryPoint = ERC4337Account(_aliceWallet).entryPoint();

        assertEq(
            actualEntryPoint,
            expectedEntryPoint,
            "EntryPoint address should match the expected ERC-4337 EntryPoint"
        );

        // Also verify it matches the constant defined in Base.t.sol
        assertEq(
            actualEntryPoint,
            ENTRYPOINT_ADDRESS,
            "EntryPoint should match the ENTRYPOINT_ADDRESS constant"
        );
    }

    // Allow this test contract to receive ETH from EntryPoint
    receive() external payable {}

    // Helper function to directly test validateUserOp by pranking as EntryPoint
    struct TestTemps {
        bytes32 userOpHash;
        address signer;
        uint256 privateKey;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 missingAccountFunds;
    }

    function test_HandleOps_CompleteFlow_Success() external {
        // Test the complete ERC-4337 flow: handleOps -> validateUserOp -> executeUserOp

        // Create a new account with alice as owner
        bytes32 aliceKeyHash = _makeKeyHash(_alice);
        address account = _deployAccountSingleOwner(
            aliceKeyHash,
            address(1), // Built-in ECDSA validator
            100 // Different salt to avoid collision
        );

        // Fund the account for gas
        vm.deal(account, 10 ether);

        // Prepare calls to be executed - transfer 1 ETH to bob
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        // Encode the calls for executeUserOp
        // The EntryPoint will call executeUserOp, so callData needs the selector
        // executeUserOp then extracts calls from userOp.callData[4:]
        bytes memory encodedCalls = abi.encode(calls);
        bytes memory callData = abi.encodePacked(
            IERC4337Account.executeUserOp.selector,
            encodedCalls
        );

        // Build the UserOperation
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: account,
            nonce: 0,
            initCode: bytes(""),
            callData: callData,
            accountGasLimits: bytes32((uint256(3000000) << 128) | 100000), // verificationGasLimit | callGasLimit
            preVerificationGas: 21000,
            gasFees: bytes32((uint256(1 gwei) << 128) | 10 gwei), // maxPriorityFeePerGas | maxFeePerGas
            paymasterAndData: bytes(""),
            signature: bytes("")
        });

        // Get the userOp hash for signing
        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        // Use helper function to construct signature
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            userOpHash,
            account
        );

        // Record bob's initial balance
        uint256 bobInitialBalance = _bob.balance;

        // Create array with single UserOperation
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Execute handleOps - this should:
        // 1. Call validateUserOp on the account (validation phase)
        // 2. If validation passes, call executeUserOp on the account (execution phase)
        // 3. Execute the actual calls (transfer 1 ETH to bob)

        // Expect the UserOperationEvent to be emitted
        vm.expectEmit(true, true, true, false);
        emit UserOperationEvent(
            userOpHash,
            account,
            address(0), // no paymaster
            0, // nonce
            true, // success
            0, // actualGasCost (we don't check exact value)
            0 // actualGasUsed (we don't check exact value)
        );

        // Execute through EntryPoint's handleOps
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(address(this)));

        // Verify the call was executed successfully
        assertEq(
            _bob.balance,
            bobInitialBalance + 1 ether,
            "Bob should have received 1 ETH"
        );

        // Verify nonce was consumed
        uint256 accountNonce = IEntryPoint(ENTRYPOINT_ADDRESS).getNonce(
            account,
            0
        );
        assertEq(accountNonce, 1, "Account nonce should be incremented");
    }

    function test_HandleOps_WithChainlessNonce_Success() external {
        // Test handleOps with chainless nonce for cross-chain operations

        // Create a new account
        bytes32 aliceKeyHash = _makeKeyHash(_alice);
        bytes32 bobKeyHash = _makeKeyHash(_bob);
        address account = _deployAccountSingleOwner(
            aliceKeyHash,
            address(1),
            101 // Different salt
        );

        vm.deal(account, 10 ether);

        // Prepare addOwner call (allowed with chainless nonce)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                bobKeyHash,
                address(1),
                _packSettings(false, 0, address(0))
            )
        });

        bytes memory encodedCalls = abi.encode(calls);
        bytes memory callData = abi.encodePacked(
            IERC4337Account.executeUserOp.selector,
            encodedCalls
        );

        // Build UserOperation with chainless nonce
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: account,
            nonce: _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0), // Chainless nonce key
            initCode: bytes(""),
            callData: callData,
            accountGasLimits: bytes32((uint256(3000000) << 128) | 100000),
            preVerificationGas: 21000,
            gasFees: bytes32((uint256(1 gwei) << 128) | 10 gwei),
            paymasterAndData: bytes(""),
            signature: bytes("")
        });

        // Use helper function to construct signature for chainless nonce
        bytes32 baseUserOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            baseUserOpHash,
            account
        );

        // Verify bob is not an owner yet
        assertFalse(
            IOwnerManager(account).hasOwner(bobKeyHash),
            "Bob should not be owner initially"
        );

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Execute through EntryPoint
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(address(this)));

        // Verify bob was added as owner
        assertTrue(
            IOwnerManager(account).hasOwner(bobKeyHash),
            "Bob should be added as owner"
        );
    }

    function test_RevertWhen_HandleOps_WithExpiredValidUntil() external {
        // Test that EntryPoint rejects UserOperation when validUntil has expired

        // Setup account with initial balance
        address account = _aliceWallet;
        vm.deal(account, 1 ether);

        // Create UserOp with transfer call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.1 ether, data: ""});

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.nonce = 0;
        userOp.callData = _encodeExecuteUserOpCalls(calls);
        userOp.accountGasLimits = bytes32(
            abi.encodePacked(uint128(100000), uint128(100000))
        );
        userOp.preVerificationGas = 21000;
        userOp.gasFees = bytes32(
            abi.encodePacked(uint128(1 gwei), uint128(1 gwei))
        );

        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        // Set expired validUntil (1 second ago to avoid underflow)
        vm.warp(2 hours); // Set block.timestamp to 2 hours
        uint48 expiredValidUntil = uint48(block.timestamp - 1);

        // Create signature with expired validUntil
        bytes32 keyHash = _makeKeyHash(_alice);
        bytes32 finalHash = _getValidateUserOpHash(
            userOp,
            userOpHash,
            expiredValidUntil,
            account
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, finalHash);
        userOp.signature = abi.encodePacked(
            keyHash,
            expiredValidUntil,
            r,
            s,
            v
        );

        // Prepare for handleOps call
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Record initial balance
        uint256 bobInitialBalance = _bob.balance;

        // Fund the EntryPoint for gas
        vm.deal(ENTRYPOINT_ADDRESS, 10 ether);

        // Call handleOps - should fail due to expired validUntil
        // EntryPoint checks the validUntil in the returned validation data
        vm.expectRevert();
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(address(this)));

        // Verify transfer didn't happen
        assertEq(
            _bob.balance,
            bobInitialBalance,
            "Transfer should not have occurred"
        );
    }

    function test_HandleOps_WithFutureValidUntil_Success() external {
        // Test that EntryPoint accepts UserOperation when validUntil is in the future

        // Setup account with initial balance
        address account = _aliceWallet;
        vm.deal(account, 1 ether);

        // Create UserOp with transfer call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.1 ether, data: ""});

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.nonce = 0;
        // executeUserOp expects: selector + abi.encode(calls)
        userOp.callData = abi.encodeWithSelector(
            IERC4337Account.executeUserOp.selector,
            calls
        );
        userOp.accountGasLimits = bytes32(
            abi.encodePacked(uint128(200000), uint128(200000))
        );
        userOp.preVerificationGas = 21000;
        userOp.gasFees = bytes32(
            abi.encodePacked(uint128(1 gwei), uint128(1 gwei))
        );

        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        // Set future validUntil (1 hour from now)
        vm.warp(1 hours); // Set block.timestamp
        uint48 futureValidUntil = uint48(block.timestamp + 1 hours);

        // Create signature with future validUntil
        bytes32 keyHash = _makeKeyHash(_alice);
        bytes32 finalHash = _getValidateUserOpHash(
            userOp,
            userOpHash,
            futureValidUntil,
            account
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, finalHash);
        userOp.signature = abi.encodePacked(keyHash, futureValidUntil, r, s, v);

        // Prepare for handleOps call
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Record initial balance
        uint256 bobInitialBalance = _bob.balance;

        // Fund the EntryPoint for gas
        vm.deal(ENTRYPOINT_ADDRESS, 10 ether);

        // Call handleOps - should succeed with future validUntil
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(address(this)));

        // Verify transfer happened
        assertEq(
            _bob.balance,
            bobInitialBalance + 0.1 ether,
            "Transfer should have occurred"
        );
    }

    function test_ValidateUserOp_WithEoaSigner_Success() external {
        vm.prank(_alice);

        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(1),
            0
        );

        TestTemps memory t;
        t.userOpHash = keccak256("123");
        t.signer = _aliceWallet;
        t.privateKey = _alicePk;
        t.missingAccountFunds = 123;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        PackedUserOperation memory userOp;
        // Use helper function to construct signature
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            t.privateKey,
            t.userOpHash,
            account
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

        // Create invalid signature for failure test
        // First get valid signature, then corrupt it
        bytes memory validSignature = _constructUserOpSignature(
            userOp,
            _alice,
            t.privateKey,
            t.userOpHash,
            account
        );
        // Corrupt the signature by flipping one bit in the 's' component (at position 70)
        bytes memory invalidSignature = validSignature;
        invalidSignature[70] = bytes1(uint8(validSignature[70]) ^ 1);
        userOp.signature = invalidSignature;

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
        vm.expectRevert(IERC4337Account.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            t.userOpHash,
            t.missingAccountFunds
        );
    }

    function test_ValidateUserOp_WithEoaSignerAndChainlessNonce_Success()
        external
    {
        bytes32 _bobKeyHash = _makeKeyHash(_bob);

        TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                _bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        userOp.callData = _encodeExecuteUserOpCalls(calls);

        t.signer = _alice; // signer is EOA
        t.privateKey = _alicePk;
        t.missingAccountFunds = 123;
        vm.deal(_aliceWallet, 1 ether);
        assertEq(_aliceWallet.balance, 1 ether);

        // Get the base userOp hash for chainless signature
        bytes32 baseHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        // Use helper function to construct chainless signature
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            baseHash,
            _aliceWallet
        );

        // Use the simplified version that auto-calculates hash
        assertEq(
            _testValidateUserOp(_aliceWallet, userOp, t.missingAccountFunds),
            0
        );
        assertEq(
            address(ENTRYPOINT_ADDRESS).balance,
            100 ether + t.missingAccountFunds
        );
    }

    function test_ValidateUserOp_WithEoaSignerAndChainlessNonce_UopHashError_ReturnsSigValidationFailed()
        external
    {
        bytes32 _bobKeyHash = _makeKeyHash(_bob);

        TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                _bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        userOp.callData = _encodeExecuteUserOpCalls(calls);

        t.userOpHash = keccak256("123");
        t.signer = _alice; // fixed: signer is EOA, not account
        t.privateKey = _alicePk;
        t.missingAccountFunds = 123;
        vm.deal(_aliceWallet, 1 ether); // fund the account
        assertEq(_aliceWallet.balance, 1 ether);

        // This test uses a fixed userOpHash that doesn't match proper chainless calculation
        // For this specific error test, manually create signature to match test expectations
        uint48 validUntil = 0;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(t.privateKey, t.userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            validUntil,
            abi.encodePacked(r, s, v)
        );
        assertEq(
            _testValidateUserOp(
                _aliceWallet, // validating the account
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED
        );
    }

    function test_ValidateUserOp_WithEoaSignerAndChainlessNonce_CalldataError_ReturnsSigValidationFailed()
        external
    {
        TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(OwnerManager.ownerCount.selector)
        });

        userOp.callData = _encodeExecuteUserOpCalls(calls);

        t.userOpHash = keccak256("123");
        t.signer = _alice; // signer is EOA
        t.privateKey = _alicePk;
        t.missingAccountFunds = 123;
        vm.deal(_aliceWallet, 1 ether);
        assertEq(_aliceWallet.balance, 1 ether);

        // This test uses a fixed userOpHash that doesn't match proper chainless calculation
        // For this specific error test, manually create signature to match test expectations
        uint48 validUntil = 0;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(t.privateKey, t.userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            validUntil,
            abi.encodePacked(r, s, v)
        );
        assertEq(
            _testValidateUserOp(
                _aliceWallet,
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED
        );
    }

    function test_ValidateUserOp_WithEcdsaValidator_Success() external {
        // Create account with ECDSA validator
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        TestTemps memory t;
        t.userOpHash = keccak256("test_ecdsa_validation");
        t.privateKey = _alicePk;
        t.missingAccountFunds = 1000;
        vm.deal(address(account), 2 ether);

        PackedUserOperation memory userOp;

        // Use helper function to construct signature
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            t.privateKey,
            t.userOpHash,
            address(account)
        );

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

        // Create invalid signature for failure test
        bytes memory validSignature = _constructUserOpSignature(
            userOp,
            _alice,
            t.privateKey,
            t.userOpHash,
            address(account)
        );
        // Corrupt the signature by flipping one bit in the 's' component
        bytes memory invalidSignature = validSignature;
        invalidSignature[70] = bytes1(uint8(validSignature[70]) ^ 1);
        userOp.signature = invalidSignature;

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

    function test_ValidateUserOp_WithPasskeyValidator_Success() external {
        // Create account with Passkey validator
        bytes32 passkeyHash = keccak256(
            abi.encodePacked(_passkeyPubX, _passkeyPubY)
        );
        address account = _deployAccountSingleOwner(
            passkeyHash,
            address(passkeyValidator),
            0
        );

        TestTemps memory t;
        // Use a specific hash that matches the passkey test signature
        t
            .userOpHash = 0x34753a30843cdf97fd7c7f1cf2556d397c93bdfa6732b0b8b79bad029f5875e5;
        t.missingAccountFunds = 1000;
        vm.deal(address(account), 2 ether);

        bytes32 passkeyHashWithValidUntil = MessageHashUtils
            .toEthSignedMessageHash(
                keccak256(
                    abi.encode(
                        t.userOpHash,
                        uint48(0),
                        ISmartWallet(account).IMPLEMENTATION()
                    )
                )
            );
        (, , bytes32 messageHash) = HelperLib.getPasskeyMessageHash(
            passkeyHashWithValidUntil
        );
        (bytes32 r, bytes32 s) = vm.signP256(_passkeyPrivateKey, messageHash);

        // Create Passkey signature with WebAuthn auth
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(
            passkeyHashWithValidUntil,
            uint256(r),
            uint256(s)
        );

        bytes memory sig = abi.encode(auth, new bytes32[](0)); // No merkle proofs
        bytes memory validatorData = abi.encodePacked(
            uint48(0), // validUntil (0 means no expiry)
            abi.encode(
                PasskeyValidatorLib.PasskeyPubKey({
                    pubKeyX: _passkeyPubX,
                    pubKeyY: _passkeyPubY
                })
            ),
            sig
        );

        PackedUserOperation memory userOp;
        // Note: Passkey validator uses different format - keyHash + validatorData
        // The validatorData already contains validUntil (6 bytes at offset after pubkey)
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
            uint48(0), // validUntil (0 means no expiry)
            sig
        );
        // Note: Invalid passkey test with different format
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

    function test_ValidateUserOp_OnlyEntryPointModifier_Success() external {
        // Create account
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("test");
        uint256 missingAccountFunds = 100;

        // Test 1: Direct call from non-EntryPoint should revert
        vm.expectRevert(IERC4337Account.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );

        // Test 2: Call from another EOA should revert
        vm.prank(_bob);
        vm.expectRevert(IERC4337Account.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );

        // Test 3: Call from the account itself should still revert (not EntryPoint)
        vm.prank(account);
        vm.expectRevert(IERC4337Account.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );

        // Test 4: Only the actual EntryPoint can call
        // Use helper function to construct valid signature
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            userOpHash,
            account
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

    function test_ValidateUserOp_SignatureValidationEdgeCases_Success()
        external
    {
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        vm.deal(account, 1 ether);

        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("edge_case_test");
        uint256 missingAccountFunds = 100;

        // Test 1: Empty signature - needs at least 38 bytes for keyHash + validUntil
        userOp.signature = new bytes(38); // 38 bytes of zeros (keyHash + validUntil)
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

        // Test 2: Only keyHash + validUntil, no actual signature
        uint48 validUntil = 0;
        userOp.signature = abi.encodePacked(_aliceWalletKeyHash, validUntil);
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
        // Use helper to create signature, then corrupt the keyHash portion
        bytes memory validSignature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            userOpHash,
            account
        );
        bytes32 wrongKeyHash = _makeKeyHash(_bob);
        // Replace the keyHash in the signature (first 32 bytes)
        assembly {
            mstore(add(validSignature, 32), wrongKeyHash)
        }
        userOp.signature = validSignature;

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
            _aliceWalletKeyHash,
            validUntil,
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

    function test_ValidateUserOp_SignatureTooShort_ReturnsSigValidationFailed()
        external
    {
        // Test that validateUserOp returns SIG_VALIDATION_FAILED when signature is too short
        address account = _aliceWallet;

        // Create a user operation with a short signature (less than 38 bytes)
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: account,
            nonce: 0,
            initCode: bytes(""),
            callData: abi.encodeWithSelector(
                ISmartWallet.execute.selector,
                constructCallsData()
            ),
            accountGasLimits: bytes32((uint256(3000000) << 128) | 100000),
            preVerificationGas: 21000,
            gasFees: bytes32((uint256(1 gwei) << 128) | 10 gwei),
            paymasterAndData: bytes(""),
            signature: new bytes(37) // Just under minimum (should be at least 38)
        });

        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );
        uint256 missingAccountFunds = 0;

        // Should return SIG_VALIDATION_FAILED (1)
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED,
            "Short signature should fail validation"
        );

        // Test with empty signature
        userOp.signature = "";
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED,
            "Empty signature should fail validation"
        );

        // Test with only pubKeyHash (32 bytes, missing validUntil)
        userOp.signature = abi.encodePacked(bytes32(0));
        assertEq(
            _testValidateUserOp(
                account,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            Static.SIG_VALIDATION_FAILED,
            "32-byte signature should fail validation"
        );
    }

    // Test canSkipChainIdValidation logic in validateUserOp context
    function test_ValidateUserOp_AllowsChainlessNonceForAddOwner_Success()
        external
    {
        // Create addOwner call
        bytes32 newOwnerKeyHash = _makeKeyHash(_bob);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet, // use existing _aliceWallet account
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0); // Use chainless nonce
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Use new unified helper to prepare and sign
        (userOp.signature, ) = _prepareAndSignUserOp(
            userOp,
            _alice,
            _alicePk,
            _aliceWallet
        );

        uint256 missingAccountFunds = 100;

        // Should succeed for addOwner with chainless nonce
        assertEq(
            _testValidateUserOp(_aliceWallet, userOp, missingAccountFunds),
            0,
            "addOwner should succeed with chainless nonce"
        );
    }

    function test_ValidateUserOp_DoesntAllowChainlessNonceForUpdateOwner_ReturnsSigValidationFailed()
        external
    {
        // Create account with ECDSA validator
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        vm.deal(account, 2 ether);

        // Create updateOwner call (make alice admin)
        uint256 adminSettings = _packSettings(
            true,
            0,
            address(0)
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.updateOwner.selector,
                _aliceWalletKeyHash,
                address(ecdsaValidator),
                adminSettings
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Use new unified helper to prepare and sign
        (userOp.signature, ) = _prepareAndSignUserOp(
            userOp,
            _alice,
            _alicePk,
            account
        );

        uint256 missingAccountFunds = 100;

        // Should fail for updateOwner with chainless nonce
        assertEq(
            _testValidateUserOp(account, userOp, missingAccountFunds),
            Static.SIG_VALIDATION_FAILED,
            "updateOwner should not succeed with chainless nonce"
        );
    }

    function test_ValidateUserOp_DoesNotAllowChainlessNonceForRemoveOwner_ReturnsSigValidationFailed()
        external
    {
        // Create account with ECDSA validator
        bytes32 _bobKeyHash = _makeKeyHash(_bob);
        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = _aliceWalletKeyHash;
        keyHashes[1] = _bobKeyHash;
        address[] memory validators = new address[](2);
        validators[0] = address(ecdsaValidator);
        validators[1] = address(ecdsaValidator);
        address account = _deployAccountWithOwners(keyHashes, validators, 0);

        vm.deal(account, 2 ether);

        // Create removeOwner call (remove bob)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                _bobKeyHash
            )
        });

        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Use new unified helper to prepare and sign
        (userOp.signature, ) = _prepareAndSignUserOp(
            userOp,
            _alice,
            _alicePk,
            account
        );

        uint256 missingAccountFunds = 100;

        // Should fail for removeOwner with chainless nonce
        assertEq(
            _testValidateUserOp(account, userOp, missingAccountFunds),
            Static.SIG_VALIDATION_FAILED,
            "removeOwner should not succeed with chainless nonce"
        );
    }

    function test_ValidateUserOp_RejectsChainlessNonceForUnsupportedSelector_ReturnsSigValidationFailed()
        external
    {
        // Create account with ECDSA validator
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        vm.deal(account, 2 ether);

        // Create regular transfer call (not supported for chainless nonce)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Use new unified helper to prepare and sign
        (userOp.signature, ) = _prepareAndSignUserOp(
            userOp,
            _alice,
            _alicePk,
            account
        );

        uint256 missingAccountFunds = 100;

        // Should return SIG_VALIDATION_FAILED for unsupported selector
        assertEq(
            _testValidateUserOp(account, userOp, missingAccountFunds),
            Static.SIG_VALIDATION_FAILED,
            "Should return validation failed for unsupported selector with chainless nonce"
        );
    }

    function test_ValidateUserOp_ComprehensiveChainlessNonceCoverage_Success()
        external
    {
        // Create account with ECDSA validator
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        vm.deal(account, 2 ether);

        // Create multiple supported calls in one batch
        bytes32 newOwnerKeyHash = _makeKeyHash(_bob);
        Call[] memory calls = new Call[](1);

        // 1. addOwner call
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(ecdsaValidator),
                0
            )
        });
        PackedUserOperation memory userOp;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0);
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Use new unified helper to prepare and sign
        (userOp.signature, ) = _prepareAndSignUserOp(
            userOp,
            _alice,
            _alicePk,
            account
        );

        uint256 missingAccountFunds = 100;

        // Should succeed with all supported selectors
        assertEq(
            _testValidateUserOp(account, userOp, missingAccountFunds),
            0,
            "Multiple supported selectors should succeed with chainless nonce"
        );
    }

    // ============ ChainId Replay Protection Tests ============

    function test_ValidateUserOp_WithChainId_PreventsReplayAcrossChains_Success()
        external
    {
        // Test that normal mode (with chainId) prevents replay attacks across chains
        address account = _aliceWallet;
        uint256 missingAccountFunds = 0;

        // Create a normal UserOp (not chainless)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.1 ether, data: ""});

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.nonce = 0; // Normal nonce (not chainless)
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Get hash on chain 1
        vm.chainId(1);
        bytes32 userOpHashChain1 = IEntryPoint(ENTRYPOINT_ADDRESS)
            .getUserOpHash(userOp);

        // Create signature for chain 1
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            userOpHashChain1,
            account
        );

        vm.deal(account, 1 ether);

        // Validate on chain 1 - should succeed
        uint256 result1 = _testValidateUserOp(
            address(account),
            userOp,
            userOpHashChain1,
            missingAccountFunds
        );
        assertEq(result1, 0, "Should succeed on chain 1");

        // Switch to chain 2
        vm.chainId(2);

        // Get hash on chain 2 (should be different due to chainId)
        bytes32 userOpHashChain2 = IEntryPoint(ENTRYPOINT_ADDRESS)
            .getUserOpHash(userOp);

        // The hashes should be different
        assertTrue(
            userOpHashChain1 != userOpHashChain2,
            "Hashes should differ across chains"
        );

        // Try to use the same signature on chain 2 - should fail
        uint256 result2 = _testValidateUserOp(
            address(account),
            userOp,
            userOpHashChain2,
            missingAccountFunds
        );

        assertEq(
            result2,
            Static.SIG_VALIDATION_FAILED,
            "Should fail on chain 2 with chain 1 signature"
        );
    }

    function test_ValidateUserOp_ChainlessMode_AllowsReplayAcrossChains_Success()
        external
    {
        // Test that chainless mode allows the same signature across different chains
        address account = _aliceWallet;
        uint256 missingAccountFunds = 0;

        // Create a chainless UserOp
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256("crossChainOwner"),
                address(ecdsaValidator),
                0
            )
        });

        PackedUserOperation memory userOp;
        userOp.sender = account;
        userOp.nonce = _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 1, 0); // Chainless nonce
        userOp.callData = _encodeExecuteUserOpCalls(calls);

        // Get hash on chain 1
        vm.chainId(1);
        bytes32 userOpHashChain1 = IEntryPoint(ENTRYPOINT_ADDRESS)
            .getUserOpHash(userOp);

        // Create signature for chainless operation
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            userOpHashChain1,
            account
        );

        vm.deal(account, 1 ether);
        uint256 chain1State = vm.snapshotState();

        // Validate on chain 1 - should succeed
        uint256 result1 = _testValidateUserOp(
            address(account),
            userOp,
            userOpHashChain1,
            missingAccountFunds
        );
        assertEq(result1, 0, "Should succeed on chain 1");

        // A replay happens on a different chain with independent wallet state.
        // Restore the pre-validation state so this test does not incorrectly
        // model both chains as sharing the same queue watermark.
        assertTrue(vm.revertToState(chain1State));

        // Switch to chain 2
        vm.chainId(2);

        // Get hash on chain 2
        bytes32 userOpHashChain2 = IEntryPoint(ENTRYPOINT_ADDRESS)
            .getUserOpHash(userOp);

        // The raw hashes should be different due to chainId
        assertTrue(
            userOpHashChain1 != userOpHashChain2,
            "Raw hashes should still differ across chains"
        );

        // But chainless mode should process them to be the same
        // This test may fail if the implementation is incorrect
        // The same signature should work on chain 2 in chainless mode
        uint256 result2 = _testValidateUserOp(
            address(account),
            userOp,
            userOpHashChain2,
            missingAccountFunds
        );

        // This assertion may fail if getUserOpHashWithoutChainId doesn't work correctly
        assertEq(
            result2,
            0,
            "Should succeed on chain 2 with the same signature in chainless mode"
        );
    }
}
