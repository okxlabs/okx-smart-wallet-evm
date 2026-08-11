// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";
import {Vm} from "forge-std/Vm.sol";
import {CallLib} from "src/libraries/CallLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";

contract USDCTest is EIP712 {
    constructor() {}

    function hashTypedData(
        bytes32 structHash
    ) public view returns (bytes32 digest) {
        return _hashTypedData(structHash);
    }

    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory, string memory)
    {
        return ("USDC Permit", "1.0.0");
    }
}

/// @notice Tests for SmartWalletEntry in EIP-7702 scenario (EOA delegating code to SmartWallet implementation).
contract ERC7702Test is Base {
    event ExecuteSuccessEvent(bytes32 indexed intentHash, address caller);

    address internal eoaWallet;
    uint256 internal eoaPk;
    USDCTest internal usdcPermit;
    bytes32 internal constant USDC_PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    function setUp() public override {
        super.setUp();
        relayer = makeAddr("relayer");
        (eoaWallet, eoaPk) = makeAddrAndKey("eoaNoOwners");
        Vm.SignedDelegation memory sd = vm.signDelegation(
            address(_smartWallet),
            eoaPk
        );
        vm.attachDelegation(sd);
        vm.deal(eoaWallet, 1 ether);

        usdcPermit = new USDCTest();
    }

    /// @notice getVerifiedValidator(keccak256(abi.encodePacked(eoa))) returns ECDSA for 7702 EOA (built-in owner).
    function test_ERC7702_BuiltInOwner_GetVerifiedValidator_ReturnsEcdsa()
        public
    {
        bytes32 eoaKeyHash = keccak256(abi.encodePacked(eoaWallet));
        address validator = IOwnerManager(eoaWallet).getVerifiedValidator(
            eoaKeyHash
        );
        assertEq(validator, Static.ECDSA_VALIDATOR_ADDRESS);
    }

    /// @notice Non-address(this) keyHash has no validator on uninitialized 7702 EOA.
    function test_ERC7702_NonAddressThisKeyHash_ReturnsZeroValidator() public {
        bytes32 bobKeyHash = _makeKeyHash(_bob);
        address validator = IOwnerManager(eoaWallet).getVerifiedValidator(
            bobKeyHash
        );
        assertEq(validator, address(0));
    }

    // ============ EIP-7702 Built-in Owner Execute ============

    /// @notice 7702 EOA can execute addOwner via self-call using built-in address(this) owner.
    function test_ERC7702_BuiltInOwner_Execute_SelfCallAddOwner() public {
        bytes32 newOwnerKeyHash = _makeKeyHash(_bob);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: eoaWallet,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                newOwnerKeyHash,
                Static.ECDSA_VALIDATOR_ADDRESS,
                0
            )
        });

        vm.prank(eoaWallet);
        vm.expectEmit(true, true, true, true);
        emit ExecuteSuccessEvent(CallLib.hash(calls), eoaWallet);
        ISmartWallet(eoaWallet).execute(calls);

        address validator = IOwnerManager(eoaWallet).getVerifiedValidator(
            newOwnerKeyHash
        );
        assertEq(
            validator,
            Static.ECDSA_VALIDATOR_ADDRESS,
            "New owner should be added"
        );
    }

    // ============ EIP-7702 ExecuteWithRelayer (No Initialization) ============

    /// @notice Relayer can execute on uninitialized 7702 EOA with valid EOA signature.
    function test_ERC7702_ExecuteWithRelayer_WithoutInitialization() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: INonceManager(eoaWallet).getNonce(0)
        });

        bytes memory validatorData = _constructRelayerSignature(
            eoaWallet,
            eoaWallet,
            eoaPk,
            batchedCall,
            uint48(0)
        );

        uint256 bobBefore = _bob.balance;
        vm.prank(relayer);
        ISmartWallet(eoaWallet).executeWithRelayer(batchedCall, validatorData);
        assertEq(
            _bob.balance - bobBefore,
            0.5 ether,
            "Bob should receive 0.5 ETH"
        );
    }

    /// @notice executeWithRelayer reverts with InvalidSignature when signature is from wrong key.
    function test_ERC7702_ExecuteWithRelayer_InvalidSignature_Reverts() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 0.5 ether, data: ""});
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: INonceManager(eoaWallet).getNonce(0)
        });

        // Use EOA as signer (so keyHash is valid built-in owner) but sign with wrong key
        (, uint256 wrongPk) = makeAddrAndKey("wrong");
        bytes memory validatorData = _constructRelayerSignature(
            eoaWallet,
            eoaWallet,
            wrongPk,
            batchedCall,
            uint48(0)
        );

        vm.prank(relayer);
        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        ISmartWallet(eoaWallet).executeWithRelayer(batchedCall, validatorData);
    }

    // ============ EIP-7702 isValidSignature (65-byte EOA compatibility) ============

    /// @notice 7702 post-upgrade: isValidSignature with 65-byte ECDSA from address(this) returns MAGIC_VALUE.
    function test_ERC7702_IsValidSignature_EOA65ByteSignature_ReturnsMagicValue()
        public
    {
        bytes32 hash = keccak256("message for 7702 EOA");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = ISmartWallet(eoaWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.MAGIC_VALUE,
            "65-byte EOA sig from address(this) should be valid"
        );
    }

    /// @notice isValidSignature with 65-byte sig from wrong signer returns INVALID_VALUE.
    function test_ERC7702_IsValidSignature_InvalidEOASignature_ReturnsInvalid()
        public
    {
        bytes32 hash = keccak256("message");
        (, uint256 wrongPk) = makeAddrAndKey("wrongSigner");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = ISmartWallet(eoaWallet).isValidSignature(
            hash,
            signature
        );
        assertEq(
            result,
            Static.INVALID_VALUE,
            "Wrong signer 65-byte sig should be invalid"
        );
    }

    // ============ EIP-7702 isValidSignature (ERC-712 typed data) ============

    /// @notice 7702 EOA: isValidSignature with USDC Permit ERC-712 struct hash from built-in owner returns MAGIC_VALUE.
    function test_ERC7702_IsValidSignature_USDC_PermitERC712_ReturnsMagicValue()
        public
        view
    {
        // Build USDC Permit struct hash (EIP-2612): owner approves spender for value
        address owner = eoaWallet;
        address spender = _bob;
        uint256 value = 1e6; // 1 USDC (6 decimals)
        uint256 nonce = 0;
        uint256 deadline = type(uint256).max;

        bytes32 hash = keccak256(
            abi.encode(
                USDC_PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        // Full EIP-712 digest (domain + structHash); for 65-byte sig wallet uses this as ecrecover input
        bytes32 digest = usdcPermit.hashTypedData(hash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First arg must be the digest that was signed (SmartWallet 65-byte path: ecrecover(hash, sig))
        bytes4 result = ISmartWallet(eoaWallet).isValidSignature(
            digest,
            signature
        );
        assertEq(
            result,
            Static.MAGIC_VALUE,
            "USDC Permit ERC-712 sig from 7702 built-in owner should be valid"
        );
    }
}
