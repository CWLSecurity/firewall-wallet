// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    PolicyPackRegistry,
    Registry_Unauthorized,
    Registry_PackExists,
    Registry_UnknownPack,
    Registry_ZeroPolicies,
    Registry_InvalidPolicy,
    Registry_InvalidPackType,
    Registry_PolicyMissingMetadata,
    Registry_InvalidPolicyMetadata
} from "../../src/PolicyPackRegistry.sol";
import {MockPolicy} from "../mocks/MockPolicies.sol";
import {Decision, IFirewallPolicy} from "../../src/interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry
} from "../../src/interfaces/IPolicyIntrospection.sol";

contract NonIntrospectionPolicy is IFirewallPolicy {
    function evaluate(address, address, uint256, bytes calldata)
        external
        pure
        returns (Decision decision, uint48 delaySeconds)
    {
        return (Decision.Allow, 0);
    }
}

contract InvalidMetadataPolicy is IFirewallPolicy, IPolicyIntrospection {
    function evaluate(address, address, uint256, bytes calldata)
        external
        pure
        returns (Decision decision, uint48 delaySeconds)
    {
        return (Decision.Allow, 0);
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("invalid-metadata-policy-v1");
    }

    function policyName() external pure returns (string memory) {
        return "InvalidMetadataPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external pure returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](0);
    }
}

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

    function test_RegisterPack_RevertsOnNonContractPolicyAddress() public {
        address[] memory policies = new address[](1);
        policies[0] = address(0xBEEF);

        vm.expectRevert(abi.encodeWithSelector(Registry_InvalidPolicy.selector, address(0xBEEF)));
        registry.registerPack(1, PACK_TYPE_BASE, keccak256("base"), true, policies);
    }

    function test_RegisterPack_RevertsWhenPolicyMissingMetadata() public {
        NonIntrospectionPolicy p = new NonIntrospectionPolicy();
        address[] memory policies = new address[](1);
        policies[0] = address(p);

        vm.expectRevert(abi.encodeWithSelector(Registry_PolicyMissingMetadata.selector, address(p)));
        registry.registerPack(1, PACK_TYPE_BASE, keccak256("base"), true, policies);
    }

    function test_RegisterPack_RevertsWhenPolicyMetadataInvalid() public {
        InvalidMetadataPolicy p = new InvalidMetadataPolicy();
        address[] memory policies = new address[](1);
        policies[0] = address(p);

        vm.expectRevert(abi.encodeWithSelector(Registry_InvalidPolicyMetadata.selector, address(p)));
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

    function test_PackEnumerationAndDetailedMetadata() public {
        address[] memory pBase = new address[](1);
        pBase[0] = address(p1);
        registry.registerPackDetailed(10, PACK_TYPE_BASE, keccak256("base-alpha"), "base-alpha", 1, true, pBase);

        address[] memory pAddon = new address[](1);
        pAddon[0] = address(p2);
        registry.registerPackDetailed(11, PACK_TYPE_ADDON, keccak256("addon-beta"), "addon-beta", 2, false, pAddon);

        assertEq(registry.packCount(), 2);
        assertEq(registry.packIdAt(0), 10);
        assertEq(registry.packIdAt(1), 11);
        uint256[] memory ids = registry.packIds();
        assertEq(ids.length, 2);
        assertEq(ids[0], 10);
        assertEq(ids[1], 11);

        (bool active0, uint8 packType0, bytes32 metadata0, string memory slug0, uint16 version0, uint256 count0) =
            registry.getPackMeta(10);
        assertEq(active0, true);
        assertEq(packType0, PACK_TYPE_BASE);
        assertEq(metadata0, keccak256("base-alpha"));
        assertEq(slug0, "base-alpha");
        assertEq(version0, 1);
        assertEq(count0, 1);

        (bool active1, uint8 packType1, bytes32 metadata1, string memory slug1, uint16 version1, uint256 count1) =
            registry.getPackMeta(11);
        assertEq(active1, false);
        assertEq(packType1, PACK_TYPE_ADDON);
        assertEq(metadata1, keccak256("addon-beta"));
        assertEq(slug1, "addon-beta");
        assertEq(version1, 2);
        assertEq(count1, 1);
    }
}
