// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {IStorage} from "src/interfaces/IStorage.sol";
import {IWalletCore} from "src/interfaces/IWalletCore.sol";
import {IValidation} from "src/interfaces/IValidation.sol";
import {IValidator} from "src/interfaces/IValidator.sol";
import {ValidationLogic} from "src/ValidationLogic.sol";
import {WalletCore} from "src/WalletCore.sol";
import {ECDSAValidator} from "src/validator/ECDSAValidator.sol";
import {Call} from "src/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {DeployInitHelper, DeployFactory} from "scripts/DeployInitHelper.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Static} from "src/libraries/Static.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract Base is Test {
    using Clones for address;

    string public constant NAME = "wallet-core";
    string public constant VERSION = "1.0.0";

    address internal _alice;
    uint256 internal _alicePk;
    address internal _bob;
    uint256 internal _bobPk;
    IStorage internal _storageImpl;
    ECDSAValidator internal _ecdsaValidatorImpl;
    WalletCore internal _walletCore;
    DeployFactory public deployFactory;
    address internal relayer;
    uint256 internal relayerPk;
    address internal validator;
    bytes32 constant _STORAGE_SALT = Static.STORAGE_SALT;
    Call[] internal relayerCalls;
    Call[] internal emptyRelayerCalls;

    function setUp() public virtual {
        (_alice, _alicePk) = makeAddrAndKey("alice");
        (_bob, _bobPk) = makeAddrAndKey("bob");

        deployFactory = new DeployFactory();
        bytes32 deployFactorySalt = vm.envBytes32("DEPLOY_FACTORY_SALT");

        (_storageImpl, _ecdsaValidatorImpl, _walletCore) = DeployInitHelper
            .deployContracts(deployFactory, deployFactorySalt, NAME, VERSION);

        _setCodeToEOA(address(_walletCore), _alice);

        deal(_alice, 10 ether);

        // Alice initializes the account
        vm.prank(_alice);
        IWalletCore(_alice).initialize();
        vm.stopPrank();
    }

    function _getEdcsaValidatorAddress(
        address eoa,
        address signer,
        address validatorImpl
    ) internal view returns (address) {
        bytes memory initCode = abi.encode(signer);
        return
            IValidation(eoa).computeValidatorAddress(validatorImpl, initCode);
    }

    function _setCodeToEOA(address contractCode, address eoa) internal {
        bytes memory code = address(contractCode).code;
        vm.etch(eoa, code);
    }

    function _construct_signature(
        address account,
        uint256 signerPk,
        Call[] memory _relayerCalls,
        Call[] memory calls,
        uint256 executionGas
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHash(
            account,
            _relayerCalls,
            calls,
            executionGas
        );
        return _signHash(signerPk, hash);
    }

    function _construct_signature(
        uint256 nonce,
        uint256 signerPk,
        Call[] memory _relayerCalls,
        Call[] memory calls,
        uint256 executionGas
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHash(
            nonce,
            executionGas,
            _relayerCalls,
            calls
        );
        return _signHash(signerPk, hash);
    }

    function _construct_signature_with_nonce(
        uint256 nonce,
        address account,
        uint256 signerPk,
        Call[] memory _relayerCalls,
        Call[] memory calls,
        uint256 executionGas
    ) public view returns (bytes memory) {
        bytes32 hash = _getValidationTypedHashWithNonce(
            account,
            nonce,
            executionGas,
            _relayerCalls,
            calls
        );
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
        return
            IStorage(WalletCore(payable(account)).getMainStorage()).getNonce();
    }

    function _getValidationTypedHash(
        uint256 nonce,
        uint256 executionGas,
        Call[] memory _relayerCalls,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return ValidationLogic(_alice).getValidationTypedHash(nonce, calls);
    }

    function _getValidationTypedHash(
        address account,
        Call[] memory _relayerCalls,
        Call[] memory calls,
        uint256 executionGas
    ) internal view returns (bytes32) {
        uint256 nonce = _getNonce(account);
        return ValidationLogic(account).getValidationTypedHash(nonce, calls);
    }

    function _getValidationTypedHashWithNonce(
        address account,
        uint256 nonce,
        uint256 executionGas,
        Call[] memory _relayerCalls,
        Call[] memory calls
    ) internal view returns (bytes32) {
        return ValidationLogic(account).getValidationTypedHash(nonce, calls);
    }

    function _signHash(
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _addValidator(address signer) internal returns (address) {
        // Validator signer
        bytes memory initCode = abi.encode(signer);

        // Compute validator address
        address validatorAddress = _getEdcsaValidatorAddress(
            signer,
            signer,
            address(_ecdsaValidatorImpl)
        );

        // Add validator with keyHash (use signer address as keyHash for testing)
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        vm.startPrank(signer);

        // Deploy the validator using Clones if it doesn't exist yet
        if (validatorAddress.code.length == 0) {
            address(_ecdsaValidatorImpl).cloneDeterministicWithImmutableArgs(
                initCode,
                Static.VALIDATOR_SALT
            );
        }

        IWalletCore(signer).addValidator(keyHash, validatorAddress);
        vm.stopPrank();

        return validatorAddress;
    }

    function _addValidator(
        address account,
        address signer
    ) internal returns (address) {
        // Validator signer
        bytes memory initCode = abi.encode(signer);

        // Compute validator address
        address validatorAddress = _getEdcsaValidatorAddress(
            account,
            signer,
            address(_ecdsaValidatorImpl)
        );

        // Add validator with keyHash (use signer address as keyHash for testing)
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        vm.startPrank(account);

        // Deploy the validator using Clones if it doesn't exist yet
        if (validatorAddress.code.length == 0) {
            address(_ecdsaValidatorImpl).cloneDeterministicWithImmutableArgs(
                initCode,
                Static.VALIDATOR_SALT
            );
        }

        IWalletCore(account).addValidator(keyHash, validatorAddress);
        vm.stopPrank();

        return validatorAddress;
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
        address signer,
        uint256 privateKey,
        bytes32 hash
    ) internal pure returns (bytes memory) {
        bytes32 keyHash = keccak256(abi.encodePacked(signer));
        bytes memory signature = _construct_signature(privateKey, hash);
        return abi.encodePacked(keyHash, signature);
    }
}
