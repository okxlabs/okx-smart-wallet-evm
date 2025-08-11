// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Call} from "../Types.sol";

interface IValidation {
    event ValidatorAdded(address validator);

    function getValidationTypedHash(
        uint256 nonce,
        Call[] calldata calls
    ) external view returns (bytes32);

    function computeValidatorAddress(
        address validatorImpl,
        bytes calldata immutableArgs
    ) external view returns (address);
}
