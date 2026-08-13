// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IHook} from "src/interfaces/IHook.sol";
import {IHookTransferAuthorization} from "src/interfaces/IHookTransferAuthorization.sol";
import {Call} from "src/Types.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Shared hook mocks
/// @notice Reusable spending-policy hook fixtures for the TWA and EIP-1271 test suites, so each hook is
///         defined once. (Execute-path-only fixtures specific to Hook.t.sol live there.)

/// @dev Blocks any spend by reverting in the TWA pre-callback. Advertises `IHookTransferAuthorization`.
contract RevertingHook is IHookTransferAuthorization {
    error HookBlocked();

    function preTransferWithAuthorization(bytes32, address, address, uint256, address)
        external
        payable
        returns (bytes memory)
    {
        revert HookBlocked();
    }

    function postTransferWithAuthorization(bytes calldata, address) external payable {}

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IHookTransferAuthorization).interfaceId ||
            interfaceId == type(IHook).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

/// @dev TWA-aware recording hook: records the authorizing keyHash + typed transfer fields forwarded
///      through the dedicated `IHookTransferAuthorization` callbacks.
contract RecordingHook is IHookTransferAuthorization {
    uint256 public preCount;
    uint256 public postCount;
    bytes32 public lastKeyHash;
    address public lastToken;
    address public lastTo;
    uint256 public lastValue;
    address public lastCaller;
    bytes32 public lastPostRetHash;

    function preTransferWithAuthorization(bytes32 keyHash, address token, address to, uint256 value, address caller)
        external
        payable
        returns (bytes memory)
    {
        preCount++;
        lastKeyHash = keyHash;
        lastToken = token;
        lastTo = to;
        lastValue = value;
        lastCaller = caller;
        return abi.encode(keyHash, token, to, value, caller);
    }

    function postTransferWithAuthorization(bytes calldata preRet, address caller) external payable {
        postCount++;
        lastCaller = caller;
        lastPostRetHash = keccak256(preRet);
    }

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IHookTransferAuthorization).interfaceId ||
            interfaceId == type(IHook).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

/// @dev Implements the TWA callbacks but does NOT advertise the interface via ERC-165 — proves a hook that
///      fails the supportsInterface probe is treated as incompatible.
contract NonAdvertisingHook is IHookTransferAuthorization {
    uint256 public preCount;

    function preTransferWithAuthorization(bytes32, address, address, uint256, address)
        external
        payable
        returns (bytes memory)
    {
        preCount++;
        return "";
    }

    function postTransferWithAuthorization(bytes calldata, address) external payable {}

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IHook).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

/// @dev A truly legacy execute-path hook that does NOT implement `supportsInterface` at all — a raw
///      `IERC165(hook).supportsInterface(...)` would revert; the gas-capped probe must return false.
///      It intentionally does not inherit `IHook`, because `IHook` now extends `IERC165`.
contract LegacyHookNoErc165 {
    uint256 public preCount;

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        preCount++;
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }
}

/// @dev Legacy fallback that returns ABI-encoded dynamic bytes for every selector. An unchecked
///      ERC-165 probe reads its non-zero offset word as `true`, and its fallback can also swallow
///      both TWA callbacks. The checked ERC-165 probe must reject it.
contract LegacyTruthyFallbackHook {
    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(bytes(""));
    }
}

contract LegacyBoolFallbackHook {
    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 1)
            return(0, 0x20)
        }
    }
}

/// @dev Advertises `IHook` and approves/rejects EIP-1271 by a constructor flag.
contract SigCheckHook is IHook {
    bool public immutable approve;

    constructor(bool approve_) {
        approve = approve_;
    }

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external view returns (bool) {
        return approve;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return
            id == type(IHook).interfaceId ||
            id == type(IERC165).interfaceId;
    }
}

/// @dev Implements every callback but advertises ONLY `IHookTransferAuthorization`, not `IHook` — so the
///      1271 gate's `type(IHook).interfaceId` ERC-165 probe fails and the signature is rejected fail-closed.
contract TwaOnlySigHook is IHookTransferAuthorization {
    function preTransferWithAuthorization(bytes32, address, address, uint256, address)
        external
        payable
        returns (bytes memory)
    {
        return "";
    }

    function postTransferWithAuthorization(bytes calldata, address) external payable {}

    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return
            id == type(IHookTransferAuthorization).interfaceId ||
            id == type(IERC165).interfaceId;
    }
}

/// @dev Advertises `IHook` but returns malformed (empty) data from `isValidSignatureCheck`, exercising the
///      `ret.length == 32` guard: the gate must reject fail-closed WITHOUT reverting `isValidSignature`.
contract MalformedSigHook is IHook {
    function preCheck(Call[] calldata, address) external payable returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata, address) external payable {}

    function isValidSignatureCheck(address, bytes32, bytes calldata) external pure returns (bool) {
        assembly {
            return(0, 0) // empty returndata (not 32 bytes)
        }
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return
            id == type(IHook).interfaceId ||
            id == type(IERC165).interfaceId;
    }
}
