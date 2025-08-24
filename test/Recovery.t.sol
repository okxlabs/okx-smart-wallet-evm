// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {RecoverySigner} from "smart-wallet-recovery/RecoverySigner.sol";
import {NonceManager} from "smart-wallet-recovery/NonceManager.sol";
import {RecoveryTypes} from "smart-wallet-recovery/utils/RecoveryTypes.sol";
import {ISmartWallet as ISmartWalletRecovery} from "smart-wallet-recovery/interfaces/ISmartWallet.sol";
import {IRecoveryVerifier} from "smart-wallet-recovery/interfaces/IRecoveryVerifier.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Errors} from "src/libraries/Errors.sol";
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
     * @return The configured mock timestamp
     */
    function verify(
        RecoveryTypes.RecoveryData calldata,
        RecoveryTypes.RecoverySignature calldata
    ) external view override returns (uint256) {
        if (shouldRevert) {
            revert("MockRecoveryVerifier: Verification failed");
        }

        // In a real verifier, this would validate the signature against the recovery data
        // For testing, we just return the mock timestamp
        return mockTimestamp;
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

        // Deploy RecoverySigner implementation
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
        // Create a smart wallet with RecoverySigner as one of the initial owners
        InitialOwner[] memory initialOwners = new InitialOwner[](2);

        // Regular owner (Alice)
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });

        // RecoverySigner as owner (using address(1) as EOA validator)
        initialOwners[1] = InitialOwner({
            keyHash: recoverySignerKeyHash,
            validator: address(1) // EOA validator for contract owner
        });

        // Create the account
        recoveredAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
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
        // Setup: Create account with RecoverySigner as owner
        InitialOwner[] memory initialOwners = new InitialOwner[](2);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });
        initialOwners[1] = InitialOwner({
            keyHash: recoverySignerKeyHash,
            validator: address(1)
        });

        recoveredAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        // Test: RecoverySigner calls addOwner through execute method
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwner));

        // Settings with admin flag set (bit 200)
        uint256 adminSettings = uint256(1) << 200;

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
        // Setup: Create account with RecoverySigner as owner
        InitialOwner[] memory initialOwners = new InitialOwner[](2);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });
        initialOwners[1] = InitialOwner({
            keyHash: recoverySignerKeyHash,
            validator: address(1)
        });

        recoveredAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
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
                newOwner: newOwnerKeyHash
            });

        // Prepare recovery signatures
        RecoveryTypes.RecoverySignature[]
            memory signatures = new RecoveryTypes.RecoverySignature[](1);
        signatures[0] = RecoveryTypes.RecoverySignature({
            verifier: address(mockVerifier),
            keyHash: keyHashes[0],
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
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });

        recoveredAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
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
                newOwner: newOwnerKeyHash
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
        vm.expectRevert(); // Will revert in NonceManager.consume() check
        recoverySigner.recover(recoveryData, signatures);
    }

    function test_recovery_settings_match_expected() public {
        // Create an account first
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });

        recoveredAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
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
            InitialOwner[] memory initialOwners = new InitialOwner[](2);
            initialOwners[0] = InitialOwner({
                keyHash: keccak256(abi.encodePacked(_alice, i)),
                validator: address(_ecdsaValidator)
            });
            initialOwners[1] = InitialOwner({
                keyHash: recoverySignerKeyHash,
                validator: address(1)
            });

            accounts[i] = _factory.createAccount(
                address(_smartWallet),
                initialOwners,
                i + 100 // Different salts
            );
        }

        // Prepare recovery data for all accounts
        bytes32 newOwnerKeyHash = keccak256(abi.encodePacked(newOwner));

        RecoveryTypes.RecoveryData memory recoveryData = RecoveryTypes
            .RecoveryData({
                accounts: accounts,
                validator: address(_ecdsaValidator),
                newOwner: newOwnerKeyHash
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
        // Setup account
        InitialOwner[] memory initialOwners = new InitialOwner[](2);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });
        initialOwners[1] = InitialOwner({
            keyHash: recoverySignerKeyHash,
            validator: address(1)
        });

        recoveredAccount = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
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
                newOwner: firstOwnerKeyHash
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

        // Check nonce was consumed
        uint256 firstNonce = nonceManager.nonces(recoveredAccount);
        assertGt(firstNonce, 0, "Nonce should be set after first recovery");

        // Attempt second recovery with same timestamp (should fail)
        bytes32 secondOwnerKeyHash = keccak256(
            abi.encodePacked(makeAddr("second"))
        );
        recoveryData.newOwner = secondOwnerKeyHash;

        vm.expectRevert(); // Should revert due to nonce already consumed
        recoverySigner.recover(recoveryData, signatures);

        // Update timestamp and retry with a higher value (but within allowed range)
        mockVerifier.setMockTimestamp(block.timestamp + 100);
        recoverySigner.recover(recoveryData, signatures);

        // Verify second recovery succeeded
        assertTrue(
            IOwnersManager(recoveredAccount).hasOwner(secondOwnerKeyHash),
            "Second recovery should succeed with new timestamp"
        );

        uint256 secondNonce = nonceManager.nonces(recoveredAccount);
        assertGt(
            secondNonce,
            firstNonce,
            "Nonce should increase after second recovery"
        );
    }
}
