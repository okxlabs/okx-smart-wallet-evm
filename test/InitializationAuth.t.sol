// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {InitialOwner} from "src/Types.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {IOwnerManager} from "src/interfaces/IOwnerManager.sol";
import {SmartWalletFactory} from "src/SmartWalletFactory.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {BaseAuthorization} from "src/BaseAuthorization.sol";

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

    function test_RevertWhen_Initialize_EIP7702_SelfInitialization() public {
        // Simulate EIP-7702 scenario
        _setCodeToEoa(address(_smartWallet), _bob);

        // Bob (as the EOA with wallet code) cannot initialize himself anymore
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_bob)),
            address(_ecdsaValidator)
        );

        // Self-initialization should fail (only factory can initialize)
        // Note: When using _setCodeToEoa, no immutable args are set, so getImmutableFactory() returns address(0)
        // The authorization check fails, which is the important behavior
        vm.prank(_bob);
        vm.expectRevert(); // Expect any revert - the important thing is that it reverts
        ISmartWallet(_bob).initialize(initialOwners);
    }

    function test_RevertWhen_Initialize_NoFactory() public {
        // Deploy a proxy without factory (simulating direct deployment)
        // This will have no immutable args
        address wallet = LibClone.deployERC1967(0, address(_smartWallet));

        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Alice tries to initialize wallet (should fail - no factory)
        vm.prank(_alice);
        vm.expectRevert(ISmartWallet.UnauthorizedInitialization.selector);
        ISmartWallet(wallet).initialize(initialOwners);

        // Even wallet itself cannot initialize (no factory address)
        vm.prank(wallet);
        vm.expectRevert(ISmartWallet.UnauthorizedInitialization.selector);
        ISmartWallet(wallet).initialize(initialOwners);
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

    function test_GetImmutableFactory() public {
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Case 1: Wallet deployed through factory (has immutable args) - should return factory address
        address factoryWallet = factory.createAccount(initialOwners, 456);
        address retrievedFactory = BaseAuthorization(factoryWallet)
            .getImmutableFactory();
        assertEq(
            retrievedFactory,
            address(factory),
            "Factory-deployed wallet should return factory address"
        );

        // Case 2: Test with different factory to ensure it returns the correct one
        SmartWalletFactory factory2 = new SmartWalletFactory(
            address(_smartWallet)
        );
        address factory2Wallet = factory2.createAccount(initialOwners, 789);
        address retrieved2Factory = BaseAuthorization(factory2Wallet)
            .getImmutableFactory();
        assertEq(
            retrieved2Factory,
            address(factory2),
            "Second factory deployment should return correct factory address"
        );

        // Case 3: Verify different factories return different addresses
        assertTrue(
            retrievedFactory != retrieved2Factory,
            "Different factories should return different addresses"
        );

        // Case 4: Test with different salt values from same factory should return same factory address
        address factoryWallet3 = factory.createAccount(initialOwners, 999);
        address retrievedFactory3 = BaseAuthorization(factoryWallet3)
            .getImmutableFactory();
        assertEq(
            retrievedFactory3,
            address(factory),
            "Different salt should return same factory address"
        );
        assertEq(
            retrievedFactory,
            retrievedFactory3,
            "Same factory should return same address regardless of salt"
        );
    }
}
