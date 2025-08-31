// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Base} from "./Base.t.sol";
import {IOwnersManager} from "src/interfaces/IOwnersManager.sol";
import {ISmartWallet} from "src/interfaces/ISmartWallet.sol";
import {Call, BatchedCall, InitialOwner} from "src/Types.sol";

contract FactoryTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_create_wallet_with_factory() external {
        vm.prank(_alice);

        ISmartWallet wallet = ISmartWallet(
            _deployAccountSingleOwner(
                keccak256(abi.encodePacked(_alice)),
                address(_ecdsaValidator),
                0
            )
        );

        assertEq(
            IOwnersManager(address(wallet)).hasOwner(
                keccak256(abi.encodePacked(_alice))
            ),
            true
        );
    }

    function test_predict_address() external {
        vm.prank(_alice);

        address wallet = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            0
        );

        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        address predictedAddress = _factory.getAddress(initialOwners, 0);

        assertEq(wallet, predictedAddress);
    }

    function test_predict_address_before_deployment() external {
        // Prepare initial owners
        bytes32[] memory keyHashes = new bytes32[](2);
        keyHashes[0] = keccak256(abi.encodePacked(_alice));
        keyHashes[1] = keccak256(abi.encodePacked(_bob));

        address[] memory validators = new address[](2);
        validators[0] = address(_ecdsaValidator);
        validators[1] = address(_ecdsaValidator);

        InitialOwner[] memory initialOwners = _createOwners(
            keyHashes,
            validators
        );

        uint256 salt = 12345;

        // Step 1: Predict the address before deployment
        address predictedAddress = _factory.getAddress(initialOwners, salt);

        // Verify the predicted address is not yet deployed
        assertEq(
            predictedAddress.code.length,
            0,
            "Address should not be deployed yet"
        );

        // Step 2: Deploy the account
        vm.prank(_alice);
        address deployedAddress = _deployAccountWithOwners(
            keyHashes,
            validators,
            salt
        );

        // Step 3: Verify the deployed address matches the prediction
        assertEq(
            deployedAddress,
            predictedAddress,
            "Deployed address should match prediction"
        );

        // Step 4: Verify the account is now deployed
        assertGt(
            deployedAddress.code.length,
            0,
            "Address should now have code"
        );

        // Step 5: Verify the account is properly initialized
        assertTrue(
            IOwnersManager(deployedAddress).hasOwner(
                keccak256(abi.encodePacked(_alice))
            )
        );
        assertTrue(
            IOwnersManager(deployedAddress).hasOwner(
                keccak256(abi.encodePacked(_bob))
            )
        );
    }

    function test_predict_address_with_different_salts() external {
        // Use same initial owners but different salts
        InitialOwner[] memory initialOwners = _createSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator)
        );

        // Predict addresses with different salts
        address predicted1 = _factory.getAddress(initialOwners, 0);

        address predicted2 = _factory.getAddress(initialOwners, 1);

        address predicted3 = _factory.getAddress(initialOwners, 999);

        // All predictions should be different
        assertTrue(
            predicted1 != predicted2,
            "Different salts should produce different addresses"
        );
        assertTrue(
            predicted2 != predicted3,
            "Different salts should produce different addresses"
        );
        assertTrue(
            predicted1 != predicted3,
            "Different salts should produce different addresses"
        );

        // Deploy and verify each one
        vm.startPrank(_aliceWallet);

        address deployed1 = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            0
        );
        assertEq(
            deployed1,
            predicted1,
            "First deployment should match prediction"
        );

        address deployed2 = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            1
        );
        assertEq(
            deployed2,
            predicted2,
            "Second deployment should match prediction"
        );

        address deployed3 = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            999
        );
        assertEq(
            deployed3,
            predicted3,
            "Third deployment should match prediction"
        );

        vm.stopPrank();
    }

    function test_predict_address_deterministic_calculation() external view {
        // This test demonstrates the deterministic nature of address calculation
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(address(0x1234))),
            validator: address(0x5678)
        });

        uint256 salt = 42;

        // Predict the address multiple times - should always be the same
        address prediction1 = _factory.getAddress(initialOwners, salt);
        address prediction2 = _factory.getAddress(initialOwners, salt);
        address prediction3 = _factory.getAddress(initialOwners, salt);

        assertEq(
            prediction1,
            prediction2,
            "Same inputs should always produce same address"
        );
        assertEq(
            prediction2,
            prediction3,
            "Same inputs should always produce same address"
        );

        // The address is deterministic based on:
        // 1. Factory address (deployer)
        // 2. Implementation address
        // 3. Initial owners configuration
        // 4. Salt value

        // Change any parameter and the address changes
        InitialOwner[] memory differentOwners = new InitialOwner[](1);
        differentOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(address(0x9999))), // Different owner
            validator: address(0x5678)
        });

        address differentPrediction = _factory.getAddress(
            differentOwners,
            salt
        );
        assertTrue(
            prediction1 != differentPrediction,
            "Different owners should produce different address"
        );
    }

    function test_already_deployed_account_returns_same_address() external {
        uint256 salt = 100;

        // First deployment
        vm.prank(_alice);
        address firstDeployment = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            salt
        );

        // Try to deploy again with same parameters
        vm.prank(_bob); // Different caller
        address secondDeployment = _deployAccountSingleOwner(
            keccak256(abi.encodePacked(_alice)),
            address(_ecdsaValidator),
            salt
        );

        // Should return the same address (already deployed)
        assertEq(
            firstDeployment,
            secondDeployment,
            "Should return existing account"
        );

        // Verify the account still has the original configuration
        assertTrue(
            IOwnersManager(firstDeployment).hasOwner(
                keccak256(abi.encodePacked(_alice))
            )
        );
    }

    function test_createAccountWithCall() external {
        uint256 salt = 0;
        InitialOwner[] memory initialOwners = new InitialOwner[](1);
        initialOwners[0] = InitialOwner({
            keyHash: keccak256(abi.encodePacked(_alice)),
            validator: address(_ecdsaValidator)
        });

        address prediction = _factory.getAddress(initialOwners, salt);

        vm.deal(prediction, 2 ether);

        Call[] memory calls = constructCallsData();
        BatchedCall memory batchedCall = BatchedCall({calls: calls, nonce: 0});
        bytes memory validatorData = _constructRelayerSignature(
            prediction,
            _alice,
            _alicePk,
            batchedCall,
            uint48(0)
        );

        vm.prank(_alice);
        address wallet = _factory.createAccountWithCall(
            initialOwners,
            salt,
            batchedCall,
            validatorData
        );

        assertEq(wallet, prediction);
        assertEq(address(_bob).balance, 1 ether);
    }
}
