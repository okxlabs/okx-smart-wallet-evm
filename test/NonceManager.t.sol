// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {NonceManager} from "src/NonceManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {Static} from "src/libraries/Static.sol";

/**
 * @title TestableNonceManager
 * @notice Test helper contract that exposes NonceManager's internal methods
 */
contract TestableNonceManager is NonceManager {
    // Wrapper to expose internal method for testing
    function testValidateAndUpdateNonce(
        uint256 packedNonce
    ) external returns (bool) {
        return validateAndUpdateNonce(packedNonce);
    }

    function exposedValidateAndUpdateChainlessQueue(
        uint256 packedNonce
    ) external returns (bool) {
        return _validateAndUpdateChainlessQueue(packedNonce);
    }
}

contract NonceManagerTest is Test {
    uint16 private constant CHAINLESS_OPERATION_TYPE_1 = 1;
    uint16 private constant CHAINLESS_OPERATION_TYPE_2 = 2;

    TestableNonceManager public nonceManager;

    // Test events
    event NonceConsumed(uint192 key, uint64 nonce);
    event ChainlessQueueInvalidated(
        uint16 indexed operationType,
        uint16 indexed queueId
    );

    function setUp() public {
        nonceManager = new TestableNonceManager();
    }

    // ============ Basic Functionality Tests ============

    function test_GetNonce_ReturnsZeroForNewKey() public view {
        uint192 key = uint192(12345);
        uint64 nonce = nonceManager.getNonce(key);
        assertEq(nonce, 0);
    }

    function test_GetNonce_ReturnsCurrentValue() public {
        uint192 key = uint192(1);
        uint256 packedNonce = (uint256(key) << 64) | uint256(0);

        // Update nonce once
        nonceManager.testValidateAndUpdateNonce(packedNonce);

        // Check it returns 1
        assertEq(nonceManager.getNonce(key), 1);
    }

    // ============ Chainless Queue Invalidation Tests ============

    function test_ChainlessQueue_QueueZeroCanBeUsedOnce() public {
        uint16 nextQueueId = nonceManager.getChainlessQueueState(
            CHAINLESS_OPERATION_TYPE_1
        );
        assertEq(nextQueueId, 0);

        uint256 packedNonce = _chainlessNonce(
            CHAINLESS_OPERATION_TYPE_1,
            0,
            0
        );

        vm.expectEmit(true, true, true, true);
        emit ChainlessQueueInvalidated(
            CHAINLESS_OPERATION_TYPE_1,
            0
        );
        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(packedNonce)
        );

        nextQueueId = nonceManager.getChainlessQueueState(
            CHAINLESS_OPERATION_TYPE_1
        );
        assertEq(nextQueueId, 1);
        assertFalse(
            nonceManager.exposedValidateAndUpdateChainlessQueue(packedNonce)
        );
    }

    function test_ChainlessQueue_InvalidatesSameAndLowerQueueIds() public {
        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 10, 0)
            )
        );

        assertFalse(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 9, 0)
            )
        );
        assertFalse(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 10, 1)
            )
        );
        uint16 nextQueueId = nonceManager.getChainlessQueueState(
            CHAINLESS_OPERATION_TYPE_1
        );
        assertEq(nextQueueId, 11);

        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 11, 0)
            )
        );
    }

    function test_ChainlessQueue_OperationTypesAreIndependent() public {
        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 20, 0)
            )
        );

        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_2, 1, 0)
            )
        );
        uint16 addOwnerNextQueueId = nonceManager.getChainlessQueueState(
            CHAINLESS_OPERATION_TYPE_1
        );
        uint16 upgradeNextQueueId = nonceManager.getChainlessQueueState(
            CHAINLESS_OPERATION_TYPE_2
        );
        assertEq(addOwnerNextQueueId, 21);
        assertEq(upgradeNextQueueId, 2);
    }

    function test_ChainlessQueue_MaxUsableQueueThenMaxIsRejected() public {
        uint16 maxUsableQueueId = type(uint16).max - 1;
        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(
                    CHAINLESS_OPERATION_TYPE_1,
                    maxUsableQueueId,
                    0
                )
            )
        );
        assertEq(
            nonceManager.getChainlessQueueState(
                CHAINLESS_OPERATION_TYPE_1
            ),
            type(uint16).max
        );

        assertFalse(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(
                    CHAINLESS_OPERATION_TYPE_1,
                    type(uint16).max,
                    0
                )
            )
        );
        assertEq(
            nonceManager.getChainlessQueueState(
                CHAINLESS_OPERATION_TYPE_1
            ),
            type(uint16).max
        );
    }

    function test_ChainlessQueue_DoesNotAffectRegularNonceKeys() public {
        assertTrue(
            nonceManager.exposedValidateAndUpdateChainlessQueue(
                _chainlessNonce(CHAINLESS_OPERATION_TYPE_1, 5, 0)
            )
        );

        assertTrue(nonceManager.testValidateAndUpdateNonce(0));
        assertEq(nonceManager.getNonce(0), 1);
    }

    function test_ValidateAndUpdateNonce_ValidNonceReturnsTrue() public {
        uint192 key = uint192(42);
        uint64 expectedNonce = 0;
        uint256 packedNonce = (uint256(key) << 64) | uint256(expectedNonce);

        bool result = nonceManager.testValidateAndUpdateNonce(packedNonce);
        assertTrue(result);
    }

    function test_ValidateAndUpdateNonce_InvalidNonceReturnsFalse() public {
        uint192 key = uint192(42);
        uint64 wrongNonce = 1; // Expected is 0, but providing 1
        uint256 packedNonce = (uint256(key) << 64) | uint256(wrongNonce);

        bool result = nonceManager.testValidateAndUpdateNonce(packedNonce);
        assertFalse(result);
    }

    function test_ValidateAndUpdateNonce_IncrementsNonce() public {
        uint192 key = uint192(123);
        uint256 packedNonce = (uint256(key) << 64) | uint256(0);

        assertEq(nonceManager.getNonce(key), 0);

        nonceManager.testValidateAndUpdateNonce(packedNonce);

        assertEq(nonceManager.getNonce(key), 1);
    }

    function test_ValidateAndUpdateNonce_EmitsEvent() public {
        uint192 key = uint192(999);
        uint64 expectedNonce = 0;
        uint256 packedNonce = (uint256(key) << 64) | uint256(expectedNonce);

        vm.expectEmit(true, true, true, true);
        emit NonceConsumed(key, expectedNonce);

        nonceManager.testValidateAndUpdateNonce(packedNonce);
    }

    // ============ Multiple Nonce Key Tests ============

    function test_ValidateAndUpdateNonce_DifferentKeysIndependentNonces()
        public
    {
        uint192 key1 = uint192(100);
        uint192 key2 = uint192(200);

        // Both should start at 0
        assertEq(nonceManager.getNonce(key1), 0);
        assertEq(nonceManager.getNonce(key2), 0);

        // Update key1 twice
        uint256 packedNonce1First = (uint256(key1) << 64) | uint256(0);
        uint256 packedNonce1Second = (uint256(key1) << 64) | uint256(1);

        nonceManager.testValidateAndUpdateNonce(packedNonce1First);
        nonceManager.testValidateAndUpdateNonce(packedNonce1Second);

        // Update key2 once
        uint256 packedNonce2First = (uint256(key2) << 64) | uint256(0);
        nonceManager.testValidateAndUpdateNonce(packedNonce2First);

        // Check final states
        assertEq(nonceManager.getNonce(key1), 2);
        assertEq(nonceManager.getNonce(key2), 1);
    }

    function test_ValidateAndUpdateNonce_ParallelManagement() public {
        uint192[] memory keys = new uint192[](5);
        keys[0] = uint192(1);
        keys[1] = uint192(1000);
        keys[2] = uint192(2 ** 64);
        keys[3] = uint192(2 ** 128);
        keys[4] = uint192(2 ** 191); // Near max uint192

        // Update each key different number of times
        for (uint256 i = 0; i < keys.length; i++) {
            for (uint256 j = 0; j <= i; j++) {
                uint256 packedNonce = (uint256(keys[i]) << 64) | uint256(j);
                bool result = nonceManager.testValidateAndUpdateNonce(
                    packedNonce
                );
                assertTrue(result);
            }
            assertEq(nonceManager.getNonce(keys[i]), i + 1);
        }
    }

    // ============ Boundary Value Tests ============

    function test_ValidateAndUpdateNonce_KeyBoundaries() public {
        uint192 minKey = uint192(0);
        uint192 maxKey = type(uint192).max;

        // Test minimum key
        uint256 packedNonceMin = (uint256(minKey) << 64) | uint256(0);
        assertTrue(nonceManager.testValidateAndUpdateNonce(packedNonceMin));
        assertEq(nonceManager.getNonce(minKey), 1);

        // Test maximum key
        uint256 packedNonceMax = (uint256(maxKey) << 64) | uint256(0);
        assertTrue(nonceManager.testValidateAndUpdateNonce(packedNonceMax));
        assertEq(nonceManager.getNonce(maxKey), 1);
    }

    function test_ValidateAndUpdateNonce_OverflowBehavior() public pure {
        // Test the theoretical overflow case
        // Note: In practice, reaching uint64 max would require enormous gas
        // But we can test the mathematical behavior

        uint64 maxNonce = type(uint64).max;

        // If we somehow had max nonce, the next increment should overflow to 0
        // This is acceptable behavior in the context of this contract
        // as it's practically impossible to reach in real usage

        // We test that the unchecked increment works as expected
        uint64 testValue = maxNonce;
        unchecked {
            testValue++;
        }
        assertEq(testValue, 0); // Overflow to 0
    }

    // ============ Packed Nonce Bit Operation Tests ============

    function test_ValidateAndUpdateNonce_PackedKeyExtraction() public pure {
        uint192 originalKey = uint192(
            0x123456789ABCDEF123456789ABCDEF123456789ABC
        );
        uint64 originalNonce = uint64(0x123456789ABCDEF0);

        uint256 packedNonce = (uint256(originalKey) << 64) |
            uint256(originalNonce);

        // Extract key (upper 192 bits)
        uint192 extractedKey = uint192(packedNonce >> 64);
        assertEq(extractedKey, originalKey);

        // Extract nonce (lower 64 bits)
        uint64 extractedNonce = uint64(packedNonce);
        assertEq(extractedNonce, originalNonce);
    }

    function test_ValidateAndUpdateNonce_PackedEdgeCases() public pure {
        // Test with key = 0, nonce = max
        uint192 key1 = uint192(0);
        uint64 nonce1 = type(uint64).max;
        uint256 packed1 = (uint256(key1) << 64) | uint256(nonce1);

        assertEq(uint192(packed1 >> 64), key1);
        assertEq(uint64(packed1), nonce1);

        // Test with key = max, nonce = 0
        uint192 key2 = type(uint192).max;
        uint64 nonce2 = uint64(0);
        uint256 packed2 = (uint256(key2) << 64) | uint256(nonce2);

        assertEq(uint192(packed2 >> 64), key2);
        assertEq(uint64(packed2), nonce2);

        // Test with both max values
        uint192 key3 = type(uint192).max;
        uint64 nonce3 = type(uint64).max;
        uint256 packed3 = (uint256(key3) << 64) | uint256(nonce3);

        assertEq(uint192(packed3 >> 64), key3);
        assertEq(uint64(packed3), nonce3);
        assertEq(packed3, type(uint256).max); // Should be max uint256
    }

    // ============ Sequential Nonce Tests ============

    function test_ValidateAndUpdateNonce_SequentialValidation() public {
        uint192 key = uint192(555);

        // Test sequential nonces 0 through 10
        for (uint64 expectedNonce = 0; expectedNonce < 10; expectedNonce++) {
            uint256 packedNonce = (uint256(key) << 64) | uint256(expectedNonce);

            vm.expectEmit(true, true, true, true);
            emit NonceConsumed(key, expectedNonce);

            bool result = nonceManager.testValidateAndUpdateNonce(packedNonce);
            assertTrue(result);
            assertEq(nonceManager.getNonce(key), expectedNonce + 1);
        }
    }

    function test_ValidateAndUpdateNonce_OutOfOrderRejected() public {
        uint192 key = uint192(777);

        // Use nonce 0 successfully
        uint256 packedNonce0 = (uint256(key) << 64) | uint256(0);
        assertTrue(nonceManager.testValidateAndUpdateNonce(packedNonce0));
        assertEq(nonceManager.getNonce(key), 1); // Should be 1 after first use

        // Try to use nonce 0 again - should fail but still increment
        bool result1 = nonceManager.testValidateAndUpdateNonce(packedNonce0);
        assertFalse(result1);
        assertEq(nonceManager.getNonce(key), 2); // Should be 2 after second call

        // Try to use nonce 2 (expecting 2, but current is now 2, so this should succeed)
        uint256 packedNonce2 = (uint256(key) << 64) | uint256(2);
        bool result2 = nonceManager.testValidateAndUpdateNonce(packedNonce2);
        assertTrue(result2); // This should succeed because current nonce is 2

        // Final nonce should be 3
        assertEq(nonceManager.getNonce(key), 3);
    }

    // ============ Event Emission Tests ============

    function test_ValidateAndUpdateNonce_EventEmissionWithDifferentKeys()
        public
    {
        uint192[] memory keys = new uint192[](3);
        keys[0] = uint192(1);
        keys[1] = uint192(2 ** 32);
        keys[2] = type(uint192).max;

        for (uint256 i = 0; i < keys.length; i++) {
            uint256 packedNonce = (uint256(keys[i]) << 64) | uint256(0);

            vm.expectEmit(true, true, true, true);
            emit NonceConsumed(keys[i], 0);

            nonceManager.testValidateAndUpdateNonce(packedNonce);
        }
    }

    function test_ValidateAndUpdateNonce_AlwaysEmitsEvent() public {
        uint192 key = uint192(888);

        // First call - valid nonce, should emit
        uint256 validPackedNonce = (uint256(key) << 64) | uint256(0);
        vm.expectEmit(true, true, true, true);
        emit NonceConsumed(key, 0);
        assertTrue(nonceManager.testValidateAndUpdateNonce(validPackedNonce));

        // Second call - invalid nonce (0 again), but should still emit with expected nonce
        uint256 invalidPackedNonce = (uint256(key) << 64) | uint256(0);
        vm.expectEmit(true, true, true, true);
        emit NonceConsumed(key, 0); // Event emits the provided nonce, not current
        assertFalse(
            nonceManager.testValidateAndUpdateNonce(invalidPackedNonce)
        );
    }

    // ============ Gas Optimization Tests ============

    function test_ValidateAndUpdateNonce_GasUsage() public {
        uint192 key = uint192(12345);
        uint256 packedNonce = (uint256(key) << 64) | uint256(0);

        uint256 gasBefore = gasleft();
        nonceManager.testValidateAndUpdateNonce(packedNonce);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (exact value may vary by compiler version)
        // This is more of a smoke test to ensure no unexpected gas costs
        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 50000); // Should be much less than this
    }

    // ============ Interface Compliance Tests ============

    function test_NonceManager_ImplementsInterface() public {
        // Test that our contract properly implements the interface
        INonceManager interfaceReference = INonceManager(address(nonceManager));

        uint192 testKey = uint192(999);
        assertEq(interfaceReference.getNonce(testKey), 0);

        // Update nonce and verify through interface
        uint256 packedNonce = (uint256(testKey) << 64) | uint256(0);
        nonceManager.testValidateAndUpdateNonce(packedNonce);

        assertEq(interfaceReference.getNonce(testKey), 1);
    }

    // ============ Cross-Contract Usage Patterns ============

    function test_NonceManager_MultipleContractsIndependent() public {
        // Simulate scenario where multiple smart wallets use different nonce keys
        TestableNonceManager wallet1 = new TestableNonceManager();
        TestableNonceManager wallet2 = new TestableNonceManager();

        uint192 key = uint192(0);
        uint256 packedNonce = (uint256(key) << 64) | uint256(0);

        // Both wallets should have independent nonce state
        assertTrue(wallet1.testValidateAndUpdateNonce(packedNonce));
        assertTrue(wallet2.testValidateAndUpdateNonce(packedNonce));

        assertEq(wallet1.getNonce(key), 1);
        assertEq(wallet2.getNonce(key), 1);
    }

    // ============ Performance and Gas Tests ============

    function test_ValidateAndUpdateNonce_GasCostComparison() public {
        uint192 key1 = uint192(0);
        uint192 key2 = type(uint192).max;

        uint256 packedNonce1 = (uint256(key1) << 64) | uint256(0);
        uint256 packedNonce2 = (uint256(key2) << 64) | uint256(0);

        uint256 gasBefore1 = gasleft();
        nonceManager.testValidateAndUpdateNonce(packedNonce1);
        uint256 gasUsed1 = gasBefore1 - gasleft();

        uint256 gasBefore2 = gasleft();
        nonceManager.testValidateAndUpdateNonce(packedNonce2);
        uint256 gasUsed2 = gasBefore2 - gasleft();

        // Gas usage may vary slightly due to storage slot differences
        // but should be within reasonable bounds (both operations are writes to empty slots)
        assertTrue(gasUsed1 > 20000); // Should use at least 20k gas for SSTORE
        assertTrue(gasUsed2 > 20000); // Should use at least 20k gas for SSTORE
        assertTrue(gasUsed1 < 50000); // Should not exceed 50k gas
        assertTrue(gasUsed2 < 50000); // Should not exceed 50k gas
    }

    function _chainlessNonce(
        uint16 operationType,
        uint16 queueId,
        uint64 sequence
    ) private pure returns (uint256) {
        return
            (Static.CHAINLESS_NONCE_KEY << 96) |
            (uint256(operationType) << 80) |
            (uint256(queueId) << 64) |
            uint256(sequence);
    }
}
