// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    PolicyPackRegistry,
    Registry_Unauthorized,
    Registry_PackExists,
    Registry_UnknownPack,
    Registry_ZeroPolicies,
    Registry_InvalidPackType
} from "../../src/PolicyPackRegistry.sol";
import {MockPolicy} from "../mocks/MockPolicies.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";

contract PolicyPackRegistryTest is Test {
    uint8 internal constant PACK_TYPE_BASE = 0;
    uint8 internal constant PACK_TYPE_ADDON = 1;

    PolicyPackRegistry internal registry;
    MockPolicy internal p1;
    MockPolicy internal p2;

    function setUp() public {
        registry = new PolicyPackRegistry(address(this));
        p1 = new MockPolicy(Decision.Allow, 0);
        p2 = new MockPolicy(Decision.Delay, 10);
    }

    function test_RegisterPack_StoresMetadataAndPolicies() public {
        address[] memory policies = new address[](2);
        policies[0] = address(p1);
        policies[1] = address(p2);

        registry.registerPack(0, PACK_TYPE_BASE, keccak256("base"), true, policies);

        assertTrue(registry.isPackActive(0));
        assertEq(registry.packTypeOf(0), PACK_TYPE_BASE);
        assertEq(registry.policyCountOf(0), 2);

        address[] memory stored = registry.getPackPolicies(0);
        assertEq(stored.length, 2);
        assertEq(stored[0], address(p1));
        assertEq(stored[1], address(p2));
    }

    function test_RegisterPack_RevertsOnDuplicatePackId() public {
        address[] memory policies = new address[](1);
        policies[0] = address(p1);

        registry.registerPack(1, PACK_TYPE_BASE, keccak256("base"), true, policies);
        vm.expectRevert(abi.encodeWithSelector(Registry_PackExists.selector, 1));
        registry.registerPack(1, PACK_TYPE_BASE, keccak256("base"), true, policies);
    }

    function test_RegisterPack_RevertsOnZeroPolicies() public {
        address[] memory policies = new address[](0);
        vm.expectRevert(Registry_ZeroPolicies.selector);
        registry.registerPack(1, PACK_TYPE_BASE, keccak256("base"), true, policies);
    }

    function test_RegisterPack_RevertsOnInvalidPackType() public {
        address[] memory policies = new address[](1);
        policies[0] = address(p1);

        vm.expectRevert(abi.encodeWithSelector(Registry_InvalidPackType.selector, 77));
        registry.registerPack(1, 77, keccak256("bad"), true, policies);
    }

    function test_SetPackActive_UpdatesStatus() public {
        address[] memory policies = new address[](1);
        policies[0] = address(p1);
        registry.registerPack(2, PACK_TYPE_ADDON, keccak256("addon"), true, policies);

        registry.setPackActive(2, false);
        assertFalse(registry.isPackActive(2));
    }

    function test_OnlyOwner_CanMutateRegistry() public {
        address[] memory policies = new address[](1);
        policies[0] = address(p1);

        vm.prank(address(0xBAD));
        vm.expectRevert(Registry_Unauthorized.selector);
        registry.registerPack(1, PACK_TYPE_BASE, keccak256("base"), true, policies);
    }

    function test_UnknownPackLookupsRevert() public {
        vm.expectRevert(abi.encodeWithSelector(Registry_UnknownPack.selector, 999));
        registry.packTypeOf(999);

        vm.expectRevert(abi.encodeWithSelector(Registry_UnknownPack.selector, 999));
        registry.getPackPolicies(999);
    }
}
