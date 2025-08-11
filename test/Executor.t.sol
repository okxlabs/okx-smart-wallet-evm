// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IExecutor} from "src/interfaces/IExecutor.sol";
import {IStorage} from "src/interfaces/IStorage.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import {MockExecutor} from "src/test/MockExecutor.sol";
import {Call, Session} from "src/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Static} from "src/libraries/Static.sol";
import "./Base.t.sol";

contract ExecutorTest is Base {
    using ECDSA for bytes32;
    using Clones for address;

    MockERC20 mockToken;
    MockExecutor mockExecutor;
    IStorage store;

    address receipt;
    uint256 receiptPri;
    address sessionOwner;
    uint256 sessionOwnerPri;

    Session session;

    uint256 validAfter = 0;
    uint256 validUntil = block.timestamp + 1000;

    function setUp() public override {
        super.setUp();

        (sessionOwner, sessionOwnerPri) = makeAddrAndKey("sessionOwner");
        (receipt, receiptPri) = makeAddrAndKey("receipt");

        vm.prank(_alice);
        mockToken = new MockERC20();
        mockExecutor = new MockExecutor(IWalletCore(_alice));

        session = Session({
            id: 0,
            executor: address(mockExecutor),
            validUntil: validUntil,
            validAfter: validAfter,
            preHook: "",
            postHook: "",
            signature: ""
        });

        bytes32 hash = IExecutor(_alice).getSessionTypedHash(session);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, hash);
        bytes memory sessionSignature = abi.encodePacked(r, s, v);

        // 创建 keyHash 并编码到签名中
        bytes32 keyHash = keccak256(abi.encodePacked(_alice));
        session.signature = abi.encodePacked(keyHash, sessionSignature);

        // 注册 validator (使用实际的 validator 实现)
        _addValidator(_alice);

        store = IStorage(WalletCore(payable(_alice)).getMainStorage());
    }

    function test_execute_reverts_for_invalid_session() public {
        vm.prank(_bob);

        _walletCore = new WalletCore(address(_storageImpl), NAME, VERSION);
        _setCodeToEOA(address(_walletCore), _bob);

        IWalletCore(_bob).initialize();

        Session memory bobSession = Session({
            id: 0,
            executor: address(mockExecutor),
            validUntil: validUntil,
            validAfter: validAfter,
            preHook: "",
            postHook: "",
            signature: ""
        });

        bytes32 hash = IExecutor(_bob).getSessionTypedHash(bobSession);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hash);
        bytes memory sessionSignature = abi.encodePacked(r, s, v);

        // 创建 keyHash 并编码到签名中
        bytes32 keyHash = keccak256(abi.encodePacked(_bob));
        session.signature = abi.encodePacked(keyHash, sessionSignature);

        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });
        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        vm.expectRevert();
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 0);
    }

    function test_session_validation_fails_for_wrong_wallet() public {
        vm.prank(_bob);

        _walletCore = new WalletCore(address(_storageImpl), NAME, VERSION);
        _setCodeToEOA(address(_walletCore), _bob);

        IWalletCore(_bob).initialize();

        Session memory bobSession = Session({
            id: 0,
            executor: address(mockExecutor),
            validUntil: validUntil,
            validAfter: validAfter,
            preHook: "",
            postHook: "",
            signature: ""
        });

        bytes32 hash = IExecutor(_bob).getSessionTypedHash(bobSession);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_bobPk, hash);
        bytes memory sessionSignature = abi.encodePacked(r, s, v);

        // 创建 keyHash 并编码到签名中
        bytes32 keyHash = keccak256(abi.encodePacked(_bob));
        bobSession.signature = abi.encode(keyHash, sessionSignature);

        vm.prank(_alice);
        vm.expectRevert();
        IExecutor(_alice).validateSession(bobSession);
    }

    function test_session_validates_successfully() public {
        vm.prank(_alice);
        IExecutor(session.executor).validateSession(session);
    }

    function test_execute_reverts_for_invalid_validator() public {
        // Use a non-existent validator address (zero address)
        session = Session({
            id: 0,
            executor: address(mockExecutor),
            validUntil: validUntil,
            validAfter: validAfter,
            preHook: "",
            postHook: "",
            signature: ""
        });

        bytes32 hash = IExecutor(_alice).getSessionTypedHash(session);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, hash);
        bytes memory sessionSignature = abi.encodePacked(r, s, v);

        // 使用 address(0) 作为 keyHash 来测试无效 validator
        bytes32 invalidKeyHash = keccak256(abi.encodePacked(address(0)));
        session.signature = abi.encodePacked(invalidKeyHash, sessionSignature);

        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });

        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValidator.selector, address(0))
        );
        vm.prank(sessionOwner);
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 0);
    }

    function test_execute_reverts_for_invalid_executor() public {
        vm.prank(_alice);
        MockExecutor mockExecutor2 = new MockExecutor(IWalletCore(_alice));

        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });

        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        vm.expectRevert(Errors.InvalidExecutor.selector);
        mockExecutor2.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 0);
    }

    function test_session_executes_with_valid_signature() public {
        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });
        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 10);
    }

    function test_execute_reverts_for_expired_session() public {
        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });

        vm.warp(session.validUntil + 1000);

        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        vm.expectRevert(Errors.InvalidSession.selector);
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 0);
    }

    function test_session_can_be_revoked() public {
        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });
        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 10);

        vm.prank(_alice);
        store.revokeSession(session.id);

        vm.prank(sessionOwner);
        vm.expectRevert(Errors.InvalidSession.selector);
        mockExecutor.execute(singleCallArray, session);
    }

    function test_session_can_be_recovered_after_invalidation() public {
        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });
        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 10);

        vm.prank(_alice);
        store.revokeSession(session.id);

        vm.prank(sessionOwner);
        vm.expectRevert(Errors.InvalidSession.selector);
        mockExecutor.execute(singleCallArray, session);
    }

    function test_session_revocation_reverts_for_non_owner() public {
        Call memory call = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt,
                10
            )
        });
        Call[] memory singleCallArray = new Call[](1);
        singleCallArray[0] = call;

        vm.prank(sessionOwner);
        mockExecutor.execute(singleCallArray, session);

        assertEq(mockToken.balanceOf(receipt), 10);
        vm.prank(_bob);

        vm.expectRevert(Errors.InvalidOwner.selector);
        store.revokeSession(session.id);
    }
}
