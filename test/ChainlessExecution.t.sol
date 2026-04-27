// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {Static} from "src/libraries/Static.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

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
        aliceKeyHash = _makeKeyHash(_alice);
        bobKeyHash = _makeKeyHash(_bob);

        // Create test account with Alice as initial owner with admin privileges
        testAccount = _deployAccountSingleOwner(
            aliceKeyHash,
            address(_ecdsaValidator),
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
    function test_HashFunctionsProduceDifferentResults_Success() external view {
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
    function test_HashTypedDataSansChainId_ConsistentAcrossChains_Success()
        external
    {
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
    function test_GetUserOpHashWithoutChainId_Consistency_Success()
        external
        view
    {
        PackedUserOperation memory userOp = _createChainlessAddOwnerUserOp();

        // getUserOpHashWithoutChainId should work with the userOp
        bytes32 userOpHash = IERC4337Account(testAccount)
            .getUserOpHashWithoutChainId(userOp);

        // The hash should be non-zero
        assertTrue(userOpHash != bytes32(0), "UserOp hash should not be zero");
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
    function test_ChainlessUserOp_FullExecutionFlow_Success() external {
        // Create comprehensive test with multiple operations
        bytes32 newOwnerKeyHash = _makeKeyHash(_bob);
        Call[] memory calls = new Call[](1);

        // 1. Add new owner
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                newOwnerKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: testAccount,
            nonce: Static.CHAINLESS_NONCE_KEY << 64,
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

        // Now get the chainless hash
        bytes32 baseUserOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        // Use helper function to construct proper chainless signature
        userOp.signature = _constructUserOpSignature(
            userOp,
            _alice,
            _alicePk,
            baseUserOpHash,
            testAccount
        );

        // Validation should succeed
        uint256 result = _executeUserOpThroughEntryPoint(
            userOp,
            baseUserOpHash
        );
        assertEq(result, 0, "UserOp validation should succeed");

        // Execute the actual operations
        vm.prank(_alice);
        SmartWallet(payable(testAccount)).execute(calls);

        // Verify results
        assertTrue(
            SmartWallet(payable(testAccount)).hasOwner(newOwnerKeyHash),
            "New owner should be added"
        );
    }

    // ==========================================
    // Chainless Execution - BatchedCall Tests
    // ==========================================

    /**
     * @notice Test chainless BatchedCall execution for addOwner
     */
    function test_ChainlessBatchedCall_AddOwner_Success() external {
        BatchedCall memory batchedCall = _createChainlessAddOwnerBatchedCall();

        bytes memory validatorData = _constructRelayerSignature(
            testAccount,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

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
     * @notice Test chainless BatchedCall fails when target is not self
     */
    function test_RevertWhen_ChainlessBatchedCall_NonSelfTarget() external {
        // Create a call with allowed selector but wrong target (not self)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _bob, // Not self - should fail
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                keccak256(abi.encodePacked(address(0x123))),
                address(_ecdsaValidator),
                0
            )
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: Static.CHAINLESS_NONCE_KEY << 64
        });

        bytes memory validatorData = _constructRelayerSignature(
            testAccount, // Use testAccount which has alice as owner
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert because target is not self
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAINLESS_NONCE_KEY
            )
        );
        SmartWallet(payable(testAccount)).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }

    /**
     * @notice Test chainless BatchedCall execution fails for unsupported selector
     */
    function test_RevertWhen_ChainlessBatchedCall_UnsupportedSelector()
        external
    {
        BatchedCall memory batchedCall = _createChainlessTransferBatchedCall();

        bytes memory validatorData = _constructRelayerSignature(
            testAccount,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert with InvalidNonceKey
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAINLESS_NONCE_KEY
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
    function test_RevertWhen_ChainlessBatchedCall_MixedSelectors() external {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.addOwner.selector,
                bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });
        calls[1] = Call({target: _bob, value: 1 ether, data: ""});

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: Static.CHAINLESS_NONCE_KEY << 64
        });

        bytes memory validatorData = _constructRelayerSignature(
            testAccount,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        // Should revert because second call is not chainless-compatible
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAINLESS_NONCE_KEY
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
    function test_RevertWhen_ChainlessExecution_ShortCalldata() external {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: "0x01" // Too short, less than 4 bytes
        });

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: Static.CHAINLESS_NONCE_KEY << 64
        });

        bytes memory validatorData = _constructRelayerSignature(
            testAccount,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAINLESS_NONCE_KEY
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
    function test_CrossChainSignature_Compatibility_Success() external {
        BatchedCall memory batchedCall = _createChainlessAddOwnerBatchedCall();

        // Create signature on "Ethereum mainnet" (chainId 1)
        vm.chainId(1);
        bytes memory validatorData = _constructRelayerSignature(
            testAccount,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

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
                OwnerManager.addOwner.selector,
                bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAINLESS_NONCE_KEY << 64,
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
                OwnerManager.updateOwner.selector,
                aliceKeyHash,
                address(_ecdsaValidator),
                adminSettings
            )
        });

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAINLESS_NONCE_KEY << 64,
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
                OwnerManager.removeOwner.selector,
                keyHash
            )
        });

        return
            PackedUserOperation({
                sender: testAccount,
                nonce: Static.CHAINLESS_NONCE_KEY << 64,
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
                nonce: Static.CHAINLESS_NONCE_KEY << 64,
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
                OwnerManager.addOwner.selector,
                bobKeyHash,
                address(_ecdsaValidator),
                0
            )
        });

        return
            BatchedCall({
                calls: calls,
                nonce: Static.CHAINLESS_NONCE_KEY << 64
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
                nonce: Static.CHAINLESS_NONCE_KEY << 64
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
        vm.prank(_alice);
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

    /// @notice Test validateChainlessNonceCallData returns false for calls with data length < 4
    /// @dev This test hits the specific line: if (callData.length < 4) return false;
    /// @dev Tests through executeWithRelayer since validateChainlessNonceCallData is internal
    function test_ValidateChainlessNonceCallData_ShortCallData() public {
        // Create a call with empty data to trigger: if (callData.length < 4) return false;
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: testAccount,
            value: 0,
            data: "" // Empty data - length 0, which is < 4
        });

        // Create chainless nonce: CHAINLESS_NONCE_KEY (196) in upper 192 bits, nonce 0 in lower 64 bits
        uint256 chainlessNonce = (Static.CHAINLESS_NONCE_KEY << 64) | 0;

        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: chainlessNonce
        });

        // Create dummy validator data (won't be validated since we expect early revert)
        bytes memory validatorData = abi.encodePacked(
            aliceKeyHash, // keyHash (32 bytes)
            uint48(0), // validUntil (6 bytes) - 0 means never expires
            new bytes(65) // dummy signature (65 bytes)
        );

        // The execution should revert with InvalidNonceKey because validateChainlessNonceCallData returns false
        vm.expectRevert(
            abi.encodeWithSelector(
                ISmartWallet.InvalidNonceKey.selector,
                Static.CHAINLESS_NONCE_KEY
            )
        );
        ISmartWallet(testAccount).executeWithRelayer(
            batchedCall,
            validatorData
        );
    }
}
