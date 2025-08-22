// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";

interface ISmartWallet is IERC165 {
    // EVENTS
    event StorageInitialized();
    event StorageCreated(address storageAddress);

    function initialize(InitialOwner[] calldata initialOwners) external;

    function execute(Call[] calldata calls) external;

    function executeWithRelayer(
        BatchedCall calldata batchedCall,
        bytes calldata validatorData
    ) external;

    function simulateExecuteWithRelayer(
        BatchedCall calldata batchedCall,
        address validator,
        bytes calldata validatorData
    ) external;

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);
}
