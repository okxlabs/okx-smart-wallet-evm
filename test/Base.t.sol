// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
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
contract Base is Test {
    string public constant NAME = "wallet-core";
    string public constant VERSION = "1.0.0";

    address internal _alice;
    uint256 internal _alicePk;
    address internal _bob;
    uint256 internal _bobPk;
    ECDSAValidator internal _ecdsaValidator; // Shared validator instance
    WalletCore internal _walletCore;
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
        (_alice, _alicePk) = makeAddrAndKey("alice");
        (_bob, _bobPk) = makeAddrAndKey("bob");

        deployFactory = new DeployFactory();
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        (_ecdsaValidator, _walletCore) = DeployInitHelper.deployContracts(
            deployFactory,
            deployFactorySalt,
            NAME,
            VERSION
        );

        _setCodeToEOA(address(_walletCore), _alice);

        deal(_alice, 10 ether);

        // Alice initializes the account
        vm.prank(_alice);
        // Initialize with empty owners array to allow tests to add validators as needed
        InitialOwner[] memory initialOwners = new InitialOwner[](0);
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
            ValidationLogic(_alice).getValidationTypedHash(
                BatchedCall({calls: calls, nonce: nonce, expiry: 0})
            );
    }

    function _getValidationTypedHash(
        address account,
        Call[] memory calls
    ) internal view returns (bytes32) {
        uint256 nonce = _getNonce(account);
        return
            ValidationLogic(account).getValidationTypedHash(
                BatchedCall({calls: calls, nonce: nonce, expiry: 0})
            );
    }

    function _getValidationTypedHashWithNonce(
        address account,
        uint256 nonce,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return
            ValidationLogic(account).getValidationTypedHash(
                BatchedCall({calls: calls, nonce: nonce, expiry: 0})
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

        vm.prank(signer);
        IOwnersManager(signer).addValidator(
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

        vm.prank(account);
        IOwnersManager(account).addValidator(
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

    // Helper function for tests to check if a signer is admin
    function isSignerAdmin(address wallet, bytes32 keyHash) internal view returns (bool) {
        uint256 settings = IOwnersManager(wallet).ownerSettings(keyHash);
        return settings != 0 && IOwnersManager(wallet).isAdmin(settings);
    }
    
    // Helper function for tests to check if a signer is expired  
    function isSignerExpired(address wallet, bytes32 keyHash) internal view returns (bool) {
        uint256 settings = IOwnersManager(wallet).ownerSettings(keyHash);
        return settings != 0 && IOwnersManager(wallet).isSettingsExpired(settings);
    }
    
    // Helper function for tests to get signer expiration
    function getSignerExpiration(address wallet, bytes32 keyHash) internal view returns (uint40) {
        uint256 settings = IOwnersManager(wallet).ownerSettings(keyHash);
        return settings != 0 ? IOwnersManager(wallet).getExpiration(settings) : 0;
    }
}
