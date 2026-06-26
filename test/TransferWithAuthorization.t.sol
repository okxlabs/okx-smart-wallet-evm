// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base, MockERC20} from "./Base.t.sol";
import {ITransferWithAuthorization} from "src/interfaces/ITransferWithAuthorization.sol";
import {TransferWithAuthorization} from "src/TransferWithAuthorization.sol";
import {BaseAuthorization} from "src/BaseAuthorization.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {IHook} from "src/interfaces/IHook.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {Call} from "src/Types.sol";
import {MessageSignLib} from "src/libraries/MessageSignLib.sol";
import {PasskeyValidatorLib} from "src/libraries/PasskeyValidatorLib.sol";
import {Static} from "src/libraries/Static.sol";
import {HelperLib} from "./utils/Helper.s.sol";
import {WebAuthn} from "webauthn-sol/WebAuthn.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal hook that blocks any spend by reverting in preCheck. Used to prove the TWA settle path
///      invokes the key-selected hook and that a hook revert rolls back the consumed nonce.
contract RevertingHook is IHook {
    error HookBlocked();

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        revert HookBlocked();
    }

    function postCheck(bytes calldata, address) external payable {}
}

contract RecordingHook is IHook {
    uint256 public preCheckCount;
    uint256 public postCheckCount;
    address public lastTarget;
    uint256 public lastValue;
    bytes32 public lastDataHash;
    address public lastPreExecutor;
    address public lastPostExecutor;
    bytes32 public lastPostRetHash;

    function preCheck(Call[] calldata calls, address executor) external payable returns (bytes memory preCheckRet) {
        preCheckCount++;
        lastPreExecutor = executor;
        require(calls.length == 1, "unexpected call count");
        lastTarget = calls[0].target;
        lastValue = calls[0].value;
        lastDataHash = keccak256(calls[0].data);
        return abi.encode(lastTarget, lastValue, lastDataHash, executor);
    }

    function postCheck(bytes calldata preCheckRet, address executor) external payable {
        postCheckCount++;
        lastPostExecutor = executor;
        lastPostRetHash = keccak256(preCheckRet);
    }
}

contract FalseReturnERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract NoReturnERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract ReentrantNativeReceiver {
    ITransferWithAuthorization public immutable itwa;
    address public immutable token;
    address public immutable to;
    uint256 public immutable value;
    uint256 public immutable validAfter;
    uint256 public immutable validBefore;
    bytes32 public immutable nonce;
    bytes public signature;
    bool public attempted;
    bool public nestedSucceeded;

    constructor(
        ITransferWithAuthorization itwa_,
        address token_,
        address to_,
        uint256 value_,
        uint256 validAfter_,
        uint256 validBefore_,
        bytes32 nonce_,
        bytes memory signature_
    ) {
        itwa = itwa_;
        token = token_;
        to = to_;
        value = value_;
        validAfter = validAfter_;
        validBefore = validBefore_;
        nonce = nonce_;
        signature = signature_;
    }

    receive() external payable {
        if (attempted) return;
        attempted = true;
        (nestedSucceeded,) = address(itwa)
            .call(
                abi.encodeCall(
                    ITransferWithAuthorization.executeTransferWithAuthorization,
                    (token, to, value, validAfter, validBefore, nonce, signature)
                )
            );
    }
}

/// @title TransferWithAuthorization unit and fuzz tests
/// @notice Stage 5 coverage for the account-level TWA implementation.
contract TransferWithAuthorizationTest is Base {
    TransferWithAuthorization internal twa;
    ITransferWithAuthorization internal itwa;
    MockERC20 internal token;
    address internal _relayer;

    bytes32 internal _execTypeHash;
    bytes32 internal _receiveTypeHash;
    bytes32 internal _cancelTypeHash;
    address internal _nativeAsset;

    function setUp() public override {
        super.setUp();
        vm.warp(10_000); // stable timestamp for open-interval window checks

        twa = TransferWithAuthorization(payable(_aliceWallet));
        itwa = ITransferWithAuthorization(_aliceWallet);
        _relayer = makeAddr("relayer");

        _execTypeHash = twa.EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH();
        _receiveTypeHash = twa.RECEIVE_WITH_AUTHORIZATION_TYPEHASH();
        _cancelTypeHash = twa.CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH();
        _nativeAsset = twa.NATIVE_ASSET();

        token = new MockERC20();
        token.mint(_aliceWallet, 1_000 ether);
    }

    // ---------------------------------------------------------------- helpers

    function _structHash(
        bytes32 typeHash,
        address tkn,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(typeHash, tkn, _aliceWallet, to, value, validAfter, validBefore, nonce));
    }

    /// @dev Builds the on-chain envelope `keyHash(32) || r,s,v(65)` over the direct EIP-712 digest.
    function _envelope(uint256 signerPk, bytes32 keyHash, bytes32 structHash) internal view returns (bytes memory) {
        bytes32 digest = twa.hashTypedData(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(keyHash, r, s, v);
    }

    function _envelopeForDigest(uint256 signerPk, bytes32 keyHash, bytes32 digest)
        internal
        pure
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(keyHash, r, s, v);
    }

    function _executeSignature(
        uint256 signerPk,
        bytes32 keyHash,
        address tkn,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes memory) {
        return _envelope(signerPk, keyHash, _structHash(_execTypeHash, tkn, to, value, validAfter, validBefore, nonce));
    }

    function _cancelSignature(uint256 signerPk, bytes32 keyHash, bytes32 nonce) internal view returns (bytes memory) {
        return _envelope(signerPk, keyHash, keccak256(abi.encode(_cancelTypeHash, nonce)));
    }

    function _registerBuiltinPasskeyOwner() internal returns (bytes32 passkeyKeyHash) {
        passkeyKeyHash = keccak256(abi.encodePacked(_passkeyPubX, _passkeyPubY));
        _addOwnerToAccount(_alice, _aliceWallet, passkeyKeyHash, Static.PASSKEY_VALIDATOR_ADDRESS, 0);
    }

    function _passkeyOwnerSignature(bytes32 digest) internal view returns (bytes memory) {
        (,, bytes32 passkeyMessageHash) = HelperLib.getPasskeyMessageHash(digest);
        (bytes32 r, bytes32 s) = vm.signP256(_passkeyPrivateKey, passkeyMessageHash);
        WebAuthn.WebAuthnAuth memory auth = HelperLib.getWebAuthnAuth(digest, uint256(r), uint256(s));

        return abi.encodePacked(
            abi.encode(PasskeyValidatorLib.PasskeyPubKey({pubKeyX: _passkeyPubX, pubKeyY: _passkeyPubY})),
            abi.encode(auth, new bytes32[](0))
        );
    }

    function _passkeyEnvelope(bytes32 keyHash, bytes32 structHash) internal view returns (bytes memory) {
        return abi.encodePacked(keyHash, _passkeyOwnerSignature(twa.hashTypedData(structHash)));
    }

    // ---------------------------------------------------------------- discovery / getters

    function test_publicConstants_matchDesign() public view {
        assertEq(
            twa.EXECUTE_TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
            0xe751bf1b144414a77b82ede1d2a433edc347fef283ab5e53e96f438392517b3c,
            "execute typehash"
        );
        assertEq(
            twa.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
            0xd8a04c474fcb45b6fb4b17a80506c180af4818903f1ace6c1ff59053338529fd,
            "receive typehash"
        );
        assertEq(
            twa.CANCEL_TRANSFER_AUTHORIZATION_TYPEHASH(),
            0xf30be15aedf9b01d0dac5525241af3753865a4968ffb9fb1a7ad6d2553d29f8e,
            "cancel typehash"
        );
        assertEq(twa.INTERFACE_ID(), bytes4(0x86c5a9e1), "interface id");
        assertEq(twa.NATIVE_ASSET(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, "native sentinel");
        assertEq(twa.SIGNATURE_ENVELOPE_MIN_LENGTH(), 32, "envelope prefix length");
    }

    function test_supportsInterface() public view {
        assertTrue(IERC165(_aliceWallet).supportsInterface(twa.INTERFACE_ID()), "TWA id");
        assertTrue(IERC165(_aliceWallet).supportsInterface(0x01ffc9a7), "ERC165 id preserved");
        assertTrue(IERC165(_aliceWallet).supportsInterface(0x1626ba7e), "ERC1271 id preserved");
        assertFalse(IERC165(_aliceWallet).supportsInterface(0xffffffff), "unknown id");
    }

    function test_domainSeparatorGetterMatchesDigest() public view {
        bytes32 sep = itwa.TRANSFER_AUTHORIZATION_DOMAIN_SEPARATOR();
        assertTrue(sep != bytes32(0), "non-zero domain separator");
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, 1, 9_000, 11_000, keccak256("x"));
        // hashTypedData == keccak256(0x1901 || domainSeparator || structHash)
        assertEq(twa.hashTypedData(sh), keccak256(abi.encodePacked(hex"1901", sep, sh)), "domain separator wired");
    }

    function test_transferAuthorizationState_unusedFalse() public view {
        assertFalse(itwa.transferAuthorizationState(keccak256("unused")), "unused nonce is false");
    }

    // ---------------------------------------------------------------- happy paths

    function test_executeErc20_happy() public {
        bytes32 nonce = keccak256("erc20");
        uint256 value = 25 ether;
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        uint256 balBefore = token.balanceOf(_bob);

        vm.expectEmit(true, true, true, true, _aliceWallet);
        emit ITransferWithAuthorization.TransferAuthorizationUsed(address(token), _aliceWallet, _bob, value, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);

        assertEq(token.balanceOf(_bob) - balBefore, value, "erc20 received");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_executeNative_happy() public {
        bytes32 nonce = keccak256("native");
        uint256 value = 1 ether;
        bytes32 sh = _structHash(_execTypeHash, _nativeAsset, _bob, value, 9_000, 11_000, nonce); // token == NATIVE_ASSET
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        uint256 balBefore = _bob.balance;
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(_nativeAsset, _bob, value, 9_000, 11_000, nonce, sig);

        assertEq(_bob.balance - balBefore, value, "native received");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_noReturnToken_settlesViaSafeERC20() public {
        NoReturnERC20 noReturnToken = new NoReturnERC20();
        noReturnToken.mint(_aliceWallet, 100 ether);

        bytes32 nonce = keccak256("no-return");
        uint256 value = 12 ether;
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(noReturnToken), _bob, value, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(noReturnToken), _bob, value, 9_000, 11_000, nonce, sig);

        assertEq(noReturnToken.balanceOf(_bob), value, "recipient received no-return token");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_passkeyEnvelope32BytePrefix_settlesErc20() public {
        bytes32 passkeyKeyHash = _registerBuiltinPasskeyOwner();
        bytes32 nonce = keccak256("passkey-twa");
        uint256 value = 3 ether;
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory sig = _passkeyEnvelope(passkeyKeyHash, sh);

        uint256 balBefore = token.balanceOf(_bob);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);

        assertEq(token.balanceOf(_bob) - balBefore, value, "passkey recipient credited");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_receive_happy_byPayee() public {
        bytes32 nonce = keccak256("receive");
        uint256 value = 10 ether;
        bytes32 sh = _structHash(_receiveTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        uint256 balBefore = token.balanceOf(_bob);
        vm.prank(_bob); // msg.sender == to (payee)
        itwa.receiveWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);

        assertEq(token.balanceOf(_bob) - balBefore, value, "payee received");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    // ---------------------------------------------------------------- replay / signature

    function test_replay_reverts() public {
        bytes32 nonce = keccak256("replay");
        uint256 value = 5 ether;
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);

        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);
    }

    function test_wrongSigner_reverts() public {
        bytes32 nonce = keccak256("wrongsigner");
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, 1 ether, 9_000, 11_000, nonce);
        // signed by bob but claiming alice's keyHash -> recovered signer mismatch
        bytes memory sig = _envelope(_bobPk, _aliceWalletKeyHash, sh);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, 1 ether, 9_000, 11_000, nonce, sig);
    }

    function test_unregisteredKey_revertsAndNonceUnused() public {
        (address eve, uint256 evePk) = makeAddrAndKey("eve-unregistered");
        bytes32 eveKeyHash = keccak256(abi.encodePacked(eve));
        bytes32 nonce = keccak256("unregistered");
        bytes memory sig = _executeSignature(evePk, eveKeyHash, address(token), _bob, 1 ether, 9_000, 11_000, nonce);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, 1 ether, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function test_wrappedDigestSignature_revertsAndNonceUnused() public {
        bytes32 nonce = keccak256("wrapped");
        uint256 value = 1 ether;
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes32 directDigest = twa.hashTypedData(sh);
        bytes32 wrappedDigest = twa.hashTypedData(
            MessageSignLib.hash(directDigest, uint48(0), SmartWallet(payable(_aliceWallet)).IMPLEMENTATION())
        );
        bytes memory sig = _envelopeForDigest(_alicePk, _aliceWalletKeyHash, wrappedDigest);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function test_shortEnvelope_reverts() public {
        bytes memory shortSig = hex"deadbeef"; // < 32 bytes
        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(
            address(token), _bob, 1 ether, 9_000, 11_000, keccak256("short"), shortSig
        );
    }

    function test_passkeyExecuteStyle38BytePrefix_revertsAndNonceUnused() public {
        bytes32 passkeyKeyHash = _registerBuiltinPasskeyOwner();
        bytes32 nonce = keccak256("passkey-valid-until-prefix");
        uint256 value = 2 ether;
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory ownerSignature = _passkeyOwnerSignature(twa.hashTypedData(sh));

        bytes memory executeStyleEnvelope = abi.encodePacked(passkeyKeyHash, uint48(0), ownerSignature);

        vm.expectRevert();
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, executeStyleEnvelope);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function test_crossTypeReplay_reverts() public {
        bytes32 nonce = keccak256("crosstype");
        uint256 value = 1 ether;
        // sign an EXECUTE authorization, then try to settle it through the RECEIVE path
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_bob);
        itwa.receiveWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);
    }

    // ---------------------------------------------------------------- window / caller guards

    function test_notYetValid_reverts() public {
        uint256 validAfter = block.timestamp; // block.timestamp <= validAfter -> not yet valid
        bytes32 nonce = keccak256("nyv");
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, 1 ether, validAfter, validAfter + 100, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        vm.expectRevert(
            abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationNotYetValid.selector, validAfter)
        );
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, 1 ether, validAfter, validAfter + 100, nonce, sig);
    }

    function test_expired_reverts() public {
        uint256 validBefore = block.timestamp; // block.timestamp >= validBefore -> expired
        bytes32 nonce = keccak256("exp");
        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, 1 ether, validBefore - 100, validBefore, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationExpired.selector, validBefore));
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, 1 ether, validBefore - 100, validBefore, nonce, sig);
    }

    function test_falseReturnToken_revertsAndNonceUnused() public {
        FalseReturnERC20 falseToken = new FalseReturnERC20();
        falseToken.mint(_aliceWallet, 100 ether);

        bytes32 nonce = keccak256("false-token");
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(falseToken), _bob, 1 ether, 9_000, 11_000, nonce);

        vm.expectRevert();
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(falseToken), _bob, 1 ether, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
        assertEq(falseToken.balanceOf(_aliceWallet), 100 ether, "account balance unchanged");
    }

    function test_insufficientErc20Balance_revertsAndNonceUnused() public {
        bytes32 nonce = keccak256("insufficient-erc20");
        uint256 value = token.balanceOf(_aliceWallet) + 1;
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(token), _bob, value, 9_000, 11_000, nonce);

        vm.expectRevert();
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
        assertEq(token.balanceOf(_bob), 0, "recipient unchanged");
    }

    function test_insufficientNativeBalance_revertsAndNonceUnused() public {
        bytes32 nonce = keccak256("insufficient-native");
        uint256 value = _aliceWallet.balance + 1;
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, _nativeAsset, _bob, value, 9_000, 11_000, nonce);

        vm.expectRevert();
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(_nativeAsset, _bob, value, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function test_msgValueRejected() public {
        bytes32 nonce = keccak256("msg-value");
        vm.deal(_relayer, 1 ether);
        bytes memory data = abi.encodeCall(
            ITransferWithAuthorization.executeTransferWithAuthorization,
            (address(token), _bob, 1, 9_000, 11_000, nonce, hex"")
        );

        vm.prank(_relayer);
        (bool ok,) = address(itwa).call{value: 1 wei}(data);

        assertFalse(ok, "nonpayable call rejected");
        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function test_receive_callerNotPayee_reverts() public {
        bytes32 nonce = keccak256("notpayee");
        uint256 value = 1 ether;
        bytes32 sh = _structHash(_receiveTypeHash, address(token), _bob, value, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.CallerNotPayee.selector, _relayer, _bob));
        vm.prank(_relayer); // not the payee
        itwa.receiveWithAuthorization(address(token), _bob, value, 9_000, 11_000, nonce, sig);
    }

    // ---------------------------------------------------------------- cancel

    function test_cancelFormB_selfThenSettleReverts() public {
        bytes32 nonce = keccak256("cancelB");

        vm.expectEmit(true, true, false, false, _aliceWallet);
        emit ITransferWithAuthorization.TransferAuthorizationCanceled(_aliceWallet, nonce);

        vm.prank(_aliceWallet); // self-call form (empty signature)
        itwa.cancelTransferAuthorization(nonce, "");

        assertTrue(itwa.transferAuthorizationState(nonce), "canceled is terminal");

        bytes32 sh = _structHash(_execTypeHash, address(token), _bob, 1 ether, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, 1 ether, 9_000, 11_000, nonce, sig);
    }

    function test_cancelFormB_nonSelf_reverts() public {
        vm.expectRevert(BaseAuthorization.NotFromSelf.selector);
        vm.prank(_relayer);
        itwa.cancelTransferAuthorization(keccak256("x"), "");
    }

    function test_cancelFormA_signed() public {
        bytes32 nonce = keccak256("cancelA");
        bytes32 sh = keccak256(abi.encode(_cancelTypeHash, nonce));
        bytes memory sig = _envelope(_alicePk, _aliceWalletKeyHash, sh);

        vm.expectEmit(true, true, false, false, _aliceWallet);
        emit ITransferWithAuthorization.TransferAuthorizationCanceled(_aliceWallet, nonce);

        vm.prank(_relayer); // form A may be relayed by anyone
        itwa.cancelTransferAuthorization(nonce, sig);

        assertTrue(itwa.transferAuthorizationState(nonce), "canceled is terminal");
    }

    function test_cancelFormA_invalidSignature_revertsAndNonceUnused() public {
        bytes32 nonce = keccak256("bad-cancel");
        bytes32 sh = keccak256(abi.encode(_cancelTypeHash, nonce));
        bytes memory sig = _envelope(_bobPk, _aliceWalletKeyHash, sh);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.cancelTransferAuthorization(nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function test_cancelAlreadyUsedNonce_reverts() public {
        bytes32 nonce = keccak256("cancel-used");
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(token), _bob, 1 ether, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, 1 ether, 9_000, 11_000, nonce, sig);

        bytes memory cancelSig = _cancelSignature(_alicePk, _aliceWalletKeyHash, nonce);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        vm.prank(_relayer);
        itwa.cancelTransferAuthorization(nonce, cancelSig);
    }

    // ---------------------------------------------------------------- hook wiring + CEI rollback

    function test_hookInvoked_blocksSettle_and_nonceUnconsumed() public {
        RevertingHook hook = new RevertingHook();
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(false, 0, address(hook)); // non-admin + hook

        // Register bob as a hook-constrained, externally-validated key (admin alice authorizes via execute).
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), settings);

        bytes32 nonce = keccak256("hook");
        uint256 value = 1 ether;
        bytes32 sh = _structHash(_execTypeHash, address(token), _charlie, value, 9_000, 11_000, nonce);
        bytes memory sig = _envelope(_bobPk, bobKeyHash, sh); // signed by bob's key -> selects bob's hook

        // The key-selected hook is invoked and blocks the spend.
        vm.expectRevert(RevertingHook.HookBlocked.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, 9_000, 11_000, nonce, sig);

        // Hook revert rolled back the CEI nonce write: the authorization is still unused.
        assertFalse(itwa.transferAuthorizationState(nonce), "nonce not consumed on revert");
    }

    function test_recordingHookReceivesExactErc20CallAndExecutor() public {
        RecordingHook hook = new RecordingHook();
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(false, 0, address(hook));
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), settings);

        bytes32 nonce = keccak256("hook-record-erc20");
        uint256 value = 7 ether;
        bytes memory sig = _executeSignature(_bobPk, bobKeyHash, address(token), _charlie, value, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, 9_000, 11_000, nonce, sig);

        bytes32 expectedRetHash = keccak256(
            abi.encode(
                address(token), uint256(0), keccak256(abi.encodeCall(IERC20.transfer, (_charlie, value))), _relayer
            )
        );
        assertEq(hook.preCheckCount(), 1, "preCheck count");
        assertEq(hook.postCheckCount(), 1, "postCheck count");
        assertEq(hook.lastTarget(), address(token), "target token");
        assertEq(hook.lastValue(), 0, "erc20 call value");
        assertEq(
            hook.lastDataHash(), keccak256(abi.encodeCall(IERC20.transfer, (_charlie, value))), "transfer calldata"
        );
        assertEq(hook.lastPreExecutor(), _relayer, "pre executor is relayer");
        assertEq(hook.lastPostExecutor(), _relayer, "post executor is relayer");
        assertEq(hook.lastPostRetHash(), expectedRetHash, "post ret");
    }

    function test_recordingHookReceivesExactNativeCallAndExecutor() public {
        RecordingHook hook = new RecordingHook();
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(false, 0, address(hook));
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), settings);

        bytes32 nonce = keccak256("hook-record-native");
        uint256 value = 1 ether;
        bytes memory sig = _executeSignature(_bobPk, bobKeyHash, _nativeAsset, _charlie, value, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(_nativeAsset, _charlie, value, 9_000, 11_000, nonce, sig);

        bytes32 expectedRetHash = keccak256(abi.encode(_charlie, value, keccak256(bytes("")), _relayer));
        assertEq(hook.preCheckCount(), 1, "preCheck count");
        assertEq(hook.postCheckCount(), 1, "postCheck count");
        assertEq(hook.lastTarget(), _charlie, "native target");
        assertEq(hook.lastValue(), value, "native value");
        assertEq(hook.lastDataHash(), keccak256(bytes("")), "empty data");
        assertEq(hook.lastPostRetHash(), expectedRetHash, "post ret");
    }

    function test_nonAdminNativeSelfTarget_succeedsNetZero() public {
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            OwnerManager(_aliceWallet).packSettings(false, 0, address(0))
        );

        bytes32 nonce = keccak256("non-admin-native-self");
        uint256 balanceBefore = _aliceWallet.balance;
        bytes memory sig =
            _executeSignature(_bobPk, bobKeyHash, _nativeAsset, _aliceWallet, 1 ether, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(_nativeAsset, _aliceWallet, 1 ether, 9_000, 11_000, nonce, sig);

        assertEq(_aliceWallet.balance, balanceBefore, "self-send net zero");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_adminNativeSelfTarget_succeedsNetZero() public {
        bytes32 nonce = keccak256("admin-native-self");
        uint256 balanceBefore = _aliceWallet.balance;
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, _nativeAsset, _aliceWallet, 1 ether, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(_nativeAsset, _aliceWallet, 1 ether, 9_000, 11_000, nonce, sig);

        assertEq(_aliceWallet.balance, balanceBefore, "self-send net zero");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_externalTokenToWalletRecipient_succeedsForNonAdmin() public {
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        _addOwnerToAccount(
            _alice,
            _aliceWallet,
            bobKeyHash,
            address(_ecdsaValidator),
            OwnerManager(_aliceWallet).packSettings(false, 0, address(0))
        );

        bytes32 nonce = keccak256("external-token-self-recipient");
        uint256 beforeBalance = token.balanceOf(_aliceWallet);
        bytes memory sig =
            _executeSignature(_bobPk, bobKeyHash, address(token), _aliceWallet, 1 ether, 9_000, 11_000, nonce);

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _aliceWallet, 1 ether, 9_000, 11_000, nonce, sig);

        assertEq(token.balanceOf(_aliceWallet), beforeBalance, "self-recipient token transfer net zero");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function test_nativeReentrancyCannotConsumeNestedNonce() public {
        bytes32 nestedNonce = keccak256("nested-reentrant");
        bytes memory nestedSig = _executeSignature(
            _alicePk, _aliceWalletKeyHash, _nativeAsset, _charlie, 1 ether, 9_000, 11_000, nestedNonce
        );
        ReentrantNativeReceiver receiver =
            new ReentrantNativeReceiver(itwa, _nativeAsset, _charlie, 1 ether, 9_000, 11_000, nestedNonce, nestedSig);

        bytes32 outerNonce = keccak256("outer-reentrant");
        uint256 outerValue = 1 ether;
        bytes memory outerSig = _executeSignature(
            _alicePk, _aliceWalletKeyHash, _nativeAsset, address(receiver), outerValue, 9_000, 11_000, outerNonce
        );

        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(
            _nativeAsset, address(receiver), outerValue, 9_000, 11_000, outerNonce, outerSig
        );

        assertTrue(receiver.attempted(), "nested call attempted");
        assertFalse(receiver.nestedSucceeded(), "nested settle blocked");
        assertTrue(itwa.transferAuthorizationState(outerNonce), "outer consumed");
        assertFalse(itwa.transferAuthorizationState(nestedNonce), "nested nonce unused");
        assertEq(address(receiver).balance, outerValue, "receiver got outer value");
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_executeErc20MovesExactValue(address to, uint96 amount, uint256 nonceSeed, address caller) public {
        vm.assume(to != _aliceWallet);
        uint256 value = bound(uint256(amount), 0, token.balanceOf(_aliceWallet));
        bytes32 nonce = keccak256(abi.encode("fuzz-exec", nonceSeed, to, value));
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(token), to, value, 9_000, 11_000, nonce);

        uint256 accountBefore = token.balanceOf(_aliceWallet);
        uint256 recipientBefore = token.balanceOf(to);

        vm.prank(caller);
        itwa.executeTransferWithAuthorization(address(token), to, value, 9_000, 11_000, nonce, sig);

        assertEq(token.balanceOf(_aliceWallet), accountBefore - value, "account debited");
        assertEq(token.balanceOf(to), recipientBefore + value, "recipient credited");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce consumed");
    }

    function testFuzz_mutatedValueInvalidatesSignature(uint96 signedAmount, uint96 mutatedAmount, uint256 nonceSeed)
        public
    {
        uint256 value = bound(uint256(signedAmount), 0, 500 ether);
        uint256 mutatedValue = bound(uint256(mutatedAmount), 0, 500 ether);
        vm.assume(mutatedValue != value);
        bytes32 nonce = keccak256(abi.encode("fuzz-mutated-value", nonceSeed));
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(token), _bob, value, 9_000, 11_000, nonce);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), _bob, mutatedValue, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }

    function testFuzz_mutatedRecipientInvalidatesSignature(address signedTo, address mutatedTo, uint256 nonceSeed)
        public
    {
        vm.assume(mutatedTo != signedTo);
        bytes32 nonce = keccak256(abi.encode("fuzz-mutated-recipient", nonceSeed));
        bytes memory sig =
            _executeSignature(_alicePk, _aliceWalletKeyHash, address(token), signedTo, 1 ether, 9_000, 11_000, nonce);

        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        vm.prank(_relayer);
        itwa.executeTransferWithAuthorization(address(token), mutatedTo, 1 ether, 9_000, 11_000, nonce, sig);

        assertFalse(itwa.transferAuthorizationState(nonce), "nonce remains unused");
    }
}
