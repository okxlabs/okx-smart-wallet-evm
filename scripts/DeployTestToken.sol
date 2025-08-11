// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "lib/forge-std/src/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test USDC Token", "USDC") {
        _mint(msg.sender, 1000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract DeployTestToken is Script {
    function run(address recipient) external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy the test token
        TestToken token = new TestToken();

        // Mint additional tokens to the specified address
        token.transfer(recipient, 1000_000 * 10 ** token.decimals());

        console.log("TestToken deployed at: %s", address(token));
        console.log("Minted 1000_000 tokens to: %s", recipient);

        vm.stopBroadcast();
    }
}
