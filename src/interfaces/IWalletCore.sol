// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IStorage} from "./IStorage.sol";
import {Call, Session} from "src/Types.sol";

interface IWalletCore is IERC165 {
    // EVENTS
    event StorageInitialized();
    event StorageCreated(address storageAddress);

    function initialize() external returns (address storageAddress);

    function executeFromSelf(Call[] calldata calls) external;

    function executeFromRelayer(
        Call[] calldata calls,
        bytes calldata validatorData
    ) external;

    function simulateExecuteFromRelayer(
        Call[] calldata calls,
        bytes calldata validatorData
    ) external;

    function executeFromExecutor(
        Call[] calldata calls,
        Session calldata session
    ) external;

    function addValidator(bytes32 keyHash, address validator) external;

    function getMainStorage() external view returns (IStorage);

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);

    function getNonce() external view returns (uint256);
}
