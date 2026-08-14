// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {SmartWalletEntry} from "src/SmartWalletEntry.sol";
import {ECDSAValidator} from "./validators/ECDSAValidator.sol";
import {PasskeyValidator} from "./validators/PasskeyValidator.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {DeployInitHelper} from "./utils/DeployInitHelper.s.sol";
import {IDeployFactory} from "script/IDeployFactory.s.sol";
import {EIP2470} from "./utils/EIP2470.s.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Static} from "src/libraries/Static.sol";
import {ERC4337Account} from "src/ERC4337Account.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MessageSignLib} from "src/libraries/MessageSignLib.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ============ Mock Contracts for Testing ============

contract MockComplexContract {
    uint256 public counter;
    bool public functionCalled;

    receive() external payable {}

    function complexFunction(uint256 _number, string memory _text, bool _flag) external payable returns (bytes memory) {
        functionCalled = true;
        return abi.encode(_number, _text, _flag, msg.value, block.timestamp);
    }

    function simpleIncrement() external {
        counter++;
    }

    function returnLargeData(uint256 size) external pure returns (bytes memory) {
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
        for (uint256 i = 0; i < 300; i++) {
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
    using BatchedCallLib for BatchedCall;

    string public constant NAME = "SmartWallet";
    string public constant VERSION = "1.0.0";

    // Test-only queue namespaces. Production code intentionally does not bind
    // an operation type to a specific chainless selector.
    uint16 internal constant CHAINLESS_OPERATION_TYPE_1 = 1;
    uint16 internal constant CHAINLESS_OPERATION_TYPE_2 = 2;

    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    address payable internal _aliceWallet; // Alice's smart wallet address
    bytes32 internal _aliceWalletKeyHash; // Alice's key hash for wallet operations
    address internal _alice; // Alice's EOA address
    uint256 internal _alicePk;
    address internal _bob;
    uint256 internal _bobPk;
    address internal _charlie;
    uint256 internal _charliePk;
    address internal _dave;
    uint256 internal _davePk;
    uint256 internal _passkeyPubX;
    uint256 internal _passkeyPubY;
    uint256 internal _passkeyPrivateKey;
    ECDSAValidator internal _ecdsaValidator; // Shared validator instance
    PasskeyValidator internal _passkeyValidator;
    SmartWalletEntry internal _smartWallet;
    SmartWalletFactory internal _factory;
    IDeployFactory public deployFactory;
    address internal relayer;
    Call[] internal relayerCalls;
    Call[] internal emptyRelayerCalls;

    event RelayerExecuteSuccessEvent(bytes32 indexed intentHash, address sender, uint256 nonce);

    function setUp() public virtual {
        (_alice, _alicePk) = makeAddrAndKey("alice");
        (_bob, _bobPk) = makeAddrAndKey("bob");
        (_charlie, _charliePk) = makeAddrAndKey("charlie");
        (_dave, _davePk) = makeAddrAndKey("dave");
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
        bytes32 deployFactorySalt = vm.envOr("DEPLOY_FACTORY_SALT", bytes32(0));

        // Deploy validators separately
        _ecdsaValidator = new ECDSAValidator();
        _passkeyValidator = new PasskeyValidator();

        // Deploy SmartWallet, Factory, and Simulator using DeployInitHelper
        (_smartWallet, _factory) = DeployInitHelper.deployContracts(deployFactory, deployFactorySalt);

        // Use factory to create a wallet for Alice
        _aliceWallet =
            payable(_deployAccountSingleOwner(keccak256(abi.encodePacked(_alice)), address(_ecdsaValidator), 0));

        deal(_aliceWallet, 10 ether);
    }

    function _setCodeToEoa(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
    }

    // ============ Helper Functions for Test Reuse ============

    function _createOwners(bytes32[] memory keyHashes, address[] memory validators)
        internal
        pure
        returns (InitialOwner[] memory)
    {
        require(keyHashes.length == validators.length, "Length mismatch");
        InitialOwner[] memory initialOwners = new InitialOwner[](keyHashes.length);
        for (uint256 i = 0; i < keyHashes.length; i++) {
            initialOwners[i] = InitialOwner({keyHash: keyHashes[i], validator: validators[i]});
        }
        return initialOwners;
    }

    function _createSingleOwner(bytes32 keyHash, address validator) internal pure returns (InitialOwner[] memory) {
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({keyHash: keyHash, validator: validator});
        return initialOwners;
    }

    function _deployAccountSingleOwner(bytes32 keyHash, address validator, uint256 salt)
        internal
        returns (address account)
    {
        InitialOwner[] memory initialOwners = _createSingleOwner(keyHash, validator);
        return _factory.createAccount(initialOwners, salt);
    }

    function _deployAccountWithOwners(bytes32[] memory keyHashes, address[] memory validators, uint256 salt)
        internal
        returns (address account)
    {
        InitialOwner[] memory initialOwners = _createOwners(keyHashes, validators);
        return _factory.createAccount(initialOwners, salt);
    }

    function _addOwnerToAccount(address owner, address account, bytes32 keyHash, address validator, uint256 settings)
        internal
    {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(IOwnerManager.addOwner.selector, keyHash, validator, settings)
        });

        vm.prank(owner);
        ISmartWallet(account).execute(calls);
    }

    function _buildAddOwnerCalls(address account, bytes32 keyHash, address validator, uint256 settings)
        internal
        pure
        returns (Call[] memory)
    {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account,
            value: 0,
            data: abi.encodeWithSelector(IOwnerManager.addOwner.selector, keyHash, validator, settings)
        });
        return calls;
    }

    function constructSignature(address account, uint256 signerPk, Call[] memory calls)
        public
        view
        returns (bytes memory)
    {
        bytes32 hash = _getValidationTypedHash(account, calls);
        return _signHash(signerPk, hash);
    }

    function constructSignature(uint256 nonce, uint256 signerPk, Call[] memory calls)
        public
        view
        returns (bytes memory)
    {
        bytes32 hash = _getValidationTypedHash(nonce, calls);
        return _signHash(signerPk, hash);
    }

    function constructSignatureWithNonce(uint256 nonce, address account, uint256 signerPk, Call[] memory calls)
        public
        view
        returns (bytes memory)
    {
        bytes32 hash = _getValidationTypedHashWithNonce(account, nonce, calls);
        return _signHash(signerPk, hash);
    }

    function constructCallsData() public view returns (Call[] memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        return calls;
    }

    function constructErc20TransferCall(IERC20 token, address recipient, uint256 amount)
        public
        pure
        returns (Call memory)
    {
        return Call({
            target: address(token), value: 0, data: abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount)
        });
    }

    function _getNonce(address account) internal view returns (uint256) {
        return uint256(INonceManager(account).getNonce(uint192(0)));
    }

    function _chainlessNonce(
        uint16 operationType,
        uint16 queueId,
        uint64 sequence
    ) internal pure returns (uint256) {
        return
            (Static.CHAINLESS_NONCE_KEY << 96) |
            (uint256(operationType) << 80) |
            (uint256(queueId) << 64) |
            uint256(sequence);
    }

    function _encodeExecuteUserOpCalls(
        Call[] memory calls
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                IERC4337Account.executeUserOp.selector,
                abi.encode(calls)
            );
    }

    // Mimics the exact hash calculation in SmartWallet.executeWithRelayer
    function _getExecuteWithRelayerHash(BatchedCall memory batchedCall, uint48 validUntil, address wallet)
        internal
        view
        returns (bytes32)
    {
        bytes32 dataHash = BatchedCallLib.hash(batchedCall, validUntil, SmartWallet(payable(wallet)).IMPLEMENTATION());

        if (batchedCall.nonce >> 96 == Static.CHAINLESS_NONCE_KEY) {
            // For chainless nonce, use hashTypedDataSansChainId
            return ERC712(wallet).hashTypedDataSansChainId(dataHash);
        } else {
            // For regular nonce, use standard hashTypedData
            return ERC712(wallet).hashTypedData(dataHash);
        }
    }

    function _getIsValidSignatureHash(bytes32 hash, address wallet, uint48 validUntil) internal view returns (bytes32) {
        address implementation = SmartWallet(payable(wallet)).IMPLEMENTATION();
        bytes32 structHash = MessageSignLib.hash(hash, validUntil, implementation);

        return SmartWallet(payable(wallet)).hashTypedData(structHash);
    }

    function _getValidationTypedHash(uint256 nonce, Call[] memory calls) internal view returns (bytes32) {
        return _getExecuteWithRelayerHash(
            BatchedCall({calls: calls, nonce: nonce}),
            0, // validUntil = 0 (no expiry)
            _aliceWallet
        );
    }

    function _getValidationTypedHash(address account, Call[] memory calls) internal view returns (bytes32) {
        uint256 nonce = _getNonce(account);
        return
            _getExecuteWithRelayerHash(
                BatchedCall({calls: calls, nonce: nonce}),
                0, // validUntil = 0 (no expiry)
                account
            );
    }

    function _getValidationTypedHashWithNonce(address account, uint256 nonce, Call[] memory calls)
        internal
        view
        returns (bytes32)
    {
        return _getExecuteWithRelayerHash(
            BatchedCall({calls: calls, nonce: nonce}),
            0, // validUntil = 0 (no expiry)
            account
        );
    }

    function _signHash(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _makeKeyHash(address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(addr));
    }

    function _constructRelayerCall(uint256 len, IERC20 token) internal view returns (Call[] memory calls) {
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            calls[i] = constructErc20TransferCall(token, _aliceWallet, 100);
        }
    }

    function _getExecutionGas(uint256 callSize) internal pure returns (uint256) {
        return 31532 + 2210 * callSize + 25160 * callSize;
    }

    function _constructRelayerSignature(
        address wallet,
        address signer,
        uint256 privateKey,
        BatchedCall memory batchedCall,
        uint48 validUntil
    ) internal view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes32 hash = _getExecuteWithRelayerHash(batchedCall, validUntil, wallet);
        return abi.encodePacked(keyHash, validUntil, _signHash(privateKey, hash));
    }

    function _constructValidatorDataWithMerkleProof(
        address wallet,
        address signer,
        uint256 privateKey,
        BatchedCall memory batchedCall,
        uint48 validUntil,
        bytes32[] memory merkleProofs
    ) internal view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes32 messageHash = _getExecuteWithRelayerHash(batchedCall, validUntil, wallet);
        bytes32 hashToSign = merkleProofs.length > 0 ? MerkleProof.processProof(merkleProofs, messageHash) : messageHash;
        return abi.encodePacked(keyHash, validUntil, _signHash(privateKey, hashToSign), abi.encode(merkleProofs));
    }

    function _prepareAndSignUserOp(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        address wallet,
        uint48 validUntil
    ) internal view returns (bytes memory signature, bytes32 finalHash) {
        bytes32 baseHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(userOp);
        finalHash = _getValidateUserOpHash(userOp, baseHash, validUntil, wallet);
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        signature = abi.encodePacked(keyHash, validUntil, _signHash(privateKey, finalHash));
    }

    function _prepareAndSignUserOp(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        address wallet
    ) internal view returns (bytes memory signature, bytes32 finalHash) {
        return _prepareAndSignUserOp(userOp, signer, privateKey, wallet, uint48(0));
    }

    // ============ ValidateUserOp Helper Functions ============

    // Mimics the exact hash calculation in SmartWallet.validateUserOp
    function _getValidateUserOpHash(
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint48 validUntil,
        address wallet
    ) internal view returns (bytes32) {
        if (userOp.nonce >> 96 == Static.CHAINLESS_NONCE_KEY) {
            userOpHash = ERC4337Account(wallet).getUserOpHashWithoutChainId(userOp);
        }
        return
            MessageHashUtils.toEthSignedMessageHash(
                keccak256(abi.encode(userOpHash, validUntil, address(_smartWallet)))
            );
    }

    function _constructUserOpSignature(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        bytes32 userOpHash,
        uint48 validUntil,
        address wallet
    ) internal view returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes32 finalHash = _getValidateUserOpHash(userOp, userOpHash, validUntil, wallet);
        return abi.encodePacked(keyHash, validUntil, _signHash(privateKey, finalHash));
    }

    function _constructUserOpSignature(
        PackedUserOperation memory userOp,
        address signer,
        uint256 privateKey,
        bytes32 userOpHash,
        address wallet
    ) internal view returns (bytes memory) {
        return _constructUserOpSignature(userOp, signer, privateKey, userOpHash, uint48(0), wallet);
    }

    /// @dev Test-only encoder for OwnerManager's packed settings layout.
    ///      Production callers should construct the packed value off-chain.
    function _packSettings(bool adminFlag, uint40 expiration, address hook) internal pure returns (uint256) {
        return (adminFlag ? Static.ROOT_KEY_SETTINGS : 0) | (uint256(expiration) << 160) | uint256(uint160(hook));
    }

    // Helper function for tests to check if a signer is admin
    function _isSignerAdmin(address wallet, bytes32 keyHash) internal view returns (bool) {
        IOwnerManager manager = IOwnerManager(wallet);
        (, uint256 settings) = manager.getOwnerConfig(keyHash);
        return manager.isAdmin(settings);
    }

    // Helper function to test validateUserOp from EntryPoint's perspective
    function _testValidateUserOp(
        address account,
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) internal returns (uint256) {
        vm.prank(ENTRYPOINT_ADDRESS);
        return IAccount(account).validateUserOp(userOp, userOpHash, missingAccountFunds);
    }

    /// @notice Simplified version that auto-calculates the hash
    /// @dev Automatically handles EntryPoint hash calculation
    function _testValidateUserOp(address account, PackedUserOperation memory userOp, uint256 missingAccountFunds)
        internal
        returns (uint256)
    {
        // Get the hash that EntryPoint would calculate
        bytes32 userOpHash = IEntryPoint(ENTRYPOINT_ADDRESS).getUserOpHash(userOp);

        vm.prank(ENTRYPOINT_ADDRESS);
        return IAccount(account).validateUserOp(userOp, userOpHash, missingAccountFunds);
    }

    // Helper function for tests to check if a signer is expired
    function _isSignerExpired(address wallet, bytes32 keyHash) internal view returns (bool) {
        IOwnerManager manager = IOwnerManager(wallet);
        (address validator, ) = manager.getOwnerConfig(keyHash);
        return manager.hasOwner(keyHash) && validator == address(0);
    }

    // Helper function for tests to get signer expiration
    function _getSignerExpiration(address wallet, bytes32 keyHash) internal view returns (uint40) {
        IOwnerManager manager = IOwnerManager(wallet);
        (, uint256 settings) = manager.getOwnerConfig(keyHash);
        return manager.getExpiration(settings);
    }

    function _getOwnerSettings(address wallet, bytes32 keyHash) internal view returns (uint256 settings) {
        (, settings) = IOwnerManager(wallet).getOwnerConfig(keyHash);
    }

    // Helper function to call removeValidator through executeWithRelayer
    function _executeRemoveValidator(address wallet, bytes32 keyHash) internal {
        Call[] memory calls = new Call[](1);
        calls[0] =
            Call({target: wallet, value: 0, data: abi.encodeWithSelector(OwnerManager.removeOwner.selector, keyHash)});

        // Create BatchedCall for relayer execution
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: _getNonce(wallet)});

        // Sign with alice's private key (as the authorized owner)
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        uint48 validUntil = 0; // No expiry

        bytes32 intentHash = batchedCall.hash(validUntil, _smartWallet.IMPLEMENTATION());
        bytes32 typedDataHash = ERC712(wallet).hashTypedData(intentHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory validatorData = abi.encodePacked(aliceKeyHash, validUntil, signature);

        // Use relayer to execute the transaction
        vm.prank(relayer);
        ISmartWallet(wallet).executeWithRelayer(batchedCall, validatorData);
    }
}
