// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev Contract that handles token receiving functionality, implementing both IERC165 and IModule interfaces.
 * Supports ERC721 and ERC1155 token receiving through standard interfaces.
 */
abstract contract FallbackHandler is IERC165 {
    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable virtual {}

    /**
     * @dev Fallback function that handles token receiving callbacks
     * Returns the function selector for ERC721 and ERC1155 token receiving functions
     */
    fallback() external payable {
        assembly {
            let s := shr(224, calldataload(0))
            // 0x150b7a02: `onERC721Received(address,address,uint256,bytes)`.
            // 0xf23a6e61: `onERC1155Received(address,address,uint256,uint256,bytes)`.
            // 0xbc197c81: `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)`.
            if or(eq(s, 0x150b7a02), or(eq(s, 0xf23a6e61), eq(s, 0xbc197c81))) {
                mstore(0x20, s) // Store `msg.sig`.
                return(0x3c, 0x20) // Return `msg.sig`.
            }
        }

        revert();
    }

    /**
     * @dev Implementation of IERC165 interface detection
     * @param interfaceId The interface identifier to check
     * @return bool True if the contract supports the interface
     */
    function supportsInterface(
        bytes4 interfaceId
    ) external view virtual override returns (bool) {
        // 0x150b7a02: `type(IERC721Receiver).interfaceId`.
        // 0x4e2312e0: `type(IERC1155Receiver).interfaceId`.
        // 0x1626ba7e: `type(IERC1271).interfaceId`.
        // 0x01ffc9a7: `type(IERC165).interfaceId`.
        return
            interfaceId == 0x150b7a02 ||
            interfaceId == 0x4e2312e0 ||
            interfaceId == 0x1626ba7e ||
            interfaceId == 0x01ffc9a7;
    }
}
