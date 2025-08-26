// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {Static} from "src/libraries/Static.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {OwnersManager} from "src/OwnersManager.sol";

/**
 * @title ChainlessExecutionTest
 * @notice Comprehensive tests for chainless execution functionality and hash operations
 * @dev Tests both UserOperation and BatchedCall chainless execution paths
 */
contract ChainlessExecutionTest is Base {
    using BatchedCallLib for BatchedCall;

    address internal testAccount;
    bytes32 internal aliceKeyHash;
    bytes32 internal bobKeyHash;

    function setUp() public override {
        super.setUp();

        // Setup test key hashes - use EOA addresses, not smart wallet addresses
        aliceKeyHash = keccak256(abi.encodePacked(_aliceEOA));
        bobKeyHash = keccak256(abi.encodePacked(_bob));

        // Create test account with Alice as initial owner with admin privileges
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: aliceKeyHash,
            validator: address(_ecdsaValidator)
        });

        testAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        vm.deal(testAccount, 10 ether);
    }

    // ===================
    // Hash Function Tests
    // ===================

    /**
     * @notice Test hashTypedData and hashTypedDataSansChainId produce different results
     * @dev Ensures chain ID affects hash computation as expected
     */
    function test_hash_functions_produce_different_results() external {
        bytes32 structHash = keccak256("test_struct_hash");

        bytes32 hashWithChainId = SmartWallet(payable(testAccount))
            .hashTypedData(structHash);
        bytes32 hashWithoutChainId = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(structHash);

        assertNotEq(
            hashWithChainId,
            hashWithoutChainId,
            "Hashes should be different"
        );
    }

    /**
     * @notice Test that hashTypedDataSansChainId is consistent across different chain IDs
     * @dev Simulates cross-chain scenarios by changing chain ID
     */
    function test_hashTypedDataSansChainId_consistent_across_chains() external {
        bytes32 structHash = keccak256("test_struct_hash");

        // Get hash on current chain
        bytes32 hashChain1 = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(structHash);

        // Simulate different chain ID
        vm.chainId(42161); // Arbitrum chain ID
        bytes32 hashChain2 = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(structHash);

        // Reset to original chain
        vm.chainId(31337);

        assertEq(
            hashChain1,
            hashChain2,
            "Chainless hashes should be identical across chains"
        );
    }

    /**
     * @notice Test getUserOpHashWithoutChainId consistency
     * @dev Ensures UserOperation hashes are chain-agnostic when using chainless mode
     */
    function test_getUserOpHashWithoutChainId_consistency() external {
        PackedUserOperation memory userOp = _createChainlessAddOwnerUserOp();

        // Get hash on current chain
        bytes32 hashChain1 = IERC4337Account(testAccount)
            .getUserOpHashWithoutChainId(userOp);

        // Simulate different chain ID
        vm.chainId(8453); // Base chain ID
        bytes32 hashChain2 = IERC4337Account(testAccount)
            .getUserOpHashWithoutChainId(userOp);

        // Reset chain ID
        vm.chainId(31337);

        assertEq(
            hashChain1,
            hashChain2,
            "UserOp chainless hashes should be identical"
        );
    }

    // ================================
    // Chainless Execution Function Tests
    // ================================

    // ========================================
    // Chainless Execution - UserOperation Tests
    // ========================================
    // Note: Basic UserOp chainless validation tests already exist in ValidateUserOp.t.sol
    // These tests focus on edge cases and execution flow verification

    /**
     * @notice Test chainless UserOperation with actual execution flow
     * @dev This complements ValidateUserOp.t.sol by testing the full execution, not just validation
     */
    function test_chainless_userOp_full_execution_flow() external {
        // Create comprehensive test with multiple operations
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(_bob));
        Call[] memory calls = new Call[](2);

        // 1. Add new owner
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        // 2. Update Alice to admin
        uint256 adminSettings = SmartWallet(payable(testAccount)).packSettings(
            true,
            0,
            address(0)
        );
        calls[1] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator),
                adminSettings
            )
        });

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: testAccount,
            nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
            initCode: "",
            callData: abi.encodeWithSelector(
                ISmartWallet.execute.selector,
                calls
            ),
            accountGasLimits: bytes32((uint256(2000000) << 128) | 100000),
            preVerificationGas: 21000,
            gasFees: bytes32((uint256(1000000000) << 128) | 1000000000),
            paymasterAndData: "",
            signature: ""
        });

        // Validate with chainless hash
        bytes32 userOpHash = IERC4337Account(testAccount)
            .getUserOpHashWithoutChainId(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, userOpHash);
        userOp.signature = abi.encodePacked(aliceKeyHash, r, s, v);

        // Validation should succeed
        uint256 result = _executeUserOpThroughEntryPoint(userOp, userOpHash);
        assertEq(result, 0, "UserOp validation should succeed");

        // Execute the actual operations
        vm.prank(_aliceEOA);
        SmartWallet(payable(testAccount)).execute(calls);

        // Verify results
        assertTrue(
            SmartWallet(payable(testAccount)).hasOwner(newOwnerKeyHash),
            "New owner should be added"
        );
        (, , , bool adminStatus, ) = SmartWallet(payable(testAccount))
            .getOwnerSettings(aliceKeyHash);
        assertTrue(adminStatus, "Alice should be admin");
    }

    // ==========================================
    // Chainless Execution - BatchedCall Tests
    // ==========================================

    /**
     * @notice Test chainless BatchedCall execution for addOwner
     */
    function test_chainless_batchedCall_addOwner_success() external {
        BatchedCall memory batchedCall = _createChainlessAddOwnerBatchedCall();

        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            address(_smartWallet)
        );
        bytes32 chainlessHash = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(dataHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, chainlessHash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        // Execute should succeed
        SmartWallet(payable(testAccount)).executeWithRelayer(
            batchedCall,
            validatorData
        );

        assertTrue(
            SmartWallet(payable(testAccount)).hasOwner(bobKeyHash),
            "Bob should be added as owner"
        );
    }

    /**
     * @notice Test chainless BatchedCall execution fails for unsupported selector
     */
    function test_chainless_batchedCall_fails_for_unsupported_selector()
        external
    {
        BatchedCall memory batchedCall = _createChainlessTransferBatchedCall();

        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            address(_smartWallet)
        );
        bytes32 chainlessHash = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(dataHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, chainlessHash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        // Should revert with InvalidNonceKey
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        SmartWallet(payable(testAccount)).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    /**
     * @notice Test chainless BatchedCall with mixed selectors (should fail)
     */
    function test_chainless_batchedCall_mixed_selectors_fails() external {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            address(_smartWallet)
        );
        bytes32 chainlessHash = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(dataHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, chainlessHash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        // Should revert because second call is not chainless-compatible
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        SmartWallet(payable(testAccount)).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    /**
     * @notice Test chainless execution with short calldata fails
     */
    function test_chainless_execution_short_calldata_fails() external {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: "0x01" // Too short, less than 4 bytes
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
            expiry: uint48(block.timestamp + 1 hours)
        });

        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            address(_smartWallet)
        );
        bytes32 chainlessHash = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(dataHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, chainlessHash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidNonceKey.selector,
                Static.CHAIN_LESS_NONCE_KEY
            )
        );
        SmartWallet(payable(testAccount)).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    // ====================
    // Cross-chain Scenarios
    // ====================

    /**
     * @notice Test that signature created on one chain works on another
     */
    function test_cross_chain_signature_compatibility() external {
        BatchedCall memory batchedCall = _createChainlessAddOwnerBatchedCall();

        // Create signature on "Ethereum mainnet" (chainId 1)
        vm.chainId(1);
        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            address(_smartWallet)
        );
        bytes32 chainlessHash = SmartWallet(payable(testAccount))
            .hashTypedDataSansChainId(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, chainlessHash);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, r, s, v);

        // Execute on "Arbitrum" (chainId 42161)
        vm.chainId(42161);
        SmartWallet(payable(testAccount)).executeWithRelayer(
            batchedCall,
            validatorData
        );

        // Verify execution succeeded
        assertTrue(
            SmartWallet(payable(testAccount)).hasOwner(bobKeyHash),
            "Cross-chain execution should succeed"
        );

        // Reset chain ID
        vm.chainId(31337);
    }

    // ===============
    // Helper Functions
    // ===============

    function _createChainlessAddOwnerUserOp()
        internal
        view
        returns (PackedUserOperation memory)
    {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
                initCode: "",
                callData: abi.encodeWithSelector(
                    ISmartWallet.execute.selector,
                    calls
                ),
                accountGasLimits: bytes32((uint256(2000000) << 128) | 100000),
                preVerificationGas: 21000,
                gasFees: bytes32((uint256(1000000000) << 128) | 1000000000),
                paymasterAndData: "",
                signature: ""
            });
    }

    function _createChainlessUpdateOwnerUserOp()
        internal
        view
        returns (PackedUserOperation memory)
    {
        uint256 adminSettings = SmartWallet(payable(testAccount)).packSettings(
            true,
            0,
            address(0)
        );

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator),
                adminSettings
            )
        });

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
                initCode: "",
                callData: abi.encodeWithSelector(
                    ISmartWallet.execute.selector,
                    calls
                ),
                accountGasLimits: bytes32((uint256(2000000) << 128) | 100000),
                preVerificationGas: 21000,
                gasFees: bytes32((uint256(1000000000) << 128) | 1000000000),
                paymasterAndData: "",
                signature: ""
            });
    }

    function _createChainlessRemoveOwnerUserOp(
        bytes32 keyHash
    ) internal view returns (PackedUserOperation memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeOwner.selector,
                keyHash
            )
        });

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
                initCode: "",
                callData: abi.encodeWithSelector(
                    ISmartWallet.execute.selector,
                    calls
                ),
                accountGasLimits: bytes32((uint256(2000000) << 128) | 100000),
                preVerificationGas: 21000,
                gasFees: bytes32((uint256(1000000000) << 128) | 1000000000),
                paymasterAndData: "",
                signature: ""
            });
    }

    function _createChainlessTransferUserOp()
        internal
        view
        returns (PackedUserOperation memory)
    {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
                initCode: "",
                callData: abi.encodeWithSelector(
                    ISmartWallet.execute.selector,
                    calls
                ),
                accountGasLimits: bytes32((uint256(2000000) << 128) | 100000),
                preVerificationGas: 21000,
                gasFees: bytes32((uint256(1000000000) << 128) | 1000000000),
                paymasterAndData: "",
                signature: ""
            });
    }

    function _createChainlessAddOwnerBatchedCall()
        internal
        view
        returns (BatchedCall memory)
    {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        return
            BatchedCall({
                calls: calls,
                nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
                expiry: uint48(block.timestamp + 1 hours)
            });
    }

    function _createChainlessTransferBatchedCall()
        internal
        view
        returns (BatchedCall memory)
    {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});

        return
            BatchedCall({
                calls: calls,
                nonce: Static.CHAIN_LESS_NONCE_KEY << 64,
                expiry: uint48(block.timestamp + 1 hours)
            });
    }

    function _executeUserOpThroughEntryPoint(
        PackedUserOperation memory userOp,
        bytes32 userOpHash
    ) internal returns (uint256) {
        vm.prank(ENTRYPOINT_ADDRESS);
        return
            IERC4337Account(testAccount).validateUserOp(userOp, userOpHash, 0);
    }

    function _addOwnerAsAdmin(bytes32 keyHash, address validator) internal {
        vm.prank(_aliceEOA);
        uint256 adminSettings = SmartWallet(payable(testAccount)).packSettings(
            true,
            0,
            address(0)
        );
        SmartWallet(payable(testAccount)).addOwner(
            keyHash,
            validator,
            adminSettings
        );
    }
}
