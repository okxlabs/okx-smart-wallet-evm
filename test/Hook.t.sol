// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Base.t.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {IWalletCore} from "src/interfaces/IWalletCore.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import {MockHook} from "src/test/MockHook.sol";
import {MockExecutor} from "src/test/MockExecutor.sol";
import {Call, Session} from "src/Types.sol";
import {Static} from "src/libraries/Static.sol";

contract HookTest is Base {
    MockERC20 mockToken;
    MockExecutor mockExecutor;
    MockHook mockHook;

    address receipt1;
    uint256 receipt1Pri;
    address receipt2;
    uint256 receipt2Pri;
    address sessionOwner;
    uint256 sessionOwnerPri;

    Session session;

    uint256 validAfter = 0;
    uint256 validUntil = type(uint256).max;

    function setUp() public override {
        super.setUp();

        (sessionOwner, sessionOwnerPri) = makeAddrAndKey("sessionOwner");
        (receipt1, receipt2Pri) = makeAddrAndKey("receipt1");
        (receipt2, receipt2Pri) = makeAddrAndKey("receipt2");

        vm.prank(_alice);
        mockToken = new MockERC20();
        mockHook = new MockHook();
        mockExecutor = new MockExecutor(IWalletCore(_alice));

        session = Session({
            id: 0,
            executor: address(mockExecutor),
            validUntil: validUntil,
            validAfter: validAfter,
            preHook: bytes.concat(
                bytes20(address(mockHook)),
                abi.encode(address(mockToken), 50 ether)
            ),
            postHook: bytes.concat(bytes20(address(mockHook))),
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
    }

    function test_hook_executes_transfers_within_limit() public {
        Call memory call1 = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt1,
                20 ether
            )
        });
        Call memory call2 = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt2,
                30 ether
            )
        });

        Call[] memory multiCallArray = new Call[](2);
        multiCallArray[0] = call1;
        multiCallArray[1] = call2;

        vm.prank(sessionOwner);
        mockExecutor.execute(multiCallArray, session);

        assertEq(
            mockToken.balanceOf(receipt1),
            20 ether,
            "Invalid balance for receipt1"
        );
        assertEq(
            mockToken.balanceOf(receipt2),
            30 ether,
            "Invalid balance for receipt2"
        );
    }

    function test_hook_reverts_when_exceeding_transfer_limit() public {
        Call memory call1 = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt1,
                30 ether
            )
        });
        Call memory call2 = Call({
            target: address(mockToken),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                receipt2,
                30 ether
            )
        });

        Call[] memory multiCallArray = new Call[](2);
        multiCallArray[0] = call1;
        multiCallArray[1] = call2;

        vm.prank(sessionOwner);
        vm.expectRevert("Total transfer amount exceeds limit");
        mockExecutor.execute(multiCallArray, session);
    }
}
