// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    ProtocolRegistry,
    ProtocolRegistry_Unauthorized,
    ProtocolRegistry_ProtocolExists,
    ProtocolRegistry_UnknownProtocol,
    ProtocolRegistry_TargetAlreadyMapped,
    ProtocolRegistry_TargetUnmapped
} from "../../src/ProtocolRegistry.sol";

contract ProtocolRegistryTest is Test {
    ProtocolRegistry internal registry;

    function setUp() public {
        registry = new ProtocolRegistry(address(this));
    }

    function test_RegisterAndEnumerateProtocols() public {
        bytes32 p0 = keccak256("uniswap-v4");
        bytes32 p1 = keccak256("aave-v3");
        registry.registerProtocol(p0, true, "uniswap-v4", 1, keccak256("dex"));
        registry.registerProtocol(p1, false, "aave-v3", 2, keccak256("lending"));

        assertEq(registry.protocolCount(), 2);
        assertEq(registry.protocolIdAt(0), p0);
        assertEq(registry.protocolIdAt(1), p1);

        (bool active0, string memory slug0, uint16 version0, bytes32 metadata0, uint256 targetCount0) =
            registry.getProtocolMeta(p0);
        assertTrue(active0);
        assertEq(slug0, "uniswap-v4");
        assertEq(version0, 1);
        assertEq(metadata0, keccak256("dex"));
        assertEq(targetCount0, 0);
    }

    function test_TargetMappingResolveAndRemoval() public {
        bytes32 protocolId = keccak256("curve");
        address target0 = address(0xCAFE);
        address target1 = address(0xBEEF);
        registry.registerProtocol(protocolId, true, "curve", 1, keccak256("amm"));

        registry.setProtocolTarget(protocolId, target0, true);
        registry.setProtocolTarget(protocolId, target1, true);
        assertEq(registry.protocolTargetCount(protocolId), 2);

        (bytes32 resolved0, bool active0) = registry.resolveProtocol(target0);
        assertEq(resolved0, protocolId);
        assertTrue(active0);

        registry.setProtocolTarget(protocolId, target0, false);
        assertEq(registry.protocolTargetCount(protocolId), 1);
        (bytes32 resolvedRemoved, bool activeRemoved) = registry.resolveProtocol(target0);
        assertEq(resolvedRemoved, bytes32(0));
        assertFalse(activeRemoved);
    }

    function test_RevertsOnDuplicateProtocolId() public {
        bytes32 protocolId = keccak256("cow");
        registry.registerProtocol(protocolId, true, "cow", 1, keccak256("dex"));

        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry_ProtocolExists.selector, protocolId));
        registry.registerProtocol(protocolId, true, "cow-v2", 2, keccak256("dex2"));
    }

    function test_RevertsWhenTargetAlreadyMappedToDifferentProtocol() public {
        bytes32 p0 = keccak256("uniswap-v4");
        bytes32 p1 = keccak256("aave-v3");
        address target = address(0xCAFE);
        registry.registerProtocol(p0, true, "uniswap-v4", 1, keccak256("dex"));
        registry.registerProtocol(p1, true, "aave-v3", 1, keccak256("lending"));
        registry.setProtocolTarget(p0, target, true);

        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry_TargetAlreadyMapped.selector, target, p0));
        registry.setProtocolTarget(p1, target, true);
    }

    function test_RevertsOnUnknownProtocolMutation() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry_UnknownProtocol.selector, unknown));
        registry.setProtocolActive(unknown, true);
    }

    function test_RevertsOnUnmappedRemoval() public {
        bytes32 protocolId = keccak256("maker");
        registry.registerProtocol(protocolId, true, "maker", 1, keccak256("lending"));

        vm.expectRevert(abi.encodeWithSelector(ProtocolRegistry_TargetUnmapped.selector, address(0xABCD)));
        registry.setProtocolTarget(protocolId, address(0xABCD), false);
    }

    function test_OnlyOwnerMutations() public {
        bytes32 protocolId = keccak256("balancer");
        vm.prank(address(0xBAD));
        vm.expectRevert(ProtocolRegistry_Unauthorized.selector);
        registry.registerProtocol(protocolId, true, "balancer", 1, keccak256("dex"));
    }
}
