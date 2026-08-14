// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Call} from "src/Types.sol";
import {CallLib} from "src/libraries/CallLib.sol";

contract CallLibTest is Test {
    bytes32 private constant CALL_TYPEHASH =
        keccak256("Call(address target,uint256 value,bytes data)");

    function test_HashEmptyArray_MatchesLegacyEncoding() public pure {
        Call[] memory calls = new Call[](0);
        assertEq(CallLib.hash(calls), keccak256(""));
    }

    function test_HashMultipleCalls_MatchesLegacyEncoding() public pure {
        Call[] memory calls = new Call[](3);
        calls[0] = Call(address(0x1111), 1 ether, "");
        calls[1] = Call(address(0x2222), 0, hex"deadbeef");
        calls[2] = Call(address(0x3333), 7, abi.encode(uint256(42)));

        assertEq(CallLib.hash(calls), _legacyHash(calls));
    }

    function testFuzz_HashSingleCall_MatchesReference(
        address target,
        uint256 value,
        bytes memory data
    ) public pure {
        vm.assume(data.length <= 4096);
        Call memory call = Call(target, value, data);

        bytes32 expected = keccak256(
            abi.encode(CALL_TYPEHASH, target, value, keccak256(data))
        );
        assertEq(CallLib.hash(call), expected);
    }

    function testFuzz_HashArray_MatchesLegacyEncoding(
        address target,
        uint256 value,
        bytes memory data,
        uint8 lengthSeed
    ) public pure {
        vm.assume(data.length <= 1024);
        uint256 length = bound(lengthSeed, 0, 16);
        Call[] memory calls = new Call[](length);

        for (uint256 i; i < length; ++i) {
            uint256 callValue;
            unchecked {
                callValue = value + i;
            }
            calls[i] = Call(
                address(uint160(uint256(keccak256(abi.encode(target, i))))),
                callValue,
                abi.encodePacked(data, i)
            );
        }

        assertEq(CallLib.hash(calls), _legacyHash(calls));
    }

    function _legacyHash(Call[] memory calls) private pure returns (bytes32) {
        bytes memory encoded;
        for (uint256 i; i < calls.length; ++i) {
            encoded = abi.encodePacked(
                encoded,
                keccak256(
                    abi.encode(
                        CALL_TYPEHASH,
                        calls[i].target,
                        calls[i].value,
                        keccak256(calls[i].data)
                    )
                )
            );
        }
        return keccak256(encoded);
    }
}
