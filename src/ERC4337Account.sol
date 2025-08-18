// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.23;

import {IERC4337AccountLocal} from "./interfaces/IERC4337AccountLocal.sol";
import {PackedUserOperation} from "./Types4337.sol";

abstract contract ERC4337Account is IERC4337AccountLocal {

    /// @notice Modifier to ensure the caller is the EntryPoint
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint()) revert NotEntryPoint();
        _;
    }

    /// @notice Returns the EntryPoint address
    function entryPoint() public pure returns (address) {
        return 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;
    }

    /**
     * Sends to the entrypoint (msg.sender) the missing funds for this transaction.
     * SubClass MAY override this method for better funds management
     * (e.g. send to the entryPoint more than the minimum required, so that in future transactions
     * it will not be required to send again).
     * @param missingAccountFunds - The minimum value this method should send the entrypoint.
     *                              This value MAY be zero, in case there is enough deposit,
     *                              or the userOp has a paymaster.
     */
    function _payPrefund(uint256 missingAccountFunds) internal virtual {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{
                    value: missingAccountFunds
                }("");
            (success);
            // Ignore failure (its EntryPoint's job to verify, not account.)
        }
    }
    
    
}