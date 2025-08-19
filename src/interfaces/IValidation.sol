// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import {BatchedCall} from "../Types.sol";

interface IValidation {
    function getValidationTypedHash(
        BatchedCall calldata batchedCall
    ) external view returns (bytes32);
}
