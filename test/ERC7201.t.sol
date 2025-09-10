// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";

contract ERC7201Test is Base {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Test the namespaceAndVersion function
    function test_namespaceAndVersion() external view {
        assertEq(_smartWallet.namespaceAndVersion(), "SmartWallet.1.0.0");
    }

    /// @notice Test the CUSTOM_STORAGE_ROOT function
    function test_CUSTOM_STORAGE_ROOT() external view {
        assertEq(
            _smartWallet.CUSTOM_STORAGE_ROOT(),
            0xd2f25270280c292d8930a730093bb680163a837f93acc639d858c440b5c53800
        );
    }
}
