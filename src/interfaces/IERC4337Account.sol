// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IAccount, PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";

interface IERC4337Account is IAccount {
    /// @notice Returns the EntryPoint address
    function entryPoint() external view returns (address);

    function getUserOpHashWithoutChainId(
        PackedUserOperation calldata userOp
    ) external view returns (bytes32);
}
