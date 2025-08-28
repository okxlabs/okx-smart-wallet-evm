// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {NonceManager} from "smart-wallet-recovery/NonceManager.sol";
import {RecoverySigner} from "smart-wallet-recovery/RecoverySigner.sol";
import {RecoveryTypes} from "smart-wallet-recovery/utils/RecoveryTypes.sol";
import {ISmartWallet as ISmartWalletRecovery} from "smart-wallet-recovery/interfaces/ISmartWallet.sol";
import {IRecoveryVerifier} from "smart-wallet-recovery/interfaces/IRecoveryVerifier.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {LibClone} from "solady/utils/LibClone.sol";

/**
 * @title MockRecoveryVerifier
 * @notice Mock implementation of IRecoveryVerifier for testing
 * @dev Simulates a ZK verifier that always returns success with configurable timestamp
 */
contract MockRecoveryVerifier is IRecoveryVerifier {
    uint256 public mockTimestamp;
    bool public shouldRevert;

    constructor(uint256 _timestamp) {
        mockTimestamp = _timestamp;
    }

    /**
     * @notice Mock verification that always succeeds unless configured to revert
     * @return true if verification succeeds, false otherwise
     */
    function verify(
        RecoveryTypes.RecoveryData calldata,
        RecoveryTypes.RecoverySignature calldata
    ) external view override returns (bool) {
        if (shouldRevert) {
            revert("MockRecoveryVerifier: Verification failed");
        }

        // In a real verifier, this would validate the signature against the recovery data
        // For testing, we just return true to indicate success
        return true;
    }

    /**
     * @notice Set the mock timestamp to return
     * @param _timestamp The timestamp to return from verify()
     */
    function setMockTimestamp(uint256 _timestamp) external {
        mockTimestamp = _timestamp;
    }

    /**
     * @notice Configure whether verify() should revert
     * @param _shouldRevert True to make verify() revert
     */
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

contract RecoveryTest is Base {
    // Recovery system contracts
    NonceManager nonceManager;
    RecoverySigner recoverySignerImpl;
    RecoverySigner recoverySigner;
    MockRecoveryVerifier mockVerifier;

    // Test accounts
    address recoveredAccount;
    address newOwner;
    uint256 newOwnerPk;

    // Recovery configuration
    bytes32[] keyHashes;
    address[] verifiers;
    bytes32 recoverySignerKeyHash;

    function setUp() public override {
        super.setUp();

        // Create new owner for recovery
        (newOwner, newOwnerPk) = makeAddrAndKey("newOwner");

        // Deploy NonceManager
        nonceManager = new NonceManager();

        // Deploy mock verifier with current block timestamp (safe for testing)
        mockVerifier = new MockRecoveryVerifier(block.timestamp);

        // Setup recovery configuration
        keyHashes = new bytes32[](1);
        keyHashes[0] = keccak256("recovery_key_1");

        verifiers = new address[](1);
        verifiers[0] = address(mockVerifier);

        // Deploy RecoverySigner implementation with NonceManager
        recoverySignerImpl = new RecoverySigner(address(nonceManager));

        // Use LibClone to create deterministic clone
        bytes32 salt = keccak256(abi.encode(keyHashes, verifiers));
        address cloneAddress = LibClone.cloneDeterministic(
            address(recoverySignerImpl),
            salt
        );

        // Initialize the clone
        RecoverySigner(cloneAddress).initialize(keyHashes, verifiers);
        recoverySigner = RecoverySigner(cloneAddress);

        // Calculate RecoverySigner's keyHash for use as owner
        recoverySignerKeyHash = keccak256(
            abi.encodePacked(address(recoverySigner))
        );
    }

    function test_RecoverySigner_as_initial_owner() public {
        // Use existing _aliceWallet account and add RecoverySigner as owner
        recoveredAccount = _aliceWallet;

        // Add RecoverySigner as owner through proper execute flow
        _addOwnerToAccount(
            _alice,
            recoveredAccount,
            recoverySignerKeyHash,
            address(1), // EOA validator for contract owner
            0
        );

        // Verify RecoverySigner is registered as owner
        assertTrue(
            IOwnersManager(recoveredAccount).hasOwner(recoverySignerKeyHash),
            "RecoverySigner should be registered as owner"
        );

        // Verify the validator is set correctly
        address validator = IOwnersManager(recoveredAccount).ownerValidators(
            recoverySignerKeyHash
        );
        assertEq(
            validator,
            address(1),
            "RecoverySigner should have EOA validator"
        );
    }

    function test_addOwner_interface_compatibility() public {
        // Use existing _aliceWallet account and add RecoverySigner as owner
        recoveredAccount = _aliceWallet;

        // Add RecoverySigner as owner with admin privileges
        uint256 adminSettings = uint256(1) << 200; // Set admin flag
        _addOwnerToAccount(
            _alice,
            recoveredAccount,
            recoverySignerKeyHash,
            address(1),
            adminSettings
        );

        // Test: RecoverySigner calls addOwner through execute method
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwner));

        // Reuse adminSettings from above (already set with admin flag)

        // Prepare the addOwner call data
        bytes memory addOwnerData = abi.encodeWithSelector(
            ISmartWalletRecovery.addOwner.selector,
            newOwnerKeyHash,
            address(_ecdsaValidator),
            adminSettings
        );

        // Create call array for execute
        ISmartWalletRecovery.Call[]
            memory calls = new ISmartWalletRecovery.Call[](1);
        calls[0] = ISmartWalletRecovery.Call({
            to: recoveredAccount,
            value: 0,
            data: addOwnerData
        });

        // This tests that our SmartWallet's execute is compatible with RecoverySigner's approach
        vm.prank(address(recoverySigner));
        ISmartWalletRecovery(recoveredAccount).execute(calls);

        // Verify the new owner was added
        assertTrue(
            IOwnersManager(recoveredAccount).hasOwner(newOwnerKeyHash),
            "New owner should be added"
        );

        // Verify the settings are correct
        (, , , bool isAdmin, ) = IOwnersManager(recoveredAccount)
            .getOwnerSettings(newOwnerKeyHash);
        assertTrue(isAdmin, "New owner should have admin privileges");
    }

    function test_recovery_full_flow() public {
        // Use existing _aliceWallet account and add RecoverySigner as owner
        recoveredAccount = _aliceWallet;

        // Add RecoverySigner as owner with admin privileges
        uint256 adminSettings = uint256(1) << 200; // Set admin flag
        _addOwnerToAccount(
            _alice,
            recoveredAccount,
            recoverySignerKeyHash,
            address(1),
            adminSettings
        );

        // Prepare recovery data
        address[] memory accounts = new address[](1);
        accounts[0] = recoveredAccount;

        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwner));

        RecoveryTypes.RecoveryData memory recoveryData = RecoveryTypes
            .RecoveryData({
                accounts: accounts,
                validator: address(_ecdsaValidator),
                newOwner: newOwnerKeyHash,
                timestamp: block.timestamp
            });

        // Prepare recovery signatures
        RecoveryTypes.RecoverySignature[]
            memory signatures = new RecoveryTypes.RecoverySignature[](1);
        signatures[0] = RecoveryTypes.RecoverySignature({
            verifier: address(mockVerifier),
            keyHash: keyHashes[0], // This uses the class member keyHashes[0] which is keccak256("recovery_key_1")
            signature: abi.encode("mock_signature")
        });

        // Execute recovery
        recoverySigner.recover(recoveryData, signatures);

        // Verify the new owner was added
        assertTrue(
            IOwnersManager(recoveredAccount).hasOwner(newOwnerKeyHash),
            "Recovery should add new owner"
        );

        // Verify the new owner has admin privileges
        uint256 settings = IOwnersManager(recoveredAccount).ownerSettings(
            newOwnerKeyHash
        );
        assertTrue(
            IOwnersManager(recoveredAccount).isAdmin(settings),
            "Recovered owner should have admin privileges"
        );

        // Verify the validator is set correctly
        address validator = IOwnersManager(recoveredAccount).ownerValidators(
            newOwnerKeyHash
        );
        assertEq(
            validator,
            address(_ecdsaValidator),
            "Recovered owner should have correct validator"
        );
    }

    function test_recovery_requires_RecoverySigner_ownership() public {
        // Create account WITHOUT RecoverySigner as owner
        recoveredAccount = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            0
        );

        // Prepare recovery data
        address[] memory accounts = new address[](1);
        accounts[0] = recoveredAccount;

        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwner));

        RecoveryTypes.RecoveryData memory recoveryData = RecoveryTypes
            .RecoveryData({
                accounts: accounts,
                validator: address(_ecdsaValidator),
                newOwner: newOwnerKeyHash,
                timestamp: block.timestamp
            });

        // Prepare recovery signatures
        RecoveryTypes.RecoverySignature[]
            memory signatures = new RecoveryTypes.RecoverySignature[](1);
        signatures[0] = RecoveryTypes.RecoverySignature({
            verifier: address(mockVerifier),
            keyHash: keyHashes[0],
            signature: abi.encode("mock_signature")
        });

        // Recovery should fail because RecoverySigner is not an owner
        vm.expectRevert(); // Will revert when RecoverySigner tries to execute
        recoverySigner.recover(recoveryData, signatures);
    }

    function test_recovery_settings_match_expected() public {
        // Create an account first
        recoveredAccount = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            0
        );

        // The RecoverySigner uses settings = uint256(1) << 200
        // This should result in:
        // - adminFlag = true (bit 200 set)
        // - expiration = 0 (no expiration)
        // - hook = address(0) (no hook)

        uint256 expectedSettings = uint256(1) << 200;

        // Verify our packSettings produces the same result
        uint256 packedSettings = IOwnersManager(recoveredAccount).packSettings(
            true, // adminFlag
            0, // expiration
            address(0) // hook
        );

        assertEq(
            packedSettings,
            expectedSettings,
            "Settings should match RecoverySigner format"
        );

        // Verify the components
        assertTrue(
            IOwnersManager(recoveredAccount).isAdmin(expectedSettings),
            "Should be admin"
        );
        assertEq(
            IOwnersManager(recoveredAccount).getExpiration(expectedSettings),
            0,
            "Should have no expiration"
        );
        assertEq(
            IOwnersManager(recoveredAccount).getHook(expectedSettings),
            address(0),
            "Should have no hook"
        );
    }

    function test_multiple_accounts_recovery() public {
        // Create multiple accounts with RecoverySigner as owner
        address[] memory accounts = new address[](3);

        for (uint i = 0; i < 3; i++) {
            bytes32[] memory ownerKeyHashes = new bytes32[](2);
            address[] memory validators = new address[](2);
            ownerKeyHashes[0] = keccak256(abi.encodePacked(_alice, i));
            validators[0] = address(_ecdsaValidator);
            ownerKeyHashes[1] = recoverySignerKeyHash;
            validators[1] = address(1);

            accounts[i] = _deployAccountWithOwners(
                ownerKeyHashes,
                validators,
                i + 100 // Different salts
            );
        }

        // Prepare recovery data for all accounts
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwner));

        RecoveryTypes.RecoveryData memory recoveryData = RecoveryTypes
            .RecoveryData({
                accounts: accounts,
                validator: address(_ecdsaValidator),
                newOwner: newOwnerKeyHash,
                timestamp: block.timestamp
            });

        // Prepare recovery signatures
        RecoveryTypes.RecoverySignature[]
            memory signatures = new RecoveryTypes.RecoverySignature[](1);
        signatures[0] = RecoveryTypes.RecoverySignature({
            verifier: address(mockVerifier),
            keyHash: keyHashes[0],
            signature: abi.encode("mock_signature")
        });

        // Execute recovery for all accounts
        recoverySigner.recover(recoveryData, signatures);

        // Verify all accounts have the new owner
        for (uint i = 0; i < accounts.length; i++) {
            assertTrue(
                IOwnersManager(accounts[i]).hasOwner(newOwnerKeyHash),
                "Each account should have new owner"
            );
        }
    }

    function test_recovery_timestamp_management() public {
        // Use existing _aliceWallet account and add RecoverySigner as owner
        recoveredAccount = _aliceWallet;

        // Add RecoverySigner as owner with admin privileges
        uint256 adminSettings = uint256(1) << 200; // Set admin flag
        _addOwnerToAccount(
            _alice,
            recoveredAccount,
            recoverySignerKeyHash,
            address(1),
            adminSettings
        );

        // First recovery
        address[] memory accounts = new address[](1);
        accounts[0] = recoveredAccount;

        bytes32 firstOwnerKeyHash = keccak256(
            abi.encodePacked(makeAddr("first"))
        );

        RecoveryTypes.RecoveryData memory recoveryData = RecoveryTypes
            .RecoveryData({
                accounts: accounts,
                validator: address(_ecdsaValidator),
                newOwner: firstOwnerKeyHash,
                timestamp: block.timestamp // Use block.timestamp like other tests
            });

        RecoveryTypes.RecoverySignature[]
            memory signatures = new RecoveryTypes.RecoverySignature[](1);
        signatures[0] = RecoveryTypes.RecoverySignature({
            verifier: address(mockVerifier),
            keyHash: keyHashes[0],
            signature: abi.encode("mock_signature")
        });

        // Execute first recovery
        recoverySigner.recover(recoveryData, signatures);

        // First recovery completed successfully

        // Attempt second recovery with same timestamp (should fail)
        bytes32 secondOwnerKeyHash = keccak256(
            abi.encodePacked(makeAddr("second"))
        );
        recoveryData.newOwner = secondOwnerKeyHash;

        // Note: Recovery with same timestamp should fail (timestamp already consumed)
        // The first recovery consumed the timestamp from mockVerifier
        vm.expectRevert(); // Should revert if timestamp already used
        recoverySigner.recover(recoveryData, signatures);

        // Update mock verifier to return a higher timestamp
        mockVerifier.setMockTimestamp(block.timestamp + 1);

        // Update recoveryData with new timestamp for second recovery
        recoveryData.timestamp = block.timestamp + 1; // Next timestamp

        // Retry with the higher timestamp
        recoverySigner.recover(recoveryData, signatures);

        // Verify second recovery succeeded
        assertTrue(
            IOwnersManager(recoveredAccount).hasOwner(secondOwnerKeyHash),
            "Second recovery should succeed with new timestamp"
        );

        // Second recovery completed successfully with new timestamp
    }
}
