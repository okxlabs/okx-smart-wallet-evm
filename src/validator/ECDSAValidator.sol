// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IValidator} from "../interfaces/IValidator.sol";
import {Errors} from "../libraries/Errors.sol";

contract ECDSAValidator is IValidator {
    using ECDSA for bytes32;

    /**
     * @notice Validates a signature against the stored signer address
     * @dev Uses ECDSA recovery to verify the signature matches the typed data hash
     * @param msgHash The hash of the message being validated (may be ignored by this implementation).
     * @param validatorData Payload (e.g. signature) required for validation.
     */
    function validate(
        bytes32 msgHash,
        bytes calldata validatorData
    ) external view returns (bool) {
        (address recoveredSigner, , ) = msgHash.tryRecover(validatorData);
        return recoveredSigner == getSigner();
    }

    /**
     * @notice Returns the signer address stored in this validator clone
     * @dev Retrieves and decodes the initialization arguments used when this clone was created
     * @return signer The stored signer address that is authorized to sign transactions
     */
    function getSigner() public view returns (address signer) {
        assembly {
            extcodecopy(address(), 12, 57, 20)
            signer := mload(0)
        }
    }

    /**
     * @notice Simulate validation process for gas measurement.
     * @dev This function should not revert.
     * @param msgHash The hash of the message being validated (may be ignored by this implementation).
     * @param validatorData Payload (e.g. signature) required for validation.
     */
    function simulate(
        bytes32 msgHash,
        bytes calldata validatorData
    ) external view returns (bool) {
        (address recoveredSigner, , ) = msgHash.tryRecover(validatorData);
        return recoveredSigner == getSigner();
    }
}
