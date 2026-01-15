// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SmartWallet} from "src/SmartWallet.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {CallLib} from "src/libraries/CallLib.sol";
import {MessageSignLib} from "src/libraries/MessageSignLib.sol";
import {Call, BatchedCall} from "src/Types.sol";
import {Base, MockERC20} from "./Base.t.sol";
import {Static} from "src/libraries/Static.sol";

/// @title ERC712Test
/// @notice Tests EIP-712 and EIP-5267 implementation using Forge EIP712 codes
contract ERC712Test is Base {
    // Type hash constants - these match the exact strings used in the contract libraries
    // Even though the constants are private in the libraries, we use the same strings here for testing
    string private constant CALL_TYPEHASH =
        "Call(address target,uint256 value,bytes data)";
    string private constant BATCHED_CALL_TYPEHASH =
        "BatchedCall(Call[] calls,uint256 nonce,uint48 validUntil,address walletImpl)Call(address target,uint256 value,bytes data)";
    string private constant MESSAGE_TYPEHASH =
        "SmartWalletMessage(bytes32 hash,uint48 validUntil,address walletImpl)";
    // From OpenZeppelin EIP712.sol
    string private constant TYPE_HASH =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    // From Solady EIP712.sol
    string private constant TYPE_HASH_SANS_CHAIN_ID =
        "EIP712Domain(string name,string version,address verifyingContract)";

    // Test data
    bytes32 internal testMessageHash;
    uint48 internal testValidUntil;
    address internal testWalletImpl;
    MockERC20 internal mockToken;
    address internal recipient;
    address internal spender;

    function setUp() public override {
        super.setUp();

        // Deploy mock token and setup test addresses
        mockToken = new MockERC20();
        recipient = makeAddr("recipient");
        spender = makeAddr("spender");

        testMessageHash = keccak256("test message for EIP-712");
        testValidUntil = uint48(block.timestamp + 3600);
        testWalletImpl = address(_smartWallet);
    }

    /// @notice Test EIP-5267 domain properties
    function test_EIP712Domain() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = SmartWallet(payable(_aliceWallet)).eip712Domain();

        assertEq(name, Static.ERC712_NAMESPACE);
        assertEq(version, Static.ERC712_VERSION);
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(_aliceWallet));
        assertEq(abi.encode(extensions), abi.encode(new uint256[](0)));
        assertEq(salt, bytes32(0)); // Solady uses bytes32(0) for salt by default
        assertEq(fields, hex"0f"); // `0b01111` - all fields present
    }

    /// @notice Test hashTypedData with actual struct data
    function test_HashTypedData() public view {
        // Create a test struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Transfer(address from,address to,uint256 amount)"),
                address(0x123),
                address(0x456),
                1000
            )
        );

        bytes32 hashTypedData = SmartWallet(payable(_aliceWallet))
            .hashTypedData(structHash);

        // Re-implement EIP-712 hash
        (, , , uint256 chainId, address verifyingContract, , ) = SmartWallet(
            payable(_aliceWallet)
        ).eip712Domain();

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(bytes(TYPE_HASH)),
                keccak256(bytes(Static.ERC712_NAMESPACE)),
                keccak256(bytes(Static.ERC712_VERSION)),
                chainId,
                verifyingContract
            )
        );

        bytes32 expected = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        assertEq(
            expected,
            hashTypedData,
            "hashTypedData should match expected computation"
        );
    }

    /// @notice Test chainless (cross-chain) EIP-712 functionality
    function test_HashTypedDataSansChainId() public view {
        // Create a test struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Transfer(address from,address to,uint256 amount)"),
                address(0x123),
                address(0x456),
                1000
            )
        );

        bytes32 hashTypedDataSansChainId = SmartWallet(payable(_aliceWallet))
            .hashTypedDataSansChainId(structHash);

        // Re-implement EIP-712 hash without chainId
        (, , , , address verifyingContract, , ) = SmartWallet(
            payable(_aliceWallet)
        ).eip712Domain();

        // Domain separator without chainId
        bytes32 domainSeparatorSansChainId = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,address verifyingContract)"
                ),
                keccak256(bytes(Static.ERC712_NAMESPACE)),
                keccak256(bytes(Static.ERC712_VERSION)),
                verifyingContract
            )
        );

        bytes32 expected = keccak256(
            abi.encodePacked("\x19\x01", domainSeparatorSansChainId, structHash)
        );
        assertEq(
            expected,
            hashTypedDataSansChainId,
            "hashTypedDataSansChainId should match expected computation"
        );
    }

    /// @notice Test that chainless and regular hashes are different
    function test_ChainlessVsRegularHashDifference() public view {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Transfer(address from,address to,uint256 amount)"),
                address(0x123),
                address(0x456),
                1000
            )
        );

        bytes32 regularHash = SmartWallet(payable(_aliceWallet)).hashTypedData(
            structHash
        );
        bytes32 chainlessHash = SmartWallet(payable(_aliceWallet))
            .hashTypedDataSansChainId(structHash);

        // They should be different because one includes chainId and the other doesn't
        assertTrue(
            regularHash != chainlessHash,
            "Regular and chainless hashes should be different"
        );
    }

    /// @notice Test that domain name and version are static (don't change after deployment)
    function test_DomainNameAndVersionMayChange() public view {
        // Since _domainNameAndVersionMayChange() returns false, the domain separator should be static
        // by verifying that the domain separator computation is consistent
        // and uses the expected static values from Static.ERC712_NAMESPACE and Static.ERC712_VERSION

        // Test that the domain separator uses the static constants
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256(bytes(TYPE_HASH)),
                keccak256(bytes(Static.ERC712_NAMESPACE)),
                keccak256(bytes(Static.ERC712_VERSION)),
                block.chainid,
                address(_aliceWallet)
            )
        );

        // Test with a simple struct hash
        bytes32 testStructHash = keccak256("test");
        bytes32 actualTypedDataHash = SmartWallet(payable(_aliceWallet))
            .hashTypedData(testStructHash);
        bytes32 expectedTypedDataHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                expectedDomainSeparator,
                testStructHash
            )
        );

        assertEq(
            actualTypedDataHash,
            expectedTypedDataHash,
            "Domain separator should use static constants when _domainNameAndVersionMayChange() returns false"
        );

        // Test consistency - multiple calls should produce the same domain separator
        bytes32 hash1 = SmartWallet(payable(_aliceWallet)).hashTypedData(
            keccak256("test1")
        );
        bytes32 hash2 = SmartWallet(payable(_aliceWallet)).hashTypedData(
            keccak256("test2")
        );

        // Both should use the same domain separator (only struct hash should differ)
        bytes32 expectedHash1 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                expectedDomainSeparator,
                keccak256("test1")
            )
        );
        bytes32 expectedHash2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                expectedDomainSeparator,
                keccak256("test2")
            )
        );

        assertEq(
            hash1,
            expectedHash1,
            "First hash should use static domain separator"
        );
        assertEq(
            hash2,
            expectedHash2,
            "Second hash should use static domain separator"
        );
    }

    /// @notice Test EIP-712 struct hash generation from libraries against Forge's EIP-712 implementation
    function test_EIP712StructHash() public view {
        // Test Call struct hash - verify it matches manual keccak256(abi.encode(...)) computation
        Call memory call = Call({
            target: address(mockToken),
            value: 1000,
            data: abi.encodeWithSelector(
                mockToken.transfer.selector,
                recipient,
                100
            )
        });

        // Get hash from library function
        bytes32 actualCallStructHash = CallLib.hash(call);

        // Verify the type hash is correct using Forge's EIP-712 cheatcodes
        bytes32 forgeCallTypeHash = vm.eip712HashType(CALL_TYPEHASH);
        bytes32 contractCallTypeHash = keccak256(bytes(CALL_TYPEHASH));
        assertEq(
            contractCallTypeHash,
            forgeCallTypeHash,
            "Call type hash should match Forge EIP-712 computation"
        );

        // Compute hash manually using the verified type hash from Forge
        bytes32 expectedCallStructHash = keccak256(
            abi.encode(
                forgeCallTypeHash, // Use Forge's verified type hash
                call.target,
                call.value,
                keccak256(call.data) // Hash the bytes field as per EIP-712
            )
        );

        // Verify the library function produces the same result as Forge's EIP-712 implementation
        assertEq(
            actualCallStructHash,
            expectedCallStructHash,
            "Call struct hash should match Forge EIP-712 computation"
        );

        // Create test calls for BatchedCall
        Call[] memory testCalls = new Call[](2);
        testCalls[0] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                mockToken.transfer.selector,
                recipient,
                100
            )
        });
        testCalls[1] = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSelector(
                mockToken.approve.selector,
                spender,
                200
            )
        });

        BatchedCall memory testBatchedCall = BatchedCall({
            calls: testCalls,
            nonce: 42
        });

        // Test BatchedCall struct hash generation - verify it matches manual keccak256(abi.encode(...)) computation
        bytes32 actualBatchedCallStructHash = BatchedCallLib.hash(
            testBatchedCall,
            testValidUntil,
            testWalletImpl
        );

        // Verify the type hash is correct using Forge's EIP-712 cheatcodes
        bytes32 forgeBatchedCallTypeHash = vm.eip712HashType(
            BATCHED_CALL_TYPEHASH
        );
        bytes32 contractBatchedCallTypeHash = keccak256(
            bytes(BATCHED_CALL_TYPEHASH)
        );
        assertEq(
            contractBatchedCallTypeHash,
            forgeBatchedCallTypeHash,
            "BatchedCall type hash should match Forge EIP-712 computation"
        );

        // Compute the full EIP-712 hash manually using the verified type hash from Forge
        bytes32 expectedBatchedCallStructHash = keccak256(
            abi.encode(
                forgeBatchedCallTypeHash, // Use Forge's verified type hash
                CallLib.hash(testBatchedCall.calls), // Hash of calls array
                testBatchedCall.nonce,
                testValidUntil,
                testWalletImpl
            )
        );

        // Verify the library function produces the same result as Forge's EIP-712 implementation
        assertEq(
            actualBatchedCallStructHash,
            expectedBatchedCallStructHash,
            "BatchedCall struct hash should match Forge EIP-712 computation"
        );

        // Test Message struct hash generation - verify it matches manual keccak256(abi.encode(...)) computation
        bytes32 actualMessageStructHash = MessageSignLib.hash(
            testMessageHash,
            testValidUntil,
            testWalletImpl
        );

        // Verify the type hash is correct using Forge's EIP-712 cheatcodes
        bytes32 forgeMessageTypeHash = vm.eip712HashType(MESSAGE_TYPEHASH);
        bytes32 contractMessageTypeHash = keccak256(bytes(MESSAGE_TYPEHASH));
        assertEq(
            contractMessageTypeHash,
            forgeMessageTypeHash,
            "Message type hash should match Forge EIP-712 computation"
        );

        // Compute hash manually using the verified type hash from Forge
        bytes32 expectedMessageStructHash = keccak256(
            abi.encode(
                forgeMessageTypeHash, // Use Forge's verified type hash
                testMessageHash,
                testValidUntil,
                testWalletImpl
            )
        );

        // Verify the library function produces the same result as Forge's EIP-712 implementation
        assertEq(
            actualMessageStructHash,
            expectedMessageStructHash,
            "Message struct hash should match Forge EIP-712 computation"
        );
    }
}
