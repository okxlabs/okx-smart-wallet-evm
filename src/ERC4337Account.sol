// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC4337Account} from "./interfaces/IERC4337Account.sol";
import {Errors} from "./libraries/Errors.sol";
import {UserOperationLib} from "account-abstraction/core/UserOperationLib.sol";

abstract contract ERC4337Account is IERC4337Account {
    /// @notice Modifier to ensure the caller is the EntryPoint
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint()) revert Errors.NotEntryPoint();
        _;
    }

    /// @notice Returns the EntryPoint address
    function entryPoint() public pure returns (address) {
        return 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    }

    /// Sends to the entrypoint (msg.sender) the missing funds for this transaction.
    /// SubClass MAY override this method for better funds management
    /// (e.g. send to the entryPoint more than the minimum required, so that in future transactions
    /// it will not be required to send again).
    /// @param missingAccountFunds - The minimum value this method should send the entrypoint.
    ///                              This value MAY be zero, in case there is enough deposit,
    ///                              or the userOp has a paymaster.
    function _payPrefund(uint256 missingAccountFunds) internal virtual {
        if (missingAccountFunds != 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = payable(msg.sender).call{
                value: missingAccountFunds
            }("");
            // Ignore failure (its EntryPoint's job to verify, not account.)
            success; // Explicitly unused
        }
    }

    /// @notice Returns the hash of the user operation without the chain id
    /// @param userOp The user operation to hash
    /// @return The hash of the user operation without the chain id
    function getUserOpHashWithoutChainId(
        PackedUserOperation calldata userOp
    ) public view virtual returns (bytes32) {
        return
            keccak256(abi.encode(UserOperationLib.hash(userOp), entryPoint()));
    }
}
