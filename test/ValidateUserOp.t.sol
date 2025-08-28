// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Errors} from "src/libraries/Errors.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {HelperLib} from "src/test/Helper.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC4337Account} from "src/ERC4337Account.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call} from "src/Types.sol";
import {OwnersManager} from "src/OwnersManager.sol";

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

    function test_entryPoint_returns_correct_address() public view {
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

    function test_handleOps_complete_flow() external {
        // Test the complete ERC-4337 flow: handleOps -> validateUserOp -> executeUserOp

        // Create a new account with alice as owner
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
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

        // Sign the userOp hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(aliceKeyHash, r, s, v);

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

    function test_handleOps_with_chainless_nonce() external {
        // Test handleOps with chainless nonce for cross-chain operations

        // Create a new account
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
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
                OwnersManager.addOwner.selector,
                bobKeyHash,
                address(1),
                OwnersManager(account).packSettings(false, 0, address(0))
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
            nonce: uint256(Static.CHAIN_LESS_NONCE_KEY) << 64, // Chainless nonce key
            initCode: bytes(""),
            callData: callData,
            accountGasLimits: bytes32((uint256(3000000) << 128) | 100000),
            preVerificationGas: 21000,
            gasFees: bytes32((uint256(1 gwei) << 128) | 10 gwei),
            paymasterAndData: bytes(""),
            signature: bytes("")
        });

        // Get userOp hash without chain ID for chainless operations
        bytes32 userOpHash = ERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);

        // Sign the userOp
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(aliceKeyHash, r, s, v);

        // Verify bob is not an owner yet
        assertFalse(
            IOwnersManager(account).hasOwner(bobKeyHash),
            "Bob should not be owner initially"
        );

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Execute through EntryPoint
        IEntryPoint(ENTRYPOINT_ADDRESS).handleOps(ops, payable(address(this)));

        // Verify bob was added as owner
        assertTrue(
            IOwnersManager(account).hasOwner(bobKeyHash),
            "Bob should be added as owner"
        );
    }

    function test_validateUserOp_with_eoa_signer() external {
        vm.prank(_alice);

        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(1),
            0
        );

        TestTemps memory t;
        t.userOpHash = keccak256("123");
        t.signer = _aliceWallet;
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        PackedUserOperation memory userOp;
        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
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
            _aliceWalletKeyHash,
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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 _bobKeyHash = keccak256(abi.encodePacked(_bob));

        TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                _bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        t.userOpHash = IERC4337Account(_aliceWallet)
            .getUserOpHashWithoutChainId(userOp);
        t.signer = _alice; // 签名者是 EOA
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(_aliceWallet, 1 ether);
        assertEq(_aliceWallet.balance, 1 ether);

        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            _testValidateUserOp(
                _aliceWallet,
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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 _bobKeyHash = keccak256(abi.encodePacked(_bob));

        TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                _bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        t.userOpHash = keccak256("123");
        t.signer = _alice; // 修正：签名者是 EOA，不是账户
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(_aliceWallet, 1 ether); // 给账户充值
        assertEq(_aliceWallet.balance, 1 ether);

        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            _testValidateUserOp(
                _aliceWallet, // 验证的是账户
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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));

        TestTemps memory t;
        PackedUserOperation memory userOp;
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(OwnersManager.ownerCount.selector)
        });

        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        t.userOpHash = keccak256("123");
        t.signer = _alice; // 签名者是 EOA
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 123;
        vm.deal(_aliceWallet, 1 ether);
        assertEq(_aliceWallet.balance, 1 ether);

        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
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

    function test_validateUserOp_with_ecdsa_validator() external {
        // Create account with ECDSA validator
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
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

        // Create ECDSA signature - ECDSAValidator expects direct hash, not eth signed message hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(t.privateKey, t.userOpHash);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        PackedUserOperation memory userOp;
        // Test valid ECDSA signature
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            ecdsaSignature
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

        // Test invalid ECDSA signature
        bytes memory invalidSignature = abi.encodePacked(
            r,
            bytes32(uint256(s) ^ 1),
            v
        );
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            invalidSignature
        );

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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
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
            _aliceWalletKeyHash,
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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
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
        userOp.signature = abi.encodePacked(_aliceWalletKeyHash);
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
            _aliceWalletKeyHash,
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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));

        // Create addOwner call
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet, // 使用已有的 _aliceWallet 账户
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
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
        bytes32 userOpHash = IERC4337Account(_aliceWallet)
            .getUserOpHashWithoutChainId(userOp);

        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
            abi.encodePacked(r, s, v)
        );

        uint256 missingAccountFunds = 100;

        // Should succeed for addOwner with chainless nonce
        assertEq(
            _testValidateUserOp(
                _aliceWallet,
                userOp,
                userOpHash,
                missingAccountFunds
            ),
            0,
            "addOwner should succeed with chainless nonce"
        );
    }

    function test_validateUserOp_doesnt_allow_chainless_nonce_for_updateOwner()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
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
                _aliceWalletKeyHash,
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
            _aliceWalletKeyHash,
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
            Static.SIG_VALIDATION_FAILED,
            "updateOwner should not succeed with chainless nonce"
        );
    }

    function test_validateUserOp_doesnt_allow_chainless_nonce_for_removeOwner()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 _bobKeyHash = keccak256(abi.encodePacked(_bob));
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
            _aliceWalletKeyHash,
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
            Static.SIG_VALIDATION_FAILED,
            "removeOwner should not succeed with chainless nonce"
        );
    }

    function test_validateUserOp_rejects_chainless_nonce_for_unsupported_selector()
        external
    {
        // Create account with ECDSA validator
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
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
        userOp.nonce = Static.CHAIN_LESS_NONCE_KEY << 64;
        userOp.callData = abi.encodeWithSelector(
            ISmartWallet.execute.selector,
            calls
        );

        bytes32 userOpHash = IERC4337Account(account)
            .getUserOpHashWithoutChainId(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(
            _aliceWalletKeyHash,
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
        bytes32 _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));
        address account = _deployAccountSingleOwner(
            _aliceWalletKeyHash,
            address(ecdsaValidator),
            0
        );

        vm.deal(account, 2 ether);

        // Create multiple supported calls in one batch
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](1);

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
            _aliceWalletKeyHash,
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
