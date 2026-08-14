// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DecodeLib} from "src/libraries/DecodeLib.sol";
import {Call} from "src/Types.sol";

/// @title DecodeLibHarness
/// @notice Helper contract to expose DecodeLib functions for testing
contract DecodeLibHarness {
    /// @notice Decode `Call[]` from function params (WITHOUT selector)
    /// @dev Expects input like `bytes params = callData[4:]` or `abi.encode(calls)`
    function decodeCalls(
        bytes calldata callData
    ) external pure returns (Call[] memory result) {
        return DecodeLib.decodeCalls(callData);
    }

    function decodeCallsWithTail(
        bytes calldata callData,
        bytes calldata
    ) external pure returns (Call[] memory result) {
        return DecodeLib.decodeCalls(callData);
    }

    /// @notice Decode signature components (pubKeyHash and validUntil) from signature bytes
    /// @dev Signature format: pubKeyHash (32 bytes) + validUntil (6 bytes) + actual signature data
    /// @param signature The signature bytes containing pubKeyHash and validUntil
    /// @return pubKeyHash The extracted public key hash (first 32 bytes)
    /// @return validUntil The extracted validity timestamp (bytes 32-38 as uint48)
    function decodeSignatureComponents(
        bytes calldata signature
    ) external pure returns (bytes32 pubKeyHash, uint48 validUntil) {
        return DecodeLib.decodeSignatureComponents(signature);
    }
}

contract DecodeLibTest is Test {
    DecodeLibHarness internal harness;

    function setUp() public {
        harness = new DecodeLibHarness();
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeCalls — Normal Path
    // ═══════════════════════════════════════════════════════════════

    function test_DecodeCalls_EmptyArray_Success() public {
        bytes memory callData = abi.encode(new Call[](0));
        Call[] memory result = harness.decodeCalls(callData);
        assertEq(result.length, 0);
    }

    function test_DecodeCalls_SingleCall_NoData_Success() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(0x1234), value: 1 ether, data: ""});
        bytes memory callData = abi.encode(calls);

        Call[] memory result = harness.decodeCalls(callData);

        assertEq(result.length, 1);
        assertEq(result[0].target, address(0x1234));
        assertEq(result[0].value, 1 ether);
        assertEq(result[0].data, "");
    }

    function test_DecodeCalls_SingleCall_WithData_Success() public {
        bytes memory innerData = abi.encodeWithSelector(
            bytes4(0xaabbccdd),
            uint256(42)
        );
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(0xABCD), value: 0, data: innerData});
        bytes memory callData = abi.encode(calls);

        Call[] memory result = harness.decodeCalls(callData);

        assertEq(result.length, 1);
        assertEq(result[0].target, address(0xABCD));
        assertEq(result[0].value, 0);
        assertEq(result[0].data, innerData);
    }

    function test_DecodeCalls_MultipleCalls_Success() public {
        bytes memory extraData = abi.encode(uint256(99));
        Call[] memory calls = new Call[](3);
        calls[0] = Call({target: address(0x1111), value: 1 ether, data: ""});
        calls[1] = Call({
            target: address(0x2222),
            value: 0,
            data: hex"deadbeef"
        });
        calls[2] = Call({
            target: address(0x3333),
            value: 0.5 ether,
            data: extraData
        });
        bytes memory callData = abi.encode(calls);

        Call[] memory result = harness.decodeCalls(callData);

        assertEq(result.length, 3);
        assertEq(result[0].target, address(0x1111));
        assertEq(result[0].value, 1 ether);
        assertEq(result[0].data, "");
        assertEq(result[1].target, address(0x2222));
        assertEq(result[1].value, 0);
        assertEq(result[1].data, hex"deadbeef");
        assertEq(result[2].target, address(0x3333));
        assertEq(result[2].value, 0.5 ether);
        assertEq(result[2].data, extraData);
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeCalls — Minimal Valid Encoding
    // ═══════════════════════════════════════════════════════════════

    /// @dev Minimal Valid Encoding: 64 bytes, relOffset=32, length=0
    ///      This is consistent with abi.encode(new Call[](0)) format
    function test_DecodeCalls_MinimalValidEncoding_EmptyArray_Success() public {
        bytes memory callData = abi.encodePacked(
            bytes32(uint256(32)), // relOffset = 32 (standard ABI offset)
            bytes32(uint256(0)) // length = 0 (empty array)
        );
        assertEq(callData.length, 64);

        Call[] memory result = harness.decodeCalls(callData);
        assertEq(result.length, 0);
    }

    function test_RevertWhen_DecodeCalls_NestedOffsetEscapesParentSlice() public {
        bytes memory payload = new bytes(548);
        bytes4 selector = harness.decodeCallsWithTail.selector;

        assembly ("memory-safe") {
            let p := add(payload, 0x20)
            mstore(p, selector)
            // Two dynamic argument offsets, relative to byte 4.
            mstore(add(p, 0x04), 0x40)
            mstore(add(p, 0x24), 0x200)
            // callData.length = 64, callData = [array offset=32, length=1].
            mstore(add(p, 0x44), 0x40)
            mstore(add(p, 0x64), 0x20)
            mstore(add(p, 0x84), 0x01)
            // Forged Call encoding after the end of callData.
            mstore(add(p, 0xa4), 0x40)
            mstore(add(p, 0xe4), 0x000000000000000000000000000000000000bEEF)
            mstore(add(p, 0x104), 7)
            mstore(add(p, 0x124), 0x60)
            mstore(add(p, 0x144), 4)
            mstore(add(p, 0x164), shl(224, 0xdeadbeef))
            // Empty second bytes argument keeps the outer calldata valid.
            mstore(add(p, 0x204), 0)
        }

        (bool ok, ) = address(harness).call(payload);
        assertFalse(ok);
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeCalls — Length Validation: callData.length < 32
    // ═══════════════════════════════════════════════════════════════

    function test_RevertWhen_DecodeCalls_Empty() public {
        vm.expectRevert();
        harness.decodeCalls("");
    }

    function test_RevertWhen_DecodeCalls_16Bytes() public {
        vm.expectRevert();
        harness.decodeCalls(new bytes(16));
    }

    function test_RevertWhen_DecodeCalls_Exactly31Bytes() public {
        vm.expectRevert();
        harness.decodeCalls(new bytes(31));
    }

    /// @dev The ABI decoder rejects an offset whose array length word is missing.
    function test_RevertWhen_DecodeCalls_Exactly32Bytes_OffsetTooLarge()
        public
    {
        bytes memory callData = abi.encodePacked(bytes32(uint256(32)));
        assertEq(callData.length, 32);
        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeCalls — Offset Out of Bounds
    // ═══════════════════════════════════════════════════════════════

    function test_RevertWhen_DecodeCalls_OffsetOutOfBounds() public {
        // callData = 64 bytes, relOffset = 1000 (outside callData)
        bytes memory callData = abi.encodePacked(
            bytes32(uint256(1000)),
            bytes32(uint256(0))
        );
        assertEq(callData.length, 64);
        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    function test_RevertWhen_DecodeCalls_OffsetExactlyOneBeyondBound() public {
        // relOffset = 33 cannot address a complete array length word.
        bytes memory callData = abi.encodePacked(
            bytes32(uint256(33)),
            bytes32(uint256(0))
        );
        assertEq(callData.length, 64);
        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeCalls — ABI Decoder Overflow Validation
    // The standard ABI decoder rejects oversized offsets without manual arithmetic.
    // ═══════════════════════════════════════════════════════════════

    function test_RevertWhen_DecodeCalls_OverflowAttack_MaxOffset() public {
        // relOffset = type(uint256).max
        bytes memory callData = abi.encodePacked(
            bytes32(type(uint256).max),
            bytes32(uint256(0))
        );
        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    /// @dev Exact Vulnerability Trigger Point: add(max-31, 32) = 0, old check gt(0, 64) = false → bypass
    function test_RevertWhen_DecodeCalls_OverflowAttack_ExactBypassPoint()
        public
    {
        uint256 R = type(uint256).max - 31;
        // Manual add(R, 32) would wrap to zero; the ABI decoder must still reject it.
        bytes memory callData = abi.encodePacked(
            bytes32(R),
            bytes32(uint256(0))
        );
        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    function test_RevertWhen_DecodeCalls_OverflowAttack_OverflowToPositive()
        public
    {
        // relOffset = type(uint256).max - 15
        // add(type(uint256).max - 15, 32) = 16 (overflows, wraps to positive)
        // Manual add(offset, 32) would wrap to 16; the ABI decoder must reject it.
        bytes memory callData = abi.encodePacked(
            bytes32(type(uint256).max - 15),
            bytes32(uint256(0))
        );
        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeSignatureComponents — Normal Path
    // ═══════════════════════════════════════════════════════════════

    function test_DecodeSignatureComponents_Exactly38Bytes_Success() public {
        bytes32 expectedHash = keccak256("testKey");
        uint48 expectedUntil = 9_999_999;

        // abi.encodePacked: bytes32(32 bytes) + uint48(6 bytes) = 38 bytes
        bytes memory sig = abi.encodePacked(
            expectedHash,
            uint48(expectedUntil)
        );
        assertEq(sig.length, 38);

        (bytes32 pubKeyHash, uint48 validUntil) = harness
            .decodeSignatureComponents(sig);
        assertEq(pubKeyHash, expectedHash);
        assertEq(validUntil, expectedUntil);
    }

    function test_DecodeSignatureComponents_WithEcdsaSignatureAppended_Success()
        public
    {
        bytes32 expectedHash = bytes32(uint256(0xDEAD));
        uint48 expectedUntil = uint48(block.timestamp + 3600);

        // Format: pubKeyHash(32) + validUntil(6) + ECDSA signature(65) = 103 bytes
        bytes memory sig = abi.encodePacked(
            expectedHash,
            uint48(expectedUntil),
            new bytes(65)
        );
        assertEq(sig.length, 103);

        (bytes32 pubKeyHash, uint48 validUntil) = harness
            .decodeSignatureComponents(sig);
        assertEq(pubKeyHash, expectedHash);
        assertEq(validUntil, expectedUntil);
    }

    function test_DecodeSignatureComponents_ZeroValidUntil_Success() public {
        bytes32 expectedHash = keccak256("alice");
        uint48 expectedUntil = 0; // Never expires

        bytes memory sig = abi.encodePacked(
            expectedHash,
            uint48(expectedUntil),
            new bytes(65)
        );

        (, uint48 validUntil) = harness.decodeSignatureComponents(sig);
        assertEq(validUntil, 0);
    }

    function test_DecodeSignatureComponents_MaxValidUntil_Success() public {
        bytes32 expectedHash = keccak256("maxExpiry");
        uint48 expectedUntil = type(uint48).max;

        bytes memory sig = abi.encodePacked(
            expectedHash,
            uint48(expectedUntil),
            new bytes(65)
        );

        (bytes32 pubKeyHash, uint48 validUntil) = harness
            .decodeSignatureComponents(sig);
        assertEq(pubKeyHash, expectedHash);
        assertEq(validUntil, type(uint48).max);
    }

    // ═══════════════════════════════════════════════════════════════
    // decodeSignatureComponents — Boundary Check (Solidity builtin slice out of bounds protection)
    // ═══════════════════════════════════════════════════════════════

    function test_RevertWhen_DecodeSignatureComponents_Empty() public {
        vm.expectRevert();
        harness.decodeSignatureComponents("");
    }

    function test_RevertWhen_DecodeSignatureComponents_LessThan32Bytes()
        public
    {
        // First slice signature[:32] out of bounds
        vm.expectRevert();
        harness.decodeSignatureComponents(new bytes(31));
    }

    function test_RevertWhen_DecodeSignatureComponents_Exactly32Bytes() public {
        // First slice signature[:32] succeeds, second slice signature[32:38] out of bounds
        vm.expectRevert();
        harness.decodeSignatureComponents(new bytes(32));
    }

    function test_RevertWhen_DecodeSignatureComponents_Exactly37Bytes() public {
        // Less than minimum valid length by 1 byte
        vm.expectRevert();
        harness.decodeSignatureComponents(new bytes(37));
    }

    // ═══════════════════════════════════════════════════════════════
    // Fuzz Tests
    // ═══════════════════════════════════════════════════════════════

    /// @dev Any input shorter than 32 bytes should be rejected by the ABI decoder
    function testFuzz_DecodeCalls_ShortInputReverts(bytes memory input) public {
        vm.assume(input.length < 32);
        vm.expectRevert();
        harness.decodeCalls(input);
    }

    /// @dev For 64 bytes of callData, an offset beyond the encoded array must revert
    function testFuzz_DecodeCalls_OverflowProtection(
        uint256 maliciousOffset
    ) public {
        vm.assume(maliciousOffset > 32); // Out of valid range [0, 32]

        bytes memory callData = abi.encodePacked(
            bytes32(maliciousOffset),
            bytes32(uint256(0))
        );
        assertEq(callData.length, 64);

        vm.expectRevert();
        harness.decodeCalls(callData);
    }

    /// @dev abi.encode(calls) generated callData should be able to roundtrip decode
    function testFuzz_DecodeCalls_ValidCallsRoundtrip(
        address target,
        uint256 value,
        bytes memory data
    ) public {
        vm.assume(data.length <= 1024); // Avoid too large calldata causing OOG

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: target, value: value, data: data});
        bytes memory callData = abi.encode(calls);

        Call[] memory result = harness.decodeCalls(callData);

        assertEq(result.length, 1);
        assertEq(result[0].target, target);
        assertEq(result[0].value, value);
        assertEq(keccak256(result[0].data), keccak256(data));
    }

    /// @dev Any valid signature format should be able to correctly parse first 38 bytes
    function testFuzz_DecodeSignatureComponents_ValidInputs(
        bytes32 pubKeyHash,
        uint48 validUntil,
        bytes memory extraData
    ) public {
        // Format: pubKeyHash(32) + validUntil(6) + any suffix
        bytes memory sig = abi.encodePacked(
            pubKeyHash,
            uint48(validUntil),
            extraData
        );

        (bytes32 decodedHash, uint48 decodedUntil) = harness
            .decodeSignatureComponents(sig);

        assertEq(decodedHash, pubKeyHash);
        assertEq(decodedUntil, validUntil);
    }
}
