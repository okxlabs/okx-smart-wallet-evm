// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base, MockERC20} from "./Base.t.sol";
import {ITransferWithAuthorization} from "src/interfaces/ITransferWithAuthorization.sol";
import {TransferWithAuthorization} from "src/TransferWithAuthorization.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Static} from "src/libraries/Static.sol";

contract TransferWithAuthorizationHandler is Base {
    ITransferWithAuthorization internal itwa;
    TransferWithAuthorization internal twa;
    MockERC20 internal token;

    address internal recipientOne;
    address internal recipientTwo;
    address internal recipientThree;
    address internal relayerOne;
    address internal relayerTwo;

    bytes32[8] internal trackedNonces;
    mapping(bytes32 ownerKeyHash => mapping(bytes32 nonce => uint256)) public settleSuccesses;
    mapping(bytes32 ownerKeyHash => mapping(bytes32 nonce => uint256)) public cancelSuccesses;
    bytes32 internal signingKeyHash;
    uint256 internal signingPrivateKey;
    uint256 public successfulSettles;
    uint256 public successfulCancels;
    uint256 public tokenOut;

    uint256 internal initialWalletTokenBalance;
    uint256 internal initialRecipientTokenBalance;

    function setUp() public override {
        super.setUp();
        vm.warp(10_000);

        itwa = ITransferWithAuthorization(_aliceWallet);
        twa = TransferWithAuthorization(payable(_aliceWallet));
        token = new MockERC20();
        token.mint(_aliceWallet, 1_000 ether);
        _addOwnerToAccount(_alice, _aliceWallet, keccak256(abi.encodePacked(_bob)), Static.ECDSA_VALIDATOR_ADDRESS, 0);

        recipientOne = makeAddr("twa invariant recipient one");
        recipientTwo = makeAddr("twa invariant recipient two");
        recipientThree = makeAddr("twa invariant recipient three");
        relayerOne = makeAddr("twa invariant relayer one");
        relayerTwo = makeAddr("twa invariant relayer two");

        for (uint256 i; i < trackedNonces.length; i++) {
            trackedNonces[i] = keccak256(abi.encode("tracked-twa-nonce", i));
        }

        initialWalletTokenBalance = token.balanceOf(_aliceWallet);
        initialRecipientTokenBalance =
            token.balanceOf(recipientOne) + token.balanceOf(recipientTwo) + token.balanceOf(recipientThree);
    }

    function execute(uint256 ownerSeed, uint256 nonceSeed, uint96 amountSeed, uint256 recipientSeed, uint256 relayerSeed) external {
        _selectOwner(ownerSeed);
        bytes32 nonce = _nonce(nonceSeed);
        address to = _recipient(recipientSeed);
        address caller = _relayer(relayerSeed);
        uint256 value = bound(uint256(amountSeed), 0, 20 ether);
        if (value > token.balanceOf(_aliceWallet)) {
            value = token.balanceOf(_aliceWallet);
        }
        bytes memory sig = _executeSignature(address(token), to, value, nonce);

        vm.prank(caller);
        try itwa.executeTransferWithAuthorization(address(token), to, value, 9_000, 11_000, nonce, sig) {
            settleSuccesses[signingKeyHash][nonce]++;
            successfulSettles++;
            tokenOut += value;
        } catch {}
    }

    function receiveByPayee(uint256 ownerSeed, uint256 nonceSeed, uint96 amountSeed, uint256 recipientSeed) external {
        _selectOwner(ownerSeed);
        bytes32 nonce = _nonce(nonceSeed);
        address to = _recipient(recipientSeed);
        uint256 value = bound(uint256(amountSeed), 0, 20 ether);
        if (value > token.balanceOf(_aliceWallet)) {
            value = token.balanceOf(_aliceWallet);
        }
        bytes memory sig = _receiveSignature(address(token), to, value, nonce);

        vm.prank(to);
        try itwa.receiveWithAuthorization(address(token), to, value, 9_000, 11_000, nonce, sig) {
            settleSuccesses[signingKeyHash][nonce]++;
            successfulSettles++;
            tokenOut += value;
        } catch {}
    }

    function cancel(uint256 ownerSeed, uint256 nonceSeed, uint256 relayerSeed) external {
        _selectOwner(ownerSeed);
        bytes32 nonce = _nonce(nonceSeed);
        bytes memory sig = _cancelSignature(nonce);

        vm.prank(_relayer(relayerSeed));
        try itwa.cancelTransferAuthorization(signingKeyHash, nonce, sig) {
            cancelSuccesses[signingKeyHash][nonce]++;
            successfulCancels++;
        } catch {}
    }

    function replayExecute(uint256 ownerSeed, uint256 nonceSeed, uint256 relayerSeed) external {
        _selectOwner(ownerSeed);
        bytes32 nonce = _nonce(nonceSeed);
        bytes memory sig = _executeSignature(address(token), recipientOne, 1 ether, nonce);

        vm.prank(_relayer(relayerSeed));
        try itwa.executeTransferWithAuthorization(address(token), recipientOne, 1 ether, 9_000, 11_000, nonce, sig) {
            settleSuccesses[signingKeyHash][nonce]++;
            successfulSettles++;
            tokenOut += 1 ether;
        } catch {}
    }

    function trackedNonce(uint256 index) external view returns (bytes32) {
        return trackedNonces[index];
    }

    function trackedNonceCount() external pure returns (uint256) {
        return 8;
    }

    function wallet() external view returns (address payable) {
        return _aliceWallet;
    }

    function trackedOwner(uint256 index) public view returns (bytes32) {
        return index == 0 ? _aliceWalletKeyHash : keccak256(abi.encodePacked(_bob));
    }

    function _selectOwner(uint256 seed) internal {
        uint256 index = seed % 2;
        signingKeyHash = trackedOwner(index);
        signingPrivateKey = index == 0 ? _alicePk : _bobPk;
    }

    function walletTokenBalance() external view returns (uint256) {
        return token.balanceOf(_aliceWallet);
    }

    function recipientTokenBalanceSum() external view returns (uint256) {
        return token.balanceOf(recipientOne) + token.balanceOf(recipientTwo) + token.balanceOf(recipientThree);
    }

    function initialWalletBalance() external view returns (uint256) {
        return initialWalletTokenBalance;
    }

    function initialRecipientBalanceSum() external view returns (uint256) {
        return initialRecipientTokenBalance;
    }

    function accountNonce() external view returns (uint64) {
        return INonceManager(_aliceWallet).getNonce(uint192(0));
    }

    function _nonce(uint256 seed) internal view returns (bytes32) {
        return trackedNonces[bound(seed, 0, trackedNonces.length - 1)];
    }

    function _recipient(uint256 seed) internal view returns (address) {
        uint256 idx = bound(seed, 0, 2);
        if (idx == 0) return recipientOne;
        if (idx == 1) return recipientTwo;
        return recipientThree;
    }

    function _relayer(uint256 seed) internal view returns (address) {
        return bound(seed, 0, 1) == 0 ? relayerOne : relayerTwo;
    }

    function _transferStructHash(bytes32 typeHash, address tkn, address to, uint256 value, bytes32 nonce)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(typeHash, tkn, _aliceWallet, to, value, uint256(9_000), uint256(11_000), nonce));
    }

    function _executeSignature(address tkn, address to, uint256 value, bytes32 nonce)
        internal
        view
        returns (bytes memory)
    {
        return _envelope(
            _transferStructHash(
                keccak256(
                    "ExecuteTransferWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
                ),
                tkn,
                to,
                value,
                nonce
            )
        );
    }

    function _receiveSignature(address tkn, address to, uint256 value, bytes32 nonce)
        internal
        view
        returns (bytes memory)
    {
        return _envelope(
            _transferStructHash(
                keccak256(
                    "ReceiveWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
                ),
                tkn,
                to,
                value,
                nonce
            )
        );
    }

    function _cancelSignature(bytes32 nonce) internal view returns (bytes memory) {
        bytes32 typeHash =
            keccak256("CancelTransferAuthorization(bytes32 targetKeyHash,bytes32 authorizationNonce)");
        return _envelope(keccak256(abi.encode(typeHash, signingKeyHash, nonce)));
    }

    function _envelope(bytes32 structHash) internal view returns (bytes memory) {
        bytes32 boundHash =
            keccak256(abi.encode(structHash, signingKeyHash, ISmartWallet(_aliceWallet).IMPLEMENTATION()));
        bytes32 digest = twa.hashTypedData(boundHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingPrivateKey, digest);
        return abi.encodePacked(signingKeyHash, r, s, v);
    }
}

contract TransferWithAuthorizationInvariantTest is Base {
    TransferWithAuthorizationHandler internal handler;
    ITransferWithAuthorization internal itwa;

    function setUp() public override {
        handler = new TransferWithAuthorizationHandler();
        vm.deal(address(handler), 1 ether);
        handler.setUp();
        itwa = ITransferWithAuthorization(handler.wallet());

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TransferWithAuthorizationHandler.execute.selector;
        selectors[1] = TransferWithAuthorizationHandler.receiveByPayee.selector;
        selectors[2] = TransferWithAuthorizationHandler.cancel.selector;
        selectors[3] = TransferWithAuthorizationHandler.replayExecute.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_nonceSettlesAtMostOncePerOwnerAndNonce() public view {
        uint256 count = handler.trackedNonceCount();
        for (uint256 i; i < count; i++) {
            bytes32 nonce = handler.trackedNonce(i);
            for (uint256 j; j < 2; j++) {
                bytes32 ownerKeyHash = handler.trackedOwner(j);
                uint256 terminalTransitions = handler.settleSuccesses(ownerKeyHash, nonce) + handler.cancelSuccesses(ownerKeyHash, nonce);
                assertLe(terminalTransitions, 1, "owner nonce terminal transition count");
                assertEq(itwa.transferAuthorizationState(ownerKeyHash, nonce), terminalTransitions == 1, "owner-scoped terminal state");
            }
        }
    }

    function invariant_tokenAccountingConservedAcrossSuccessfulSettles() public view {
        uint256 currentWallet = handler.walletTokenBalance();
        uint256 currentRecipients = handler.recipientTokenBalanceSum();
        assertEq(
            handler.initialWalletBalance(), currentWallet + handler.tokenOut(), "wallet debit equals recorded outflow"
        );
        assertEq(
            currentRecipients,
            handler.initialRecipientBalanceSum() + handler.tokenOut(),
            "recipient credit equals recorded outflow"
        );
    }

    function invariant_twaDoesNotAdvanceNativeNonceSpace() public view {
        assertEq(handler.accountNonce(), 0, "native account nonce unchanged");
    }
}
