// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC4337Account} from "src/interfaces/IERC4337Account.sol";
import {Errors} from "src/libraries/Errors.sol";

contract ValidateUserOpTest is Base {
    function setUp() public override {
        super.setUp();
    }

    struct _TestTemps {
        bytes32 userOpHash;
        address signer;
        uint256 privateKey;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 missingAccountFunds;
    }

    function test_validateUserOp_with_eoa_signer() external {
        vm.prank(_alice);

        bytes32 _aliceKeyHash = keccak256(abi.encodePacked(_alice));
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: _aliceKeyHash,
            validator: address(1)
        });
        address account = _factory.createAccount(
            address(_smartWallet),
            initialOwners,
            0
        );

        _TestTemps memory t;
        t.userOpHash = keccak256("123");
        t.signer = _alice;
        t.privateKey = _alicePk;
        (t.v, t.r, t.s) = vm.sign(t.privateKey, t.userOpHash);
        t.missingAccountFunds = 456;
        vm.deal(address(account), 1 ether);
        assertEq(address(account).balance, 1 ether);

        vm.etch(
            IERC4337Account(account).entryPoint(),
            address(new MockEntryPoint()).code
        );
        MockEntryPoint ep = MockEntryPoint(
            payable(IERC4337Account(account).entryPoint())
        );

        PackedUserOperation memory userOp;
        // Success returns 0.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, t.s, t.v)
        );
        assertEq(
            ep.validateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            0
        );
        assertEq(address(ep).balance, t.missingAccountFunds);
        // // Failure returns 1.
        userOp.signature = abi.encodePacked(
            _aliceKeyHash,
            abi.encodePacked(t.r, bytes32(uint256(t.s) ^ 1), t.v)
        );

        assertEq(
            ep.validateUserOp(
                address(account),
                userOp,
                t.userOpHash,
                t.missingAccountFunds
            ),
            1 << 96
        );
        assertEq(address(ep).balance, t.missingAccountFunds * 2);
        // Not entry point reverts.
        vm.expectRevert(Errors.NotEntryPoint.selector);
        IERC4337Account(account).validateUserOp(
            userOp,
            t.userOpHash,
            t.missingAccountFunds
        );
    }
}

// Mock contract moved from mocks/MockEntryPoint.sol
contract MockEntryPoint {
    mapping(address => uint256) public balanceOf;

    function depositTo(address to) public payable {
        balanceOf[to] += msg.value;
    }

    function withdrawTo(address to, uint256 amount) public payable {
        balanceOf[msg.sender] -= amount;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success);
    }

    function validateUserOp(
        address account,
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public payable returns (uint256 validationData) {
        validationData = IERC4337Account(payable(account)).validateUserOp(
            userOp,
            userOpHash,
            missingAccountFunds
        );
    }

    receive() external payable {
        depositTo(msg.sender);
    }
}
