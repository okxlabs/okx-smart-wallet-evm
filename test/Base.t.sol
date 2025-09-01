// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {OKXSmartWalletEntry} from "src/OKXSmartWalletEntry.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {DeployInitHelper} from "scripts/deploy/DeployInitHelper.sol";
import {IDeployFactory} from "scripts/utils/IDeployFactory.sol";
import {EIP2470} from "scripts/deploy/EIP2470.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC4337Account} from "src/ERC4337Account.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MessageSignLib} from "src/libraries/MessageSignLib.sol";

// ============ Mock Contracts for Testing ============

contract MockComplexContract {
    uint256 public counter;
    bool public functionCalled;

    receive() external payable {}

    function complexFunction(
        uint256 _number,
        string memory _text,
        bool _flag
    ) external payable returns (bytes memory) {
        functionCalled = true;
        return abi.encode(_number, _text, _flag, msg.value, block.timestamp);
    }

    function simpleIncrement() external {
        counter++;
    }

    function returnLargeData(
        uint256 size
    ) external pure returns (bytes memory) {
        return new bytes(size);
    }
}

contract MockRevertingContract {
    function alwaysReverts() external pure {
        revert("Always reverts");
    }

    function revertWithLargeMessage() external pure {
        // Create a 300-byte error message (larger than MAX_RETURNDATA_SIZE of 256)
        bytes memory largeMessage = new bytes(300);
        for (uint i = 0; i < 300; i++) {
            largeMessage[i] = bytes1(uint8(65 + (i % 26))); // Fill with A-Z pattern
        }
        revert(string(largeMessage));
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Base is Test {
    string public constant NAME = "SmartWallet";
    string public constant VERSION = "1.0.0";

    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS =
        0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    address payable internal _aliceWallet; // Alice's smart wallet address
    bytes32 internal _aliceWalletKeyHash; // Alice's key hash for wallet operations
    address internal _alice; // Alice's EOA address
    uint256 internal _alicePk;
    address internal _bob;
    uint256 internal _bobPk;
    uint256 internal _passkeyPubX;
    uint256 internal _passkeyPubY;
    uint256 internal _passkeyPrivateKey;
    ECDSAValidator internal _ecdsaValidator; // Shared validator instance
    PasskeyValidator internal _passkeyValidator;
    OKXSmartWalletEntry internal _smartWallet;
    SmartWalletFactory internal _factory;
    IDeployFactory public deployFactory;
    address internal relayer;
    uint256 internal relayerPk;
    Call[] internal relayerCalls;
    Call[] internal emptyRelayerCalls;

    event ExecuteSuccessEvent(
        bytes32 indexed intentHash,
        address sender,
        uint256 nonce
    );

    function setUp() public virtual {
        (_alice, _alicePk) = makeAddrAndKey("alice");
        (_bob, _bobPk) = makeAddrAndKey("bob");
        _aliceWalletKeyHash = keccak256(abi.encodePacked(_alice));

        // Deploy EntryPoint and place it at the standard address
        EntryPoint entryPoint = new EntryPoint();
        vm.etch(ENTRYPOINT_ADDRESS, address(entryPoint).code);
        vm.deal(ENTRYPOINT_ADDRESS, 100 ether); // Fund EntryPoint for gas payments

        // Generated real P256 signature using SmartAccount method (crypto.createSign compatibility)
        _passkeyPubX = 0xac3363644e2570764491a4ef772d7a2df4322a6f6830330baa85f2bf5edf4cb1;
        _passkeyPubY = 0x293e49491e2b881d16d17aa6cacee25feccbfb74acce4ff15402f09c2ee9f9f5;
        _passkeyPrivateKey = 0x305cfeb0eecbb0cdb260b8c93b0f9b1f812d601261c135fce04bb8de6a310f0f;

        // Ensure EIP-2470 Singleton Factory is deployed and use it through the interface
        address singletonFactory = EIP2470.ensureDeployed(vm);
        deployFactory = IDeployFactory(singletonFactory);
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        // Deploy validators separately
        _ecdsaValidator = new ECDSAValidator();
        _passkeyValidator = new PasskeyValidator();

        // Deploy SmartWallet and Factory using DeployInitHelper
        (_smartWallet, _factory) = DeployInitHelper.deployContracts(
            deployFactory,
            deployFactorySalt
        );

        // Use factory to create a wallet for Alice
        _aliceWallet = payable(
            _deployAccountSingleOwner(
                keccak256(abi.encodePacked(_alice)),
                address(_ecdsaValidator),
                0
            )
        );

        deal(_aliceWallet, 10 ether);
    }

    function _setCodeToEoa(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
    }

    // ============ Helper Functions for Test Reuse ============

    /// @notice Create InitialOwner array with multiple owners
    /// @param keyHashes Array of key hashes
    /// @param validators Array of validator addresses
    /// @return initialOwners Array with owner configurations
    function _createOwners(
        bytes32[] memory keyHashes,
        address[] memory validators
    ) internal pure returns (InitialOwner[] memory) {
        require(keyHashes.length == validators.length, "Length mismatch");
        InitialOwner[] memory initialOwners = new InitialOwner[](
            keyHashes.length
        );
        for (uint256 i = 0; i < keyHashes.length; i++) {
            initialOwners[i] = InitialOwner({
                keyHash: keyHashes[i],
                validator: validators[i]
            });
        }
        return initialOwners;
    }

    /// @notice Create InitialOwner array with a single owner
    /// @param keyHash The key hash for the owner
    /// @param validator The validator address
    /// @return initialOwners Array with single owner configuration
    function _createSingleOwner(
        bytes32 keyHash,
        address validator
    ) internal pure returns (InitialOwner[] memory) {
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keyHash,
            validator: validator
        });
        return initialOwners;
    }

    /// @notice Deploy a new wallet account with a single owner
    /// @param keyHash The key hash for the owner
    /// @param validator The validator address
    /// @param salt The salt for deterministic deployment
    /// @return account The deployed account address
    function _deployAccountSingleOwner(
        bytes32 keyHash,
        address validator,
        uint256 salt
    ) internal returns (address account) {
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keyHash,
            validator
        );
        return _factory.createAccount(initialOwners, salt);
    }

    /// @notice Deploy a new wallet account with multiple owners
    /// @param keyHashes Array of key hashes for the owners
    /// @param validators Array of validator addresses
    /// @param salt The salt for deterministic deployment
    /// @return account The deployed account address
    function _deployAccountWithOwners(
        bytes32[] memory keyHashes,
        address[] memory validators,
        uint256 salt
    ) internal returns (address account) {
        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );
        return _factory.createAccount(initialOwners, salt);
    }

    /// @notice Add an owner to an existing wallet account through execute flow
    /// @param owner The owner address to execute the call
    /// @param account The wallet account to add owner to
    /// @param keyHash The key hash for the new owner
    /// @param validator The validator address for the new owner
    /// @param settings Packed settings (0 for default)
    function _addOwnerToAccount(
        address owner,
        address account,
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                keyHash,
                validator,
                settings
            )
        });

        vm.prank(owner);
        ISmartWallet(account).execute(calls);
    }

    /// @notice Helper to build addOwner calls for expectRevert tests
    /// @param account The wallet account to add owner to
    /// @param keyHash The key hash for the new owner
    /// @param validator The validator address for the new owner
    /// @param settings Packed settings (0 for default)
    function _buildAddOwnerCalls(
        address account,
        bytes32 keyHash,
        address validator,
        uint256 settings
    ) internal pure returns (Call[] memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(
                IOwnerManager.addOwner.selector,
                keyHash,
                validator,
                settings
            )
        });
        return calls;
    }

    function constructSignature(
        address account,
        uint256 signerPk,
        Call[] memory calls
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHash(account, calls);
        return _signHash(signerPk, hash);
    }

    function constructSignature(
        uint256 nonce,
        uint256 signerPk,
        Call[] memory calls
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHash(nonce, calls);
        return _signHash(signerPk, hash);
    }

    function constructSignatureWithNonce(
        uint256 nonce,
        address account,
        uint256 signerPk,
        Call[] memory calls
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHashWithNonce(account, nonce, calls);
        return _signHash(signerPk, hash);
    }

    function constructCallsData() public view returns (Call[] memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        return calls;
    }

    function constructErc20TransferCall(
        IERC20 token,
        address recipient,
        uint256 amount
    ) public pure returns (Call memory) {
        return
            Call({
                target: address(token),
                value: 0,
                data: abi.encodeWithSelector(
                    IERC20.transfer.selector,
                    recipient,
                    amount
                )
            });
    }

    function _getNonce(address account) internal view returns (uint256) {
        return uint256(INonceManager(account).getNonce(uint192(0)));
    }

    /// @notice Helper function to calculate hash for executeWithRelayer validation
    /// @dev Mimics the exact hash calculation in SmartWallet.executeWithRelayer
    /// @param batchedCall The batched call data
    /// @param validUntil The expiry timestamp (6 bytes)
    /// @param wallet The wallet address for ERC712 domain
    /// @return The final hash ready for signing
    function _getExecuteWithRelayerHash(
        BatchedCall memory batchedCall,
        uint48 validUntil,
        address wallet
    ) internal view returns (bytes32) {
        // 1. Get base hash using BatchedCallLib
        // Use the wallet's implementation address for hash calculation
        bytes32 dataHash = BatchedCallLib.hash(
            batchedCall,
            validUntil,
            SmartWallet(payable(wallet)).IMPLEMENTATION()
        );

        // 3. Apply ERC712 domain separator
        uint256 nonceKey = batchedCall.nonce >> 64;
        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // For chainless nonce, use hashTypedDataSansChainId
            return ERC712(wallet).hashTypedDataSansChainId(dataHash);
        } else {
            // For regular nonce, use standard hashTypedData
            return ERC712(wallet).hashTypedData(dataHash);
        }
    }

    /// @notice Helper function to calculate the hash for isValidSignature
    /// @param hash The base hash to be signed
    /// @param wallet The wallet address
    /// @param validUntil The expiration timestamp (0 for no expiry)
    /// @return The final digest ready to be signed
    function _getIsValidSignatureHash(
        bytes32 hash,
        address wallet,
        uint48 validUntil
    ) internal view returns (bytes32) {
        // Use MessageSignLib to create the struct hash matching SmartWallet.isValidSignature logic
        address implementation = SmartWallet(payable(wallet)).IMPLEMENTATION();
        bytes32 structHash = MessageSignLib.hash(
            hash,
            validUntil,
            implementation
        );

        // Use the wallet's ERC712 hashTypedData function
        return SmartWallet(payable(wallet)).hashTypedData(structHash);
    }

    function _getValidationTypedHash(
        uint256 nonce,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return
            _getExecuteWithRelayerHash(
                BatchedCall({calls: calls, nonce: nonce}),
                0, // validUntil = 0 (no expiry)
                _aliceWallet
            );
    }

    function _getValidationTypedHash(
        address account,
        Call[] memory calls
    ) internal view returns (bytes32) {
        uint256 nonce = _getNonce(account);
        return
            _getExecuteWithRelayerHash(
                BatchedCall({calls: calls, nonce: nonce}),
                0, // validUntil = 0 (no expiry)
                account
            );
    }

    function _getValidationTypedHashWithNonce(
        address account,
        uint256 nonce,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return
            _getExecuteWithRelayerHash(
                BatchedCall({calls: calls, nonce: nonce}),
                0, // validUntil = 0 (no expiry)
                account
            );
    }

    function _signHash(
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _constructRelayerCall(
        uint256 len,
        IERC20 token
    ) internal view returns (Call[] memory calls) {
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            calls[i] = constructErc20TransferCall(token, _aliceWallet, 100);
        }
    }

    function _getExecutionGas(
        uint256 callSize
    ) internal pure returns (uint256) {
        return 31532 + 2210 * callSize + 25160 * callSize;
    }

    function _constructSignature(
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Construct signature for executeWithRelayer/simulateExecuteWithRelayer
    /// @dev Creates the complete signature in format: keyHash + validUntil + signature
    /// @param wallet The wallet address for domain separator
    /// @param signer The signer address
    /// @param privateKey The private key for signing
    /// @param batchedCall The batched call to sign
    /// @param validUntil The expiry timestamp (0 for no expiry)
    /// @return The complete signature for relayer execution
    function _constructRelayerSignature(
        address wallet,
        address signer,
        uint256 privateKey,
        BatchedCall memory batchedCall,
        uint48 validUntil
    ) internal view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        // Calculate hash using the helper that matches SmartWallet logic
        bytes32 hash = _getExecuteWithRelayerHash(
            batchedCall,
            validUntil,
            wallet
        );

        // Sign the hash
        bytes memory signature = _constructSignature(privateKey, hash);

        // Return in format: pubKeyHash (32) + validUntil (6) + signature
        return abi.encodePacked(keyHash, validUntil, signature);
    }

    /// @notice Construct validator data with Merkle proof support for batch operations
    /// @dev Creates validator data with Merkle proofs for batch transaction authorization
    /// @param wallet The wallet address for hash calculation
    /// @param signer The signer address
    /// @param privateKey The private key for signing
    /// @param batchedCall The batched call to sign
    /// @param validUntil The expiry timestamp
    /// @param merkleProofs Array of Merkle proof elements
    /// @return Validator data with format: keyHash + validUntil + signature + abi.encode(proofs)
    function _constructValidatorDataWithMerkleProof(
        address wallet,
        address signer,
        uint256 privateKey,
        BatchedCall memory batchedCall,
        uint48 validUntil,
        bytes32[] memory merkleProofs
    ) internal view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        // Calculate hash using the helper that matches SmartWallet logic
        bytes32 messageHash = _getExecuteWithRelayerHash(
            batchedCall,
            validUntil,
            wallet
        );

        // If there are Merkle proofs, we need to sign the root hash instead
        bytes32 hashToSign = messageHash;
        if (merkleProofs.length > 0) {
            // Process Merkle proof to get root hash (mimicking MerkleProofProcessor)
            hashToSign = MerkleProof.processProof(merkleProofs, messageHash);
        }

        // Sign the appropriate hash
        bytes memory signature = _constructSignature(privateKey, hashToSign);

        // Return in format: pubKeyHash (32) + validUntil (6) + signature + abi.encode(proofs)
        return
            abi.encodePacked(
                keyHash,
                validUntil,
                signature,
                abi.encode(merkleProofs)
            );
    }

    /// @notice Unified helper to prepare and sign UserOp with automatic hash calculation
    /// @dev Handles all the complexity of getting baseHash from EntryPoint and calculating final hash
    /// @param userOp The user operation to sign
    /// @param signer The signer address
    /// @param privateKey The private key for signing
    /// @param wallet The wallet address
    /// @param validUntil The expiry timestamp (0 for no expiry)
    /// @return signature The complete signature with keyHash and validUntil
    /// @return finalHash The final hash that will be used for validation
    function _prepareAndSignUserOp(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        address wallet,
        uint48 validUntil
    ) internal view returns (bytes memory signature, bytes32 finalHash) {
        // Get the base hash from EntryPoint
        bytes32 baseHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        // Calculate the final hash with validUntil and chainless logic
        finalHash = _getValidateUserOpHash(
            userOp,
            baseHash,
            validUntil,
            wallet
        );

        // Create the signature
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, finalHash);
        signature = abi.encodePacked(keyHash, validUntil, r, s, v);
    }

    /// @notice Overload with default validUntil = 0
    function _prepareAndSignUserOp(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        address wallet
    ) internal view returns (bytes memory signature, bytes32 finalHash) {
        return
            _prepareAndSignUserOp(
                userOp,
                signer,
                privateKey,
                wallet,
                uint48(0)
            );
    }

    // ============ ValidateUserOp Helper Functions ============

    /// @notice Calculate the final hash for validateUserOp validation
    /// @dev Mimics the exact hash calculation in SmartWallet.validateUserOp
    /// @param userOp The user operation (needed for chainless mode)
    /// @param userOpHash The initial user operation hash from EntryPoint
    /// @param validUntil The expiry timestamp (6 bytes)
    /// @param wallet The wallet address for chainless hash calculation
    /// @return The final hash ready for signing
    function _getValidateUserOpHash(
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint48 validUntil,
        address wallet
    ) internal view returns (bytes32) {
        // 1. If chainless nonce, apply getUserOpHashWithoutChainId
        uint256 nonceKey = userOp.nonce >> 64;
        if (nonceKey == Static.CHAIN_LESS_NONCE_KEY) {
            // For chainless, get hash without chainId
            userOpHash = ERC4337Account(wallet).getUserOpHashWithoutChainId(
                userOp
            );
        }

        // 2. Add validUntil and IMPLEMENTATION to hash after chainless processing
        // The IMPLEMENTATION is the deployed SmartWallet implementation address
        return
            keccak256(
                abi.encode(userOpHash, validUntil, address(_smartWallet))
            );
    }

    /// @notice Construct signature for validateUserOp
    /// @dev Creates the complete signature in the format: pubKeyHash + validUntil + signature
    /// @param userOp The user operation (needed for chainless mode)
    /// @param signer The signer address
    /// @param privateKey The private key for signing
    /// @param userOpHash The user operation hash from EntryPoint
    /// @param validUntil The expiry timestamp (use 0 for no expiry)
    /// @param wallet The wallet address
    /// @return The complete signature for userOp
    function _constructUserOpSignature(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        bytes32 userOpHash,
        uint48 validUntil,
        address wallet
    ) internal view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        // Calculate the correct hash with validUntil and chainless logic
        bytes32 finalHash = _getValidateUserOpHash(
            userOp,
            userOpHash,
            validUntil,
            wallet
        );

        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, finalHash);

        // Return in format: pubKeyHash (32) + validUntil (6) + signature
        return abi.encodePacked(keyHash, validUntil, r, s, v);
    }

    /// @notice Overload for convenience with default validUntil = 0
    function _constructUserOpSignature(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        bytes32 userOpHash,
        address wallet
    ) internal view returns (bytes memory) {
        return
            _constructUserOpSignature(
                userOp,
                signer,
                privateKey,
                userOpHash,
                uint48(0),
                wallet
            );
    }

    // Helper function for tests to check if a signer is admin
    function _isSignerAdmin(
        address wallet,
        bytes32 keyHash
    ) internal view returns (bool) {
        uint256 settings = IOwnerManager(wallet).ownerSettings(keyHash);
        return settings != 0 && IOwnerManager(wallet).isAdmin(settings);
    }

    // Helper function to test validateUserOp from EntryPoint's perspective
    function _testValidateUserOp(
        address account,
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) internal returns (uint256) {
        vm.prank(ENTRYPOINT_ADDRESS);
        return
            IAccount(account).validateUserOp(
                userOp,
                userOpHash,
                missingAccountFunds
            );
    }

    /// @notice Simplified version that auto-calculates the hash
    /// @dev Automatically handles EntryPoint hash calculation
    function _testValidateUserOp(
        address account,
        PackedUserOperation memory userOp,
        uint256 missingAccountFunds
    ) internal returns (uint256) {
        // Get the hash that EntryPoint would calculate
        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(
            userOp
        );

        vm.prank(ENTRYPOINT_ADDRESS);
        return
            IAccount(account).validateUserOp(
                userOp,
                userOpHash,
                missingAccountFunds
            );
    }

    // Helper function for tests to check if a signer is expired
    function _isSignerExpired(
        address wallet,
        bytes32 keyHash
    ) internal view returns (bool) {
        uint256 settings = IOwnerManager(wallet).ownerSettings(keyHash);
        return
            settings != 0 && IOwnerManager(wallet).isSettingsExpired(settings);
    }

    // Helper function for tests to get signer expiration
    function _getSignerExpiration(
        address wallet,
        bytes32 keyHash
    ) internal view returns (uint40) {
        uint256 settings = IOwnerManager(wallet).ownerSettings(keyHash);
        return
            settings != 0 ? IOwnerManager(wallet).getExpiration(settings) : 0;
    }
    // Helper function to call removeValidator through execute
    function _executeRemoveValidator(address wallet, bytes32 keyHash) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: wallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnerManager.removeOwner.selector,
                keyHash
            )
        });

        vm.prank(wallet);
        ISmartWallet(wallet).execute(calls);
    }
}
