// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract FallbackHandlerTest is Base {
    function test_Receive_AcceptsEther_Success() public {
        uint256 initialBalance = _aliceWallet.balance;
        (bool success, ) = payable(_aliceWallet).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(_aliceWallet.balance, initialBalance + 1 ether);
    }

    function test_RevertWhen_Fallback_InvalidSelector() public {
        // Test case 1: completely invalid selector
        bytes memory invalidData = abi.encodeWithSelector(
            bytes4(keccak256("invalidFunction()")),
            address(this)
        );
        (bool success, ) = _aliceWallet.call(invalidData);
        assertFalse(success);
    }

    function test_Fallback_HandlesErc721Receive_Success() public {
        // Create calldata for onERC721Received
        bytes memory data = abi.encodeWithSelector(
            IERC721Receiver.onERC721Received.selector,
            address(this),
            address(this),
            1,
            ""
        );

        // Call fallback function
        (bool success, bytes memory returnData) = _aliceWallet.call(data);

        // Verify success and returned selector
        assertTrue(success);
        assertEq(bytes4(returnData), IERC721Receiver.onERC721Received.selector);
    }

    function test_Fallback_HandlesErc1155Receive_Success() public {
        // Create calldata for onERC1155Received
        bytes memory data = abi.encodeWithSelector(
            IERC1155Receiver.onERC1155Received.selector,
            address(this),
            address(this),
            1,
            1,
            ""
        );

        // Call fallback function
        (bool success, bytes memory returnData) = _aliceWallet.call(data);

        // Verify success and returned selector
        assertTrue(success);
        assertEq(
            bytes4(returnData),
            IERC1155Receiver.onERC1155Received.selector
        );
    }

    function test_Fallback_HandlesErc1155BatchReceive_Success() public {
        // Create arrays for batch transfer
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        amounts[0] = 10;
        amounts[1] = 20;

        // Create calldata for onERC1155BatchReceived
        bytes memory data = abi.encodeWithSelector(
            IERC1155Receiver.onERC1155BatchReceived.selector,
            address(this),
            address(this),
            ids,
            amounts,
            ""
        );

        // Call fallback function
        (bool success, bytes memory returnData) = _aliceWallet.call(data);

        // Verify success and returned selector
        assertTrue(success);
        assertEq(
            bytes4(returnData),
            IERC1155Receiver.onERC1155BatchReceived.selector
        );
    }

    function test_SupportsInterface_TokenReceiveInterfaces_Success()
        public
        view
    {
        assertEq(
            IERC165(_aliceWallet).supportsInterface(
                type(IERC721Receiver).interfaceId
            ),
            true
        );
        assertEq(
            IERC165(_aliceWallet).supportsInterface(
                type(IERC1155Receiver).interfaceId
            ),
            true
        );
        assertEq(
            IERC165(_aliceWallet).supportsInterface(type(IERC1271).interfaceId),
            true
        );
        assertEq(
            IERC165(_aliceWallet).supportsInterface(type(IERC165).interfaceId),
            true
        );
    }
}
