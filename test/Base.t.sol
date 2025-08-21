// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {OwnersManager} from "src/OwnersManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {IWalletCore} from "src/interfaces/IWalletCore.sol";
import {IValidation} from "src/interfaces/IValidation.sol";
import {IValidator} from "src/interfaces/IValidator.sol";
import {ValidationLogic} from "src/ValidationLogic.sol";
import {WalletCore} from "src/WalletCore.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {DeployInitHelper, DeployFactory} from "scripts/DeployInitHelper.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Static} from "src/libraries/Static.sol";
import {BatchedCallLib} from "src/libraries/BatchedCallLib.sol";
import {ERC712} from "src/ERC712.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";

contract Base is Test {
    string public constant NAME = "SmartWallet";
    string public constant VERSION = "1.0.0";

    address payable internal _alice;
    uint256 internal _alicePk;
    address internal _bob;
    uint256 internal _bobPk;
    ECDSAValidator internal _ecdsaValidator; // Shared validator instance
    WalletCore internal _walletCore;
    SmartWalletFactory internal _factory;
    DeployFactory public deployFactory;
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
        (address aliceAddr, uint256 alicePk) = makeAddrAndKey("alice");

        // Make _alice payable so we can cast to WalletCore (which has payable fallback functions) in relevant unit tests 
        _alice = payable(aliceAddr);
        _alicePk = alicePk;
        (_bob, _bobPk) = makeAddrAndKey("bob");

        deployFactory = new DeployFactory();
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        (_ecdsaValidator, _walletCore, _factory) = DeployInitHelper
            .deployContracts(deployFactory, deployFactorySalt);

        _setCodeToEOA(address(_walletCore), _alice);

        deal(_alice, 10 ether);

        // Alice initializes the account with herself as admin
        vm.prank(_alice);
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });
        IWalletCore(_alice).initialize(initialOwners);
        vm.stopPrank();
    }

    function _setCodeToEOA(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
    }

    function _construct_signature(
        address account,
        uint256 signerPk,
        Call[] memory calls
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHash(account, calls);
        return _signHash(signerPk, hash);
    }

    function _construct_signature(
        uint256 nonce,
        uint256 signerPk,
        Call[] memory calls
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHash(nonce, calls);
        return _signHash(signerPk, hash);
    }

    function _construct_signature_with_nonce(
        uint256 nonce,
        address account,
        uint256 signerPk,
        Call[] memory calls
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHashWithNonce(account, nonce, calls);
        return _signHash(signerPk, hash);
    }

    function _construct_calls_data() public view returns (Call[] memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: _bob, value: 1 ether, data: ""});
        return calls;
    }

    function _construct_erc20_transfer_call(
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
                    BatchedCall({calls: calls, nonce: nonce, expiry: 0})
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
                    BatchedCall({calls: calls, nonce: nonce, expiry: 0})
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
                    BatchedCall({calls: calls, nonce: nonce, expiry: 0})
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

    function _addValidator(address signer) internal returns (address) {
        // Use the signer's address as the keyHash for testing
        bytes32 keyHash = keccak256(abi.encodePacked(signer));

        // Check if validator already exists (alice is initialized with a validator)
        if (IOwnersManager(signer).hasOwner(keyHash)) {
            return address(_ecdsaValidator);
        }

        _executeAddValidator(
            signer,
            keyHash,
            address(_ecdsaValidator),
            false,
            0,
            address(0)
        );

        return address(_ecdsaValidator);
    }

    function _addValidator(
        address account,
        address signer
    ) internal returns (address) {
        // Use the signer's address as the keyHash for testing
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

    function _construct_relayer_call(
        uint256 len,
        IERC20 token
    ) internal view returns (Call[] memory calls) {
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            calls[i] = _construct_erc20_transfer_call(token, _alice, 100);
        }
    }

    function _get_execution_gas(
        uint256 callSize
    ) internal pure returns (uint256) {
        return 31532 + 2210 * callSize + 25160 * callSize;
    }

    function _construct_signature(
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _construct_validatorData(
        address /* wallet */,
        address signer,
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = _construct_signature(privateKey, hash);
        return abi.encodePacked(keyHash, signature);
    }

    function _construct_validatorData(
        address signer,
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        return _construct_validatorData(signer, signer, privateKey, hash);
    }

    function _construct_validatorData(
        address signer,
        uint256 privateKey,
        bytes32 hash,
        uint64 /* nonce */
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = _construct_signature(privateKey, hash);
        return abi.encodePacked(keyHash, signature);
    }

    function _construct_signature(
        BatchedCall memory batchedCall,
        address account,
        uint256 signerPk
    ) public view returns (bytes memory) {
        bytes32 hash = ERC712(account).hashTypedData(
            BatchedCallLib.hash(batchedCall)
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
            settings
        );
    }

    // Helper function to call addValidator with pre-packed settings
    function _executeAddValidatorWithSettings(
        address wallet,
        bytes32 keyHash,
        address validatorAddr,
        uint256 settings
    ) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: wallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.addValidator.selector,
                keyHash,
                validatorAddr,
                settings
            )
        });

        vm.prank(wallet);
        IWalletCore(wallet).execute(calls);
    }

    // Helper function to call removeValidator through execute
    function _executeRemoveValidator(address wallet, bytes32 keyHash) internal {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: wallet,
            value: 0,
            data: abi.encodeWithSelector(
                OwnersManager.removeValidator.selector,
                keyHash
            )
        });

        vm.prank(wallet);
        IWalletCore(wallet).execute(calls);
    }
}
