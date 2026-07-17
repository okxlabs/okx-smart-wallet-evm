// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Base, MockERC20} from "../Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {ITransferWithAuthorization} from "src/interfaces/ITransferWithAuthorization.sol";
import {TransferWithAuthorization} from "src/TransferWithAuthorization.sol";
import {Static} from "src/libraries/Static.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {OwnerManager} from "src/OwnerManager.sol";
import {INonceManager} from "src/interfaces/INonceManager.sol";
import {SmartWallet} from "src/SmartWallet.sol";
import {RecordingHook, RevertingHook} from "../mocks/Hooks.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ===================== Honest peripheral fixtures (external dependencies only) =====================

/// @dev A deflationary token: the sender is debited the full amount, the recipient receives the amount
///      minus a fixed fee, and the fee is routed to a sink. Models the real divergence between the
///      amount a fee-on-transfer token deducts and the amount its recipient actually receives.
contract IntegrationFeeOnTransferERC20 {
    string public constant name = "FeeToken";
    string public constant symbol = "FEE";
    uint8 public constant decimals = 18;

    uint256 public immutable feeBps;
    address public immutable feeSink;
    mapping(address => uint256) public balanceOf;

    constructor(uint256 feeBps_, address feeSink_) {
        feeBps = feeBps_;
        feeSink = feeSink_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 bal = balanceOf[msg.sender];
        require(bal >= amount, "fee-token: insufficient");
        balanceOf[msg.sender] = bal - amount;
        uint256 fee = (amount * feeBps) / 10_000;
        balanceOf[to] += amount - fee;
        balanceOf[feeSink] += fee;
        return true;
    }
}

/// @dev A contract recipient that rejects any native transfer.
contract RevertingNativeRecipient {
    error Rejected();

    receive() external payable {
        revert Rejected();
    }
}

/// @dev A contract payee that pulls an owed payment atomically from within its own logic, so that
///      msg.sender == to on the account's receive path.
contract IntegrationContractPayee {
    function pull(
        ITransferWithAuthorization wallet,
        address token,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external {
        wallet.receiveWithAuthorization(token, address(this), value, validAfter, validBefore, nonce, signature);
    }
}

/// @dev A faithful next UUPS implementation with the same custom storage layout plus an upgrade marker.
contract TwaWalletV2 is SmartWallet layout at 0x653ff6dcbda533c3c7d8ffb646da3e510d0de40f237170c4da3f874472aecb00 {
    function isUpgraded() external pure returns (bool) {
        return true;
    }
}

// ===================== Integration base: real deployment harness + signing helpers =====================

abstract contract TwaIntegrationBase is Base {
    MockERC20 internal token;

    bytes32 internal EXEC_TYPEHASH;
    bytes32 internal RECV_TYPEHASH;
    bytes32 internal CANCEL_TYPEHASH;
    address internal NATIVE;

    // Stable base time; authorization windows use absolute literals around it (open interval).
    uint256 internal constant BASE_TS = 10_000;
    uint256 internal constant VALID_AFTER = 9_000;
    uint256 internal constant VALID_BEFORE = 11_000;

    address internal _relayerA;
    address internal _relayerB;
    address internal _feeSink;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(BASE_TS);

        TransferWithAuthorization aliceTwa = TransferWithAuthorization(payable(_aliceWallet));
        // Typehashes are internal constants in the contract; recompute them from the type strings here.
        EXEC_TYPEHASH = keccak256(
            "ExecuteTransferWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
        );
        RECV_TYPEHASH = keccak256(
            "ReceiveWithAuthorization(address token,address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 authorizationNonce)"
        );
        CANCEL_TYPEHASH = keccak256("CancelTransferAuthorization(bytes32 authorizationNonce)");
        NATIVE = Static.NATIVE_ETH;

        _relayerA = makeAddr("relayerA");
        _relayerB = makeAddr("relayerB");
        _feeSink = makeAddr("feeSink");

        token = new MockERC20();
        token.mint(_aliceWallet, 1_000 ether);
    }

    // ---- signing helpers, parametric on the account so cross-account binding is exercised honestly ----

    function _digest(address account, bytes32 structHash) internal view returns (bytes32) {
        return TransferWithAuthorization(payable(account)).hashTypedData(structHash);
    }

    /// @dev Reconstructs the account's EIP-712 domain separator from its ERC-5267 eip712Domain() fields
    ///      (the dedicated separator getter was removed from the contract).
    function _domainSeparatorOf(address account) internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract, , ) =
            TransferWithAuthorization(payable(account)).eip712Domain();
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function _transferStructHash(
        bytes32 typeHash,
        address account,
        address tkn,
        address to,
        uint256 value,
        bytes32 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(typeHash, tkn, account, to, value, VALID_AFTER, VALID_BEFORE, nonce));
    }

    function _envelope(address account, uint256 signerPk, bytes32 keyHash, bytes32 structHash)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = _digest(account, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(keyHash, r, s, v);
    }

    function _execEnvelope(
        address account,
        uint256 signerPk,
        bytes32 keyHash,
        address tkn,
        address to,
        uint256 value,
        bytes32 nonce
    ) internal view returns (bytes memory) {
        return _envelope(account, signerPk, keyHash, _transferStructHash(EXEC_TYPEHASH, account, tkn, to, value, nonce));
    }

    function _receiveEnvelope(
        address account,
        uint256 signerPk,
        bytes32 keyHash,
        address tkn,
        address to,
        uint256 value,
        bytes32 nonce
    ) internal view returns (bytes memory) {
        return _envelope(account, signerPk, keyHash, _transferStructHash(RECV_TYPEHASH, account, tkn, to, value, nonce));
    }

    function _cancelEnvelope(address account, uint256 signerPk, bytes32 keyHash, bytes32 nonce)
        internal
        view
        returns (bytes memory)
    {
        return _envelope(account, signerPk, keyHash, keccak256(abi.encode(CANCEL_TYPEHASH, nonce)));
    }
}

// ===================== Integration scenarios =====================

contract TransferWithAuthorizationIntegrationTest is TwaIntegrationBase {
    // -------------------------------------------------- deployment / initialization

    /// @notice A freshly factory-deployed multi-owner account exposes a live TWA surface and settles.
    function test_deploy_freshMultiOwnerAccountTwaLiveAndSettles() public {
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 daveKeyHash = keccak256(abi.encodePacked(_dave));

        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = aliceKeyHash;
        keyHashes[1] = daveKeyHash;
        address[] memory validators = new address[](2);
        validators[0] = address(_ecdsaValidator);
        validators[1] = address(_ecdsaValidator);

        address account = _deployAccountWithOwners(keyHashes, validators, 7);

        // both initial owners registered as admins by initialize()
        assertTrue(_isSignerAdmin(account, aliceKeyHash), "alice admin");
        assertTrue(_isSignerAdmin(account, daveKeyHash), "dave admin");

        // TWA surface live immediately on the fresh account — the wallet no longer advertises the
        // TWA interface id via supportsInterface, so liveness is proven by the wired domain separator below.
        assertFalse(ISmartWallet(account).supportsInterface(0x86c5a9e1), "twa interface id not advertised");
        // The dedicated separator getter was removed; reconstruct it from ERC-5267 eip712Domain() fields.
        bytes32 sep = _domainSeparatorOf(account);
        bytes32 probe = _transferStructHash(EXEC_TYPEHASH, account, address(token), _bob, 1, keccak256("probe"));
        assertEq(_digest(account, probe), keccak256(abi.encodePacked(hex"1901", sep, probe)), "domain separator wired");

        // a happy-path settle works on the freshly initialized account
        token.mint(account, 100 ether);
        bytes32 nonce = keccak256("fresh-settle");
        uint256 value = 30 ether;
        bytes memory sig = _execEnvelope(account, _alicePk, aliceKeyHash, address(token), _bob, value, nonce);

        uint256 before = token.balanceOf(_bob);
        vm.prank(_relayerA);
        ITransferWithAuthorization(account).executeTransferWithAuthorization(
            address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig
        );

        assertEq(token.balanceOf(_bob) - before, value, "recipient credited on fresh account");
        assertTrue(ITransferWithAuthorization(account).transferAuthorizationState(nonce), "nonce terminal");
    }

    /// @notice The deployed account cannot be re-initialized.
    function test_deploy_reinitializeReverts() public {
        InitialOwner[] memory owners = _createSingleOwner(keccak256(abi.encodePacked(_alice)), address(_ecdsaValidator));

        // even the factory cannot re-run initialize on an already-initialized account
        vm.prank(address(_factory));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ISmartWallet(_aliceWallet).initialize(owners);
    }

    // -------------------------------------------------- cross-account binding

    /// @notice An authorization signed for one account does not settle on a different account, even when
    ///         the same owner key is registered on both. The recompiled struct binds from=address(this)
    ///         and the digest binds verifyingContract, so the signature fails on the other account.
    function test_crossAccount_authorizationDoesNotReplayAcrossAccounts() public {
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        address accountA = _aliceWallet;
        address accountB = _deployAccountSingleOwner(aliceKeyHash, address(_ecdsaValidator), 99);
        token.mint(accountB, 500 ether);

        // signature is bound to accountA (from == accountA, accountA domain separator)
        bytes32 nonce = keccak256("cross-account");
        uint256 value = 10 ether;
        bytes memory sigForA = _execEnvelope(accountA, _alicePk, aliceKeyHash, address(token), _bob, value, nonce);

        // submitting accountA's authorization to accountB fails and moves no funds on B
        uint256 bBefore = token.balanceOf(accountB);
        uint256 bobBefore = token.balanceOf(_bob);
        vm.prank(_relayerA);
        vm.expectRevert(ISmartWallet.InvalidSignature.selector);
        ITransferWithAuthorization(accountB).executeTransferWithAuthorization(
            address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sigForA
        );
        assertEq(token.balanceOf(accountB), bBefore, "account B unchanged");
        assertFalse(ITransferWithAuthorization(accountB).transferAuthorizationState(nonce), "B nonce unused");

        // the same authorization still settles on its intended account A
        vm.prank(_relayerA);
        ITransferWithAuthorization(accountA).executeTransferWithAuthorization(
            address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sigForA
        );
        assertEq(token.balanceOf(_bob) - bobBefore, value, "recipient credited on account A");
        assertTrue(ITransferWithAuthorization(accountA).transferAuthorizationState(nonce), "A nonce terminal");
    }

    // -------------------------------------------------- user journeys / lifecycle

    /// @notice Settle once, then a later transaction replaying the same authorization is rejected.
    function test_journey_erc20SettleThenReplayInLaterTxReverts() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 nonce = keccak256("journey-replay");
        uint256 value = 40 ether;
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, value, nonce);

        uint256 accountBefore = token.balanceOf(_aliceWallet);
        uint256 recipientBefore = token.balanceOf(_charlie);

        vm.expectEmit(true, true, true, true, _aliceWallet);
        emit ITransferWithAuthorization.TransferAuthorizationUsed(address(token), _aliceWallet, _charlie, value, nonce);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);

        assertEq(accountBefore - token.balanceOf(_aliceWallet), value, "account debited once");
        assertEq(token.balanceOf(_charlie) - recipientBefore, value, "recipient credited once");

        // advance to a later block / transaction and replay
        vm.roll(block.number + 1);
        vm.prank(_relayerB);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);

        assertEq(token.balanceOf(_charlie) - recipientBefore, value, "no second credit");
    }

    /// @notice An owner revokes an outstanding authorization through a real account self-call, after which
    ///         settlement of that nonce is rejected and no funds move.
    function test_journey_ownerCancelsViaExecuteSelfCallThenSettleReverts() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));
        bytes32 nonce = keccak256("journey-cancel");

        // owner cancels by having the account call itself (empty-signature form), routed through execute
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeCall(ITransferWithAuthorization.cancelTransferAuthorization, (nonce, bytes("")))
        });

        vm.expectEmit(true, false, false, false, _aliceWallet);
        emit ITransferWithAuthorization.TransferAuthorizationCanceled(nonce);
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls);

        assertTrue(itwa.transferAuthorizationState(nonce), "nonce terminal after cancel");

        // a later settle of the canceled nonce is rejected and moves no funds
        uint256 value = 5 ether;
        uint256 recipientBefore = token.balanceOf(_charlie);
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, value, nonce);
        vm.prank(_relayerA);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertEq(token.balanceOf(_charlie), recipientBefore, "no funds moved for canceled nonce");
    }

    // -------------------------------------------------- state continuity

    /// @notice A TWA settle does not advance the account's 4337/native nonce, and a relayer execution does
    ///         not consume any TWA authorization nonce. The two nonce spaces are independent.
    function test_stateContinuity_twaNonceIsolatedFrom4337Nonce() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        assertEq(_getNonce(_aliceWallet), 0, "4337 nonce starts at 0");

        bytes32 twaNonce = keccak256("isolation-twa");
        assertFalse(itwa.transferAuthorizationState(twaNonce), "twa nonce unused");

        // a normal relayer execution consumes the 4337 nonce (0 -> 1)
        Call[] memory calls = new Call[](1);
        calls[0] = constructErc20TransferCall(IERC20(address(token)), _dave, 1 ether);
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: _getNonce(_aliceWallet)});
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, batchedCall, uint48(0));
        vm.prank(_relayerA);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);
        assertEq(_getNonce(_aliceWallet), 1, "4337 nonce advanced by relayer execution");

        // a TWA settle consumes only the TWA nonce; the 4337 nonce is untouched
        uint256 value = 3 ether;
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _bob, value, twaNonce);
        vm.prank(_relayerB);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, VALID_AFTER, VALID_BEFORE, twaNonce, sig);

        assertTrue(itwa.transferAuthorizationState(twaNonce), "twa nonce terminal");
        assertEq(_getNonce(_aliceWallet), 1, "4337 nonce unchanged by twa settle");
    }

    /// @notice Distinct authorization nonces progress through their own lifecycles independently.
    function test_stateContinuity_independentNoncesProgressIndependently() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        bytes32 n1 = keccak256("indep-1");
        bytes32 n2 = keccak256("indep-2");
        bytes32 n3 = keccak256("indep-3");

        // n1 -> used
        uint256 v1 = 7 ether;
        bytes memory s1 = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _bob, v1, n1);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _bob, v1, VALID_AFTER, VALID_BEFORE, n1, s1);

        // n2 -> canceled (signed form, relayed)
        bytes memory cancelSig = _cancelEnvelope(_aliceWallet, _alicePk, aliceKeyHash, n2);
        vm.prank(_relayerB);
        itwa.cancelTransferAuthorization(n2, cancelSig);

        assertTrue(itwa.transferAuthorizationState(n1), "n1 terminal");
        assertTrue(itwa.transferAuthorizationState(n2), "n2 terminal");
        assertFalse(itwa.transferAuthorizationState(n3), "n3 still unused");

        // both terminal nonces reject further transitions
        vm.prank(_relayerA);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, n1));
        itwa.executeTransferWithAuthorization(address(token), _bob, v1, VALID_AFTER, VALID_BEFORE, n1, s1);

        // the untouched nonce still settles
        uint256 v3 = 2 ether;
        bytes memory s3 = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, v3, n3);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _charlie, v3, VALID_AFTER, VALID_BEFORE, n3, s3);
        assertTrue(itwa.transferAuthorizationState(n3), "n3 terminal after settle");
    }

    /// @notice Authorization-nonce state survives a UUPS upgrade of the account implementation.
    function test_upgrade_twaNonceStatePersistsAcrossUUPSUpgrade() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        // settle an authorization before the upgrade
        bytes32 nonce = keccak256("upgrade-durability");
        uint256 value = 6 ether;
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _bob, value, nonce);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce terminal before upgrade");

        // upgrade the implementation through an owner-authorized self-call
        TwaWalletV2 v2 = new TwaWalletV2();
        Call[] memory upgradeCalls = new Call[](1);
        upgradeCalls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(v2), "")
        });
        BatchedCall memory batchedCall = BatchedCall({calls: upgradeCalls, nonce: _getNonce(_aliceWallet)});
        bytes memory validatorData = _constructRelayerSignature(_aliceWallet, _alice, _alicePk, batchedCall, uint48(0));
        vm.prank(_relayerA);
        ISmartWallet(_aliceWallet).executeWithRelayer(batchedCall, validatorData);

        assertTrue(TwaWalletV2(payable(_aliceWallet)).isUpgraded(), "implementation upgraded");

        // the authorization-nonce state persists and replay is still rejected after the upgrade
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce still terminal after upgrade");
        vm.prank(_relayerB);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        itwa.executeTransferWithAuthorization(address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
    }

    // -------------------------------------------------- multi-actor

    /// @notice Each owner key's settle selects that key's own hook; an admin key with no hook invokes none,
    ///         a non-admin key with a hook invokes exactly its hook with the exact call.
    function test_multiActor_perKeyHookIsolationAcrossOwners() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        // register bob as a non-admin key constrained by a recording hook
        RecordingHook bobHook = new RecordingHook();
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 settings = OwnerManager(_aliceWallet).packSettings(false, 0, address(bobHook));
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), settings);

        // alice (admin, no hook) settles: bob's hook must not be touched
        uint256 vA = 4 ether;
        bytes memory sigA =
            _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, vA, keccak256("iso-alice"));
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(
            address(token), _charlie, vA, VALID_AFTER, VALID_BEFORE, keccak256("iso-alice"), sigA
        );
        assertEq(bobHook.preCount(), 0, "admin-key settle invokes no hook");

        // bob (non-admin, hooked) settles: bob's hook is invoked once with the exact call and the relayer as executor
        uint256 vB = 9 ether;
        bytes memory sigB =
            _execEnvelope(_aliceWallet, _bobPk, bobKeyHash, address(token), _dave, vB, keccak256("iso-bob"));
        vm.prank(_relayerB);
        itwa.executeTransferWithAuthorization(
            address(token), _dave, vB, VALID_AFTER, VALID_BEFORE, keccak256("iso-bob"), sigB
        );
        assertEq(bobHook.preCount(), 1, "hooked-key settle invokes its hook once");
        assertEq(bobHook.postCount(), 1, "post hook once");
        assertEq(bobHook.lastKeyHash(), bobKeyHash, "hook saw authorizing keyHash");
        assertEq(bobHook.lastToken(), address(token), "hook saw token");
        assertEq(bobHook.lastTo(), _dave, "hook saw recipient");
        assertEq(bobHook.lastValue(), vB, "hook saw transfer value");
        assertEq(bobHook.lastCaller(), _relayerB, "hook caller is the relayer");

        // control: a normal external-token payment whose recipient is the account itself is not a self-call
        uint256 vSelf = 1 ether;
        uint256 selfBefore = token.balanceOf(_aliceWallet);
        bytes memory sigSelf = _execEnvelope(
            _aliceWallet, _alicePk, aliceKeyHash, address(token), _aliceWallet, vSelf, keccak256("iso-self")
        );
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(
            address(token), _aliceWallet, vSelf, VALID_AFTER, VALID_BEFORE, keccak256("iso-self"), sigSelf
        );
        assertEq(token.balanceOf(_aliceWallet), selfBefore, "external-token self-recipient settles net zero");
    }

    /// @notice execute is permissionless (any relayer), while receive is gated to the payee. A contract payee
    ///         pulls an owed payment from within its own logic; a non-payee submitter is rejected.
    function test_multiActor_executePermissionless_receivePayeeGatedContractPayee() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        IntegrationContractPayee payee = new IntegrationContractPayee();

        // execute path: an arbitrary relayer settles
        uint256 ve = 8 ether;
        bytes memory execSig =
            _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, ve, keccak256("perm-exec"));
        vm.prank(makeAddr("arbitrary-relayer"));
        itwa.executeTransferWithAuthorization(
            address(token), _charlie, ve, VALID_AFTER, VALID_BEFORE, keccak256("perm-exec"), execSig
        );
        assertEq(token.balanceOf(_charlie), ve, "execute settled by arbitrary relayer");

        // receive path: signed to the contract payee
        uint256 vr = 12 ether;
        bytes32 rNonce = keccak256("perm-recv");
        bytes memory recvSig =
            _receiveEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), address(payee), vr, rNonce);

        // a non-payee submitter is rejected (msg.sender != to)
        vm.prank(_relayerA);
        vm.expectRevert(
            abi.encodeWithSelector(ITransferWithAuthorization.CallerNotPayee.selector, _relayerA, address(payee))
        );
        itwa.receiveWithAuthorization(address(token), address(payee), vr, VALID_AFTER, VALID_BEFORE, rNonce, recvSig);

        // the payee contract pulls the payment from within its own logic
        uint256 payeeBefore = token.balanceOf(address(payee));
        payee.pull(itwa, address(token), vr, VALID_AFTER, VALID_BEFORE, rNonce, recvSig);
        assertEq(token.balanceOf(address(payee)) - payeeBefore, vr, "payee credited via receive");
        assertTrue(itwa.transferAuthorizationState(rNonce), "receive nonce terminal");
    }

    /// @notice A front-running relayer cannot change the settlement outcome: funds reach the signed recipient,
    ///         and the losing relayer's resubmission reverts.
    function test_multiActor_frontRunIsOutcomeNeutral() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        bytes32 nonce = keccak256("front-run");
        uint256 value = 15 ether;
        // intended facilitator is relayer A, but the signature only binds the recipient and amount
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, value, nonce);

        uint256 recipientBefore = token.balanceOf(_charlie);

        // relayer B front-runs and settles first
        vm.prank(_relayerB);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertEq(token.balanceOf(_charlie) - recipientBefore, value, "funds reached the signed recipient");

        // relayer A's later submission reverts; the outcome is unchanged
        vm.prank(_relayerA);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationAlreadyUsed.selector, nonce));
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertEq(token.balanceOf(_charlie) - recipientBefore, value, "no double credit from front-run");
    }

    // -------------------------------------------------- fund flows

    /// @notice Several sequential ERC-20 settlements conserve value: total recipient credit equals total
    ///         account debit equals tracked outflow.
    function test_fundFlow_sequentialErc20SettlementsConserveAndDrain() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        address[] memory recipients = new address[](4);
        recipients[0] = _bob;
        recipients[1] = _charlie;
        recipients[2] = _dave;
        recipients[3] = makeAddr("twa-recipient-4");
        uint256[] memory values = new uint256[](4);
        values[0] = 100 ether;
        values[1] = 200 ether;
        values[2] = 150 ether;
        values[3] = 50 ether;

        uint256 accountStart = token.balanceOf(_aliceWallet);
        uint256 outflow;
        uint256 recipientCreditSum;

        for (uint256 i; i < recipients.length; i++) {
            bytes32 nonce = keccak256(abi.encode("drain", i));
            bytes memory sig =
                _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), recipients[i], values[i], nonce);
            uint256 rBefore = token.balanceOf(recipients[i]);
            vm.prank(_relayerA);
            itwa.executeTransferWithAuthorization(
                address(token), recipients[i], values[i], VALID_AFTER, VALID_BEFORE, nonce, sig
            );
            outflow += values[i];
            recipientCreditSum += token.balanceOf(recipients[i]) - rBefore;
        }

        assertEq(accountStart - token.balanceOf(_aliceWallet), outflow, "account debit equals outflow");
        assertEq(recipientCreditSum, outflow, "recipient credit equals outflow");
        assertEq(token.balanceOf(_aliceWallet), accountStart - outflow, "account conserved");
    }

    /// @notice Native and ERC-20 settlements in one account lifecycle each conserve their own ledger.
    function test_fundFlow_mixedNativeAndErc20Conserve() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        uint256 nativeStart = _aliceWallet.balance;
        uint256 tokenStart = token.balanceOf(_aliceWallet);

        // native settle to bob
        uint256 nativeValue = 2 ether;
        bytes memory nativeSig =
            _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, NATIVE, _bob, nativeValue, keccak256("mix-native"));
        uint256 bobNativeBefore = _bob.balance;
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(NATIVE, _bob, nativeValue, VALID_AFTER, VALID_BEFORE, keccak256("mix-native"), nativeSig);

        // token settle to charlie
        uint256 tokenValue = 75 ether;
        bytes memory tokenSig =
            _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, tokenValue, keccak256("mix-token"));
        uint256 charlieTokenBefore = token.balanceOf(_charlie);
        vm.prank(_relayerB);
        itwa.executeTransferWithAuthorization(address(token), _charlie, tokenValue, VALID_AFTER, VALID_BEFORE, keccak256("mix-token"), tokenSig);

        assertEq(nativeStart - _aliceWallet.balance, nativeValue, "native ledger debited exactly");
        assertEq(_bob.balance - bobNativeBefore, nativeValue, "native recipient credited exactly");
        assertEq(tokenStart - token.balanceOf(_aliceWallet), tokenValue, "token ledger debited exactly");
        assertEq(token.balanceOf(_charlie) - charlieTokenBefore, tokenValue, "token recipient credited exactly");
    }

    /// @notice A fee-on-transfer token settles the nominal value: the account is debited the full value, the
    ///         recipient receives value minus fee, and the emitted event logs the nominal value.
    function test_fundFlow_feeOnTransferTokenSettlesNominalValue() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        uint256 feeBps = 250; // 2.5%
        IntegrationFeeOnTransferERC20 feeToken = new IntegrationFeeOnTransferERC20(feeBps, _feeSink);
        feeToken.mint(_aliceWallet, 100 ether);

        bytes32 nonce = keccak256("fee-on-transfer");
        uint256 value = 40 ether;
        uint256 expectedFee = (value * feeBps) / 10_000;
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(feeToken), _bob, value, nonce);

        uint256 accountBefore = feeToken.balanceOf(_aliceWallet);

        // the event logs the nominal value, regardless of the fee the token applies
        vm.expectEmit(true, true, true, true, _aliceWallet);
        emit ITransferWithAuthorization.TransferAuthorizationUsed(address(feeToken), _aliceWallet, _bob, value, nonce);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(feeToken), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig);

        assertEq(accountBefore - feeToken.balanceOf(_aliceWallet), value, "account debited full nominal value");
        assertEq(feeToken.balanceOf(_bob), value - expectedFee, "recipient received value minus fee");
        assertEq(feeToken.balanceOf(_feeSink), expectedFee, "fee routed to sink");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce terminal");
    }

    // -------------------------------------------------- failure / recovery (no partial effect)

    /// @notice A policy hook blocks a settle (leaving the nonce unused and funds untouched); after the owner
    ///         removes the hook, the same signed authorization settles.
    function test_recovery_hookBlockThenRemoveHookThenRetrySameSignature() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);

        RevertingHook blockingHook = new RevertingHook();
        bytes32 bobKeyHash = keccak256(abi.encodePacked(_bob));
        uint256 blockedSettings = OwnerManager(_aliceWallet).packSettings(false, 0, address(blockingHook));
        _addOwnerToAccount(_alice, _aliceWallet, bobKeyHash, address(_ecdsaValidator), blockedSettings);

        bytes32 nonce = keccak256("recover-hook");
        uint256 value = 5 ether;
        bytes memory sig = _execEnvelope(_aliceWallet, _bobPk, bobKeyHash, address(token), _charlie, value, nonce);

        uint256 accountBefore = token.balanceOf(_aliceWallet);
        uint256 recipientBefore = token.balanceOf(_charlie);

        // blocked: no partial effect
        vm.prank(_relayerA);
        vm.expectRevert(RevertingHook.HookBlocked.selector);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertFalse(itwa.transferAuthorizationState(nonce), "nonce unused after block");
        assertEq(token.balanceOf(_aliceWallet), accountBefore, "account unchanged after block");
        assertEq(token.balanceOf(_charlie), recipientBefore, "recipient unchanged after block");

        // owner removes the hook for bob's key
        uint256 openSettings = OwnerManager(_aliceWallet).packSettings(false, 0, address(0));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: _aliceWallet,
            value: 0,
            data: abi.encodeWithSelector(IOwnerManager.updateOwner.selector, bobKeyHash, address(_ecdsaValidator), openSettings)
        });
        vm.prank(_alice);
        ISmartWallet(_aliceWallet).execute(calls);

        // the same authorization now settles
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertEq(token.balanceOf(_charlie) - recipientBefore, value, "recipient credited after recovery");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce terminal after recovery");
    }

    /// @notice An under-funded settle reverts without partial effect; after the account is funded, the same
    ///         signed authorization settles.
    function test_recovery_insufficientBalanceThenFundThenRetrySameSignature() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        // value exceeds the current balance
        uint256 value = token.balanceOf(_aliceWallet) + 500 ether;
        bytes32 nonce = keccak256("recover-balance");
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _bob, value, nonce);

        uint256 recipientBefore = token.balanceOf(_bob);
        vm.prank(_relayerA);
        vm.expectRevert();
        itwa.executeTransferWithAuthorization(address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertFalse(itwa.transferAuthorizationState(nonce), "nonce unused after insufficient balance");
        assertEq(token.balanceOf(_bob), recipientBefore, "recipient unchanged after revert");

        // fund the account so the same authorization can settle
        token.mint(_aliceWallet, 600 ether);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertEq(token.balanceOf(_bob) - recipientBefore, value, "recipient credited after funding");
        assertTrue(itwa.transferAuthorizationState(nonce), "nonce terminal after recovery");
    }

    /// @notice An expired authorization cannot be settled; a freshly signed authorization with a new window does.
    function test_failure_expiredAuthorizationReissueWorks() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        bytes32 nonce = keccak256("expired-then-reissue");
        uint256 value = 3 ether;
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _bob, value, nonce);

        // move time strictly past the signed window and attempt to settle
        vm.warp(VALID_BEFORE + 1);
        vm.prank(_relayerA);
        vm.expectRevert(abi.encodeWithSelector(ITransferWithAuthorization.AuthorizationExpired.selector, VALID_BEFORE));
        itwa.executeTransferWithAuthorization(address(token), _bob, value, VALID_AFTER, VALID_BEFORE, nonce, sig);
        assertFalse(itwa.transferAuthorizationState(nonce), "expired nonce unused");

        // a fresh authorization with an open window around the new time settles
        uint256 freshAfter = VALID_BEFORE; // current time is VALID_BEFORE + 1, strictly after
        uint256 freshBefore = VALID_BEFORE + 100;
        bytes32 freshNonce = keccak256("reissued");
        bytes32 structHash =
            keccak256(abi.encode(EXEC_TYPEHASH, address(token), _aliceWallet, _bob, value, freshAfter, freshBefore, freshNonce));
        bytes memory freshSig = _envelope(_aliceWallet, _alicePk, aliceKeyHash, structHash);
        uint256 before = token.balanceOf(_bob);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _bob, value, freshAfter, freshBefore, freshNonce, freshSig);
        assertEq(token.balanceOf(_bob) - before, value, "reissued authorization settled");
    }

    /// @notice A native settle to a recipient that rejects ETH reverts and leaves no partial effect.
    function test_failure_nativeRecipientRevertRollsBackFully() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        RevertingNativeRecipient rejector = new RevertingNativeRecipient();
        bytes32 nonce = keccak256("native-reject");
        uint256 value = 1 ether;
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, NATIVE, address(rejector), value, nonce);

        uint256 accountBefore = _aliceWallet.balance;
        vm.prank(_relayerA);
        vm.expectRevert(RevertingNativeRecipient.Rejected.selector);
        itwa.executeTransferWithAuthorization(NATIVE, address(rejector), value, VALID_AFTER, VALID_BEFORE, nonce, sig);

        assertEq(_aliceWallet.balance, accountBefore, "account native balance unchanged");
        assertEq(address(rejector).balance, 0, "rejector received nothing");
        assertFalse(itwa.transferAuthorizationState(nonce), "nonce unused after native revert");
    }

    // -------------------------------------------------- observability

    /// @notice A settled nonce and a canceled nonce are both terminal on-chain (same boolean state), but are
    ///         distinguishable only by their distinct events; the nonce is a log topic only on cancellation.
    function test_observability_usedVsCanceledDistinguishableOnlyByEvent() public {
        ITransferWithAuthorization itwa = ITransferWithAuthorization(_aliceWallet);
        bytes32 aliceKeyHash = keccak256(abi.encodePacked(_alice));

        bytes32 usedNonce = keccak256("obs-used");
        bytes32 canceledNonce = keccak256("obs-canceled");
        uint256 value = 5 ether;

        vm.recordLogs();

        // settle one nonce
        bytes memory sig = _execEnvelope(_aliceWallet, _alicePk, aliceKeyHash, address(token), _charlie, value, usedNonce);
        vm.prank(_relayerA);
        itwa.executeTransferWithAuthorization(address(token), _charlie, value, VALID_AFTER, VALID_BEFORE, usedNonce, sig);

        // cancel a different nonce (signed form)
        bytes memory cancelSig = _cancelEnvelope(_aliceWallet, _alicePk, aliceKeyHash, canceledNonce);
        vm.prank(_relayerB);
        itwa.cancelTransferAuthorization(canceledNonce, cancelSig);

        // both nonces are terminal and on-chain indistinguishable by state
        assertTrue(itwa.transferAuthorizationState(usedNonce), "used nonce terminal");
        assertTrue(itwa.transferAuthorizationState(canceledNonce), "canceled nonce terminal");

        bytes32 usedTopic = keccak256("TransferAuthorizationUsed(address,address,address,uint256,bytes32)");
        bytes32 canceledTopic = keccak256("TransferAuthorizationCanceled(bytes32)");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawUsed;
        bool sawCanceled;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != _aliceWallet) continue;
            if (logs[i].topics[0] == usedTopic) {
                // Used: token/from/to indexed; value + nonce live in data (nonce is NOT a topic)
                assertEq(logs[i].topics.length, 4, "used has 3 indexed fields");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), _aliceWallet, "used from == account");
                (uint256 evValue, bytes32 evNonce) = abi.decode(logs[i].data, (uint256, bytes32));
                assertEq(evValue, value, "used value in data");
                assertEq(evNonce, usedNonce, "used nonce in data");
                sawUsed = true;
            } else if (logs[i].topics[0] == canceledTopic) {
                // Canceled: only authorizationNonce indexed (nonce IS a topic, cheaply filterable)
                assertEq(logs[i].topics.length, 2, "canceled has 1 indexed field");
                assertEq(logs[i].topics[1], canceledNonce, "canceled nonce is a topic");
                sawCanceled = true;
            }
        }
        assertTrue(sawUsed, "saw used event");
        assertTrue(sawCanceled, "saw canceled event");
    }
}
