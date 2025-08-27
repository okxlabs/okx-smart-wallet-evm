// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {OKXSmartWalletEntry} from "src/OKXSmartWalletEntry.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {PasskeyValidator} from "src/validator/PasskeyValidator.sol";
import {Helper} from "src/test/Helper.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {DeployInitHelper, DeployFactory} from "scripts/DeployInitHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IAccount} from "account-abstraction/interfaces/IAccount.sol";

contract Base is Test {
    string public constant NAME = "SmartWallet";
    string public constant VERSION = "1.0.0";

    // Standard EntryPoint address used in ERC-4337
    address constant ENTRYPOINT_ADDRESS =
        0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    address payable internal _alice; // Alice's smart wallet address
    address internal _aliceEOA; // Alice's original EOA address
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
    DeployFactory public deployFactory;
    EntryPoint internal _entryPoint; // EntryPoint instance
    address internal relayer;
    uint256 internal relayerPk;
    address internal validator;
    Call[] internal relayerCalls;
    Call[] internal emptyRelayerCalls;

    event ExecuteSuccessEvent(
        bytes32 indexed callHash,
        address sender,
        uint256 nonce
    );

    function setUp() public virtual {
        (_aliceEOA, _alicePk) = makeAddrAndKey("alice");
        (_bob, _bobPk) = makeAddrAndKey("bob");

        // Deploy EntryPoint and place it at the standard address
        _entryPoint = new EntryPoint();
        vm.etch(ENTRYPOINT_ADDRESS, address(_entryPoint).code);
        vm.deal(ENTRYPOINT_ADDRESS, 100 ether); // Fund EntryPoint for gas payments

        // Generated real P256 signature using SmartAccount method (crypto.createSign compatibility)
        _passkeyPubX = 0xac3363644e2570764491a4ef772d7a2df4322a6f6830330baa85f2bf5edf4cb1;
        _passkeyPubY = 0x293e49491e2b881d16d17aa6cacee25feccbfb74acce4ff15402f09c2ee9f9f5;
        _passkeyPrivateKey = 0x305cfeb0eecbb0cdb260b8c93b0f9b1f812d601261c135fce04bb8de6a310f0f;
        // Deploy Factory
        deployFactory = new DeployFactory();
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        Helper helper;
        (
            _ecdsaValidator,
            _passkeyValidator,
            _smartWallet,
            _factory,
            helper
        ) = DeployInitHelper.deployContracts(deployFactory, deployFactorySalt);

        // Use factory to create a wallet for Alice instead of _setCodeToEOA
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_aliceEOA)),
            validator: address(_ecdsaValidator)
        });

        // Create wallet using factory with deterministic address
        _alice = payable(
            _factory.createAccount(
                address(_smartWallet),
                initialOwners,
                0 // salt
            )
        );

        deal(_alice, 10 ether);
    }

    function _setCodeToEOA(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
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

    function _getValidationTypedHash(
        uint256 nonce,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return
            ERC712(_alice).hashTypedData(
                BatchedCallLib.hash(
                    BatchedCall({calls: calls, nonce: nonce, expiry: 0}),
                    address(_smartWallet)
                )
            );
    }

    function _getValidationTypedHash(
        address account,
        Call[] memory calls
    ) internal view returns (bytes32) {
        uint256 nonce = _getNonce(account);
        return
            ERC712(account).hashTypedData(
                BatchedCallLib.hash(
                    BatchedCall({calls: calls, nonce: nonce, expiry: 0}),
                    address(_smartWallet)
                )
            );
    }

    function _getValidationTypedHashWithNonce(
        address account,
        uint256 nonce,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return
            ERC712(account).hashTypedData(
                BatchedCallLib.hash(
                    BatchedCall({calls: calls, nonce: nonce, expiry: 0}),
                    address(_smartWallet)
                )
            );
    }

    function _signHash(
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _addValidator(
        address account,
        address signer
    ) internal returns (address) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        // Check if validator already exists
        if (IOwnersManager(account).hasOwner(keyHash)) {
            return address(_ecdsaValidator);
        }

        _executeAddValidator(
            account,
            keyHash,
            address(_ecdsaValidator),
            false,
            0,
            address(0)
        );

        return address(_ecdsaValidator);
    }

    function constructRelayerCall(
        uint256 len,
        IERC20 token
    ) internal view returns (Call[] memory calls) {
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            calls[i] = constructErc20TransferCall(token, _alice, 100);
        }
    }

    function getExecutionGas(uint256 callSize) internal pure returns (uint256) {
        return 31532 + 2210 * callSize + 25160 * callSize;
    }

    function constructSignature(
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function constructValidatorData(
        address, // wallet (unused)
        address signer,
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = constructSignature(privateKey, hash);
        return abi.encodePacked(keyHash, signature);
    }

    function constructValidatorData(
        address signer,
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        return constructValidatorData(signer, signer, privateKey, hash);
    }

    function constructValidatorData(
        address signer,
        uint256 privateKey,
        bytes32 hash,
        uint64 /* nonce */
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = constructSignature(privateKey, hash);
        return abi.encodePacked(keyHash, signature);
    }

    function constructSignature(
        BatchedCall memory batchedCall,
        address account,
        uint256 signerPk
    ) public view returns (bytes memory) {
        bytes32 hash = ERC712(account).hashTypedData(
            BatchedCallLib.hash(batchedCall, address(_smartWallet))
        );
        address signer = vm.addr(signerPk);
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = _signHash(signerPk, hash);
        return abi.encodePacked(keyHash, signature);
    }

    // Helper function for tests to check if a signer is admin
    function isSignerAdmin(
        address wallet,
        bytes32 keyHash
    ) internal view returns (bool) {
        uint256 settings = IOwnersManager(wallet).ownerSettings(keyHash);
        return settings != 0 && IOwnersManager(wallet).isAdmin(settings);
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

    // Helper function for tests to check if a signer is expired
    function isSignerExpired(
        address wallet,
        bytes32 keyHash
    ) internal view returns (bool) {
        uint256 settings = IOwnersManager(wallet).ownerSettings(keyHash);
        return
            settings != 0 && IOwnersManager(wallet).isSettingsExpired(settings);
    }

    // Helper function for tests to get signer expiration
    function getSignerExpiration(
        address wallet,
        bytes32 keyHash
    ) internal view returns (uint40) {
        uint256 settings = IOwnersManager(wallet).ownerSettings(keyHash);
        return
            settings != 0 ? IOwnersManager(wallet).getExpiration(settings) : 0;
    }

    // Helper function to call addValidator through execute
    function _executeAddValidator(
        address wallet,
        bytes32 keyHash,
        address validatorAddr,
        bool adminFlag,
        uint40 expiration,
        address hook
    ) internal {
        // Get packed settings before any potential revert expectations are set
        uint256 settings = OwnersManager(wallet).packSettings(
            adminFlag,
            expiration,
            hook
        );
        _executeAddValidatorWithSettings(
            wallet,
            keyHash,
            validatorAddr,
            settings,
            IOwnersManager(wallet).sequence()
        );
    }

    // Helper function to call addValidator with pre-packed settings
    function _executeAddValidatorWithSettings(
        address wallet,
        bytes32 keyHash,
        address validatorAddr,
        uint256 settings,
        uint256 seq
    ) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: wallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addOwner.selector,
                keyHash,
                validatorAddr,
                settings,
                seq
            )
        });

        vm.prank(wallet);
        ISmartWallet(wallet).execute(calls);
    }

    // Helper function to call removeValidator through execute
    function _executeRemoveValidator(address wallet, bytes32 keyHash) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: wallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeOwner.selector,
                keyHash,
                IOwnersManager(wallet).sequence()
            )
        });

        vm.prank(wallet);
        ISmartWallet(wallet).execute(calls);
    }
}

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
}
