// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {InitialOwner} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract InitializationAuthTest is Base {
    SmartWalletFactory public factory;

    function setUp() public override {
        super.setUp();
        // Deploy factory with the implementation
        factory = new SmartWalletFactory(address(_smartWallet));
    }

    function test_Initialize_FactoryCanInitialize_Success() public {
        // Factory deploys and initializes a wallet
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Deploy through factory
        address wallet = factory.createAccount(initialOwners, 123);

        // Verify owner was set correctly
        (address validator, , , , ) = IOwnerManager(wallet).getOwnerSettings(
            keccak256(abi.encodePacked(_alice))
        );
        assertEq(validator, address(_ecdsaValidator));
    }

    function test_RevertWhen_Initialize_UnauthorizedCaller() public {
        // Deploy wallet through factory but don't initialize
        bytes memory factoryAddress = abi.encode(address(factory));
        address wallet = LibClone.deployERC1967(
            0,
            address(_smartWallet),
            factoryAddress
        );

        // Try to initialize from unauthorized address (not factory, not self)
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        vm.prank(_bob); // Bob is not authorized
        vm.expectRevert(ISmartWallet.UnauthorizedInitialization.selector);
        ISmartWallet(wallet).initialize(initialOwners);
    }

    function test_Initialize_SelfCanInitialize_EIP7702_Success() public {
        // Simulate EIP-7702 scenario
        _setCodeToEoa(address(_smartWallet), _bob);

        // Bob (as the EOA with wallet code) can initialize himself
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_bob)),
            address(_ecdsaValidator)
        );

        vm.prank(_bob); // Self-initialization
        ISmartWallet(_bob).initialize(initialOwners);

        // Verify owner was set
        (address validator2, , , , ) = IOwnerManager(_bob).getOwnerSettings(
            keccak256(abi.encodePacked(_bob))
        );
        assertEq(validator2, address(_ecdsaValidator));
    }

    function test_RevertWhen_Initialize_NotSelfInEIP7702() public {
        // Deploy a proxy without factory (simulating direct EIP-7702)
        // This will have no immutable args
        address wallet = LibClone.deployERC1967(0, address(_smartWallet));

        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Alice tries to initialize wallet (should fail - not self, no factory)
        vm.prank(_alice);
        vm.expectRevert(ISmartWallet.UnauthorizedInitialization.selector);
        ISmartWallet(wallet).initialize(initialOwners);

        // But wallet itself can initialize
        vm.prank(wallet);
        ISmartWallet(wallet).initialize(initialOwners);

        // Verify initialization succeeded
        (address validator3, , , , ) = IOwnerManager(wallet).getOwnerSettings(
            keccak256(abi.encodePacked(_alice))
        );
        assertEq(validator3, address(_ecdsaValidator));
    }

    function test_Initialize_FactoryAddressFromImmutableArgs() public {
        // Create wallet with factory address in immutable args
        bytes memory factoryAddress = abi.encode(address(factory));
        address wallet = LibClone.deployERC1967(
            0,
            address(_smartWallet),
            factoryAddress
        );

        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Factory can initialize
        vm.prank(address(factory));
        ISmartWallet(wallet).initialize(initialOwners);

        // Verify initialization succeeded
        (address validator4, , , , ) = IOwnerManager(wallet).getOwnerSettings(
            keccak256(abi.encodePacked(_alice))
        );
        assertEq(validator4, address(_ecdsaValidator));
    }

    function test_RevertWhen_Initialize_WrongFactoryAddress() public {
        // Create a different factory
        SmartWalletFactory wrongFactory = new SmartWalletFactory(
            address(_smartWallet)
        );

        // Deploy with original factory address in immutable args
        bytes memory factoryAddress = abi.encode(address(factory));
        address wallet = LibClone.deployERC1967(
            0,
            address(_smartWallet),
            factoryAddress
        );

        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Wrong factory tries to initialize
        vm.prank(address(wrongFactory));
        vm.expectRevert(ISmartWallet.UnauthorizedInitialization.selector);
        ISmartWallet(wallet).initialize(initialOwners);
    }

    function test_Initialize_PreventsFrontRunning() public {
        // This test demonstrates the security improvement:
        // An attacker cannot front-run initialization

        // Deploy through factory
        InitialOwner[] memory legitOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Attacker prepares malicious owners
        InitialOwner[] memory attackerOwners = _createSingleOwner(
            keccak256(abi.encodePacked(address(0xdead))),
            address(_ecdsaValidator)
        );

        // Deploy wallet (simulating the moment before factory initializes)
        bytes memory factoryAddress = abi.encode(address(factory));
        address wallet = LibClone.deployERC1967(
            0,
            address(_smartWallet),
            factoryAddress
        );

        // Attacker tries to front-run initialization
        vm.prank(address(0xdead));
        vm.expectRevert(ISmartWallet.UnauthorizedInitialization.selector);
        ISmartWallet(wallet).initialize(attackerOwners);

        // Legitimate factory initialization succeeds
        vm.prank(address(factory));
        ISmartWallet(wallet).initialize(legitOwners);

        // Verify legitimate owner was set
        (address validator5, , , , ) = IOwnerManager(wallet).getOwnerSettings(
            keccak256(abi.encodePacked(_alice))
        );
        assertEq(validator5, address(_ecdsaValidator));
    }
}
