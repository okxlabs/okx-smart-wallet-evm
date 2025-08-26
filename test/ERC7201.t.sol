// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {ERC7201} from "../src/ERC7201.sol";

contract ERC7201Test is Base {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Test the namespaceAndVersion function
    function test_namespaceAndVersion() external {
        ERC7201 erc7201 = new ERC7201();
        assertEq(erc7201.namespaceAndVersion(), "OKX.SmartWallet.1.0.0");
    }

    /// @notice Test the CUSTOM_STORAGE_ROOT function
    function test_CUSTOM_STORAGE_ROOT() external {
        ERC7201 erc7201 = new ERC7201();
        assertEq(
            erc7201.CUSTOM_STORAGE_ROOT(),
            0x02a90b95e07536939d6b1617e9cf25c8d725ec1c5c4c03ccc00770cd202e6e00
        );
    }
}
