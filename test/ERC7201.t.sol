// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";

contract ERC7201Test is Base {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Test the namespaceAndVersion function
    function test_namespaceAndVersion() external view {
        assertEq(_smartWallet.namespaceAndVersion(), "OKX.SmartWallet.1.0.0");
    }

    /// @notice Test the CUSTOM_STORAGE_ROOT function
    function test_CUSTOM_STORAGE_ROOT() external view {
        assertEq(
            _smartWallet.CUSTOM_STORAGE_ROOT(),
            0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00
        );
    }
}
