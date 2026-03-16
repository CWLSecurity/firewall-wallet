// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {UnknownContractBlockPolicy} from "../../src/policies/UnknownContractBlockPolicy.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry
} from "../../src/interfaces/IPolicyIntrospection.sol";

contract DummyTarget {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract UnknownContractBlockPolicyTest is Test {
    UnknownContractBlockPolicy policy;

    address policyOwner = address(0xABCD);

    function setUp() public {
        vm.prank(policyOwner);
        policy = new UnknownContractBlockPolicy(policyOwner);
    }

    function test_Allows_EOA() public view {
        address eoa = address(0xBEEF); // code.length == 0
        (Decision d, uint48 ds) = policy.evaluate(address(this), eoa, 0, hex"");
        assertEq(uint256(d), uint256(Decision.Allow));
        assertEq(ds, 0);
    }

    function test_Reverts_UnknownContract() public {
        DummyTarget t = new DummyTarget();
        (Decision d, uint48 ds) = policy.evaluate(address(this), address(t), 0, hex"");
        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(ds, 0);
    }

    function test_Allows_AllowedContract() public {
        DummyTarget t = new DummyTarget();

        vm.prank(policyOwner);
        policy.setAllowed(address(t), true);

        (Decision d, uint48 ds) = policy.evaluate(address(this), address(t), 0, hex"");
        assertEq(uint256(d), uint256(Decision.Allow));
        assertEq(ds, 0);
    }

    function test_SetAllowed_OnlyOwner() public {
        DummyTarget t = new DummyTarget();

        vm.expectRevert();
        policy.setAllowed(address(t), true);

        vm.prank(policyOwner);
        policy.setAllowed(address(t), true);
    }

    function test_Metadata_StatesAllowlistRequiresEventIndexing() public view {
        PolicyConfigEntry[] memory cfg = IPolicyIntrospection(address(policy)).policyConfig();
        assertEq(cfg.length, 4);
        assertEq(cfg[3].key, bytes32("allowlist_reconstruct"));
        assertEq(cfg[3].value, bytes32("events_required"));
        assertEq(cfg[3].unit, bytes32("mode"));
    }
}
