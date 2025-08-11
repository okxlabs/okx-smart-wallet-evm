// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract FallbackHandlerTest is Base {
    function test_receive_accepts_ether() public {
        uint256 initialBalance = _alice.balance;
        (bool success, ) = payable(_alice).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(_alice.balance, initialBalance + 1 ether);
    }

    function test_fallback_reverts_for_invalid_selector() public {
        // Test case 1: completely invalid selector
        bytes memory invalidData = abi.encodeWithSelector(
            bytes4(keccak256("invalidFunction()")),
            address(this)
        );
        (bool success, ) = _alice.call(invalidData);
        assert(!success);
    }

    function test_fallback_handles_erc721_receive() public {
        // Create calldata for onERC721Received
        bytes memory data = abi.encodeWithSelector(
            0x150b7a02, // onERC721Received selector
            address(this),
            address(this),
            1,
            ""
        );

        // Call fallback function
        (bool success, bytes memory returnData) = _alice.call(data);

        // Verify success and returned selector
        assertTrue(success);
        assertEq(bytes4(returnData), bytes4(0x150b7a02));
    }

    function test_fallback_handles_erc1155_receive() public {
        // Create calldata for onERC1155Received
        bytes memory data = abi.encodeWithSelector(
            0xf23a6e61, // onERC1155Received selector
            address(this),
            address(this),
            1,
            1,
            ""
        );

        // Call fallback function
        (bool success, bytes memory returnData) = _alice.call(data);

        // Verify success and returned selector
        assertTrue(success);
        assertEq(bytes4(returnData), bytes4(0xf23a6e61));
    }

    function test_fallback_handles_erc1155_batch_receive() public {
        // Create arrays for batch transfer
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        amounts[0] = 10;
        amounts[1] = 20;

        // Create calldata for onERC1155BatchReceived
        bytes memory data = abi.encodeWithSelector(
            0xbc197c81, // onERC1155BatchReceived selector
            address(this),
            address(this),
            ids,
            amounts,
            ""
        );

        // Call fallback function
        (bool success, bytes memory returnData) = _alice.call(data);

        // Verify success and returned selector
        assertTrue(success);
        assertEq(bytes4(returnData), bytes4(0xbc197c81));
    }

    function test_supports_token_receive_interfaces() public view {
        assertEq(
            IERC165(_alice).supportsInterface(
                type(IERC721Receiver).interfaceId
            ),
            true
        );
        assertEq(
            IERC165(_alice).supportsInterface(
                type(IERC1155Receiver).interfaceId
            ),
            true
        );
        assertEq(
            IERC165(_alice).supportsInterface(type(IERC1271).interfaceId),
            true
        );
        assertEq(
            IERC165(_alice).supportsInterface(type(IERC165).interfaceId),
            true
        );
    }
}
