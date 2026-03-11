// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    PolicyRouter,
    Router_NotEntitled,
    Router_Unauthorized,
    Router_PackNotActive,
    Router_DuplicatePolicy
} from "../../src/PolicyRouter.sol";
import {PolicyPackRegistry} from "../../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../../src/SimpleEntitlementManager.sol";
import {
    Decision,
    IFirewallPolicy,
    IFirewallPostExecPolicy
} from "../../src/interfaces/IFirewallPolicy.sol";
import {MockPolicy} from "../mocks/MockPolicies.sol";

contract MockPostExecPolicy is IFirewallPolicy, IFirewallPostExecPolicy {
    Decision public nextDecision;
    uint48 public nextDelay;
    uint256 public executedCount;

    constructor(Decision d, uint48 delaySeconds) {
        nextDecision = d;
        nextDelay = delaySeconds;
    }

    function evaluate(address, address, uint256, bytes calldata)
        external
        view
        returns (Decision decision, uint48 delaySeconds)
    {
        return (nextDecision, nextDelay);
    }

    function onExecuted(address, address, uint256, bytes calldata) external {
        executedCount++;
    }
}

contract PolicyRouterTest is Test {
    uint8 internal constant PACK_TYPE_BASE = 0;
    uint8 internal constant PACK_TYPE_ADDON = 1;

    uint256 internal constant BASE_PACK = 0;
    uint256 internal constant ADDON_PACK = 100;

    address internal OWNER = address(0xA11CE);
    address internal FIREWALL = address(0xF1EE);

    function _deployRouter(MockPolicy[] memory basePolicies, MockPolicy[] memory addonPolicies)
        internal
        returns (PolicyRouter router, PolicyPackRegistry registry, SimpleEntitlementManager entitlement)
    {
        registry = new PolicyPackRegistry(address(this));

        address[] memory base = new address[](basePolicies.length);
        for (uint256 i = 0; i < basePolicies.length; i++) {
            base[i] = address(basePolicies[i]);
        }
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, keccak256("base"), true, base);

        address[] memory addon = new address[](addonPolicies.length);
        for (uint256 i = 0; i < addonPolicies.length; i++) {
            addon[i] = address(addonPolicies[i]);
        }
        registry.registerPack(ADDON_PACK, PACK_TYPE_ADDON, keccak256("addon"), true, addon);

        entitlement = new SimpleEntitlementManager(address(this));
        router = new PolicyRouter(OWNER, FIREWALL, address(registry), address(entitlement), BASE_PACK);
    }

    function test_PolicyCount_ReturnsBaseCount() public {
        MockPolicy p1 = new MockPolicy(Decision.Allow, 0);
        MockPolicy p2 = new MockPolicy(Decision.Delay, 10);
        MockPolicy p3 = new MockPolicy(Decision.Revert, 0);

        MockPolicy[] memory base = new MockPolicy[](3);
        base[0] = p1;
        base[1] = p2;
        base[2] = p3;

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Allow, 0);

        (PolicyRouter r,,) = _deployRouter(base, addon);
        assertEq(r.policyCount(), 3);
    }

    function test_Constructor_RevertsOnDuplicatePolicyInsideBasePack() public {
        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));

        MockPolicy p = new MockPolicy(Decision.Allow, 0);
        address[] memory base = new address[](2);
        base[0] = address(p);
        base[1] = address(p);
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, keccak256("base"), true, base);

        MockPolicy addonP = new MockPolicy(Decision.Allow, 0);
        address[] memory addon = new address[](1);
        addon[0] = address(addonP);
        registry.registerPack(ADDON_PACK, PACK_TYPE_ADDON, keccak256("addon"), true, addon);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));

        vm.expectRevert(abi.encodeWithSelector(Router_DuplicatePolicy.selector, address(p)));
        new PolicyRouter(OWNER, FIREWALL, address(registry), address(entitlement), BASE_PACK);
    }

    function test_Evaluate_PrioritizesRevertAcrossBaseAndAddon() public {
        MockPolicy[] memory base = new MockPolicy[](2);
        base[0] = new MockPolicy(Decision.Allow, 0);
        base[1] = new MockPolicy(Decision.Delay, 30);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Revert, 0);

        (PolicyRouter r,, SimpleEntitlementManager ent) = _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        r.enableAddonPack(ADDON_PACK);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");
        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(uint256(delay), 0);
    }

    function test_Evaluate_ReturnsMaxDelayAcrossBaseAndAddon() public {
        MockPolicy[] memory base = new MockPolicy[](2);
        base[0] = new MockPolicy(Decision.Delay, 60);
        base[1] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](2);
        addon[0] = new MockPolicy(Decision.Delay, 300);
        addon[1] = new MockPolicy(Decision.Allow, 0);

        (PolicyRouter r,, SimpleEntitlementManager ent) = _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        r.enableAddonPack(ADDON_PACK);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(uint256(delay), 300);
    }

    function test_EnableAddonPack_RequiresEntitlement() public {
        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Delay, 300);

        (PolicyRouter r,,) = _deployRouter(base, addon);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_NotEntitled.selector, ADDON_PACK));
        r.enableAddonPack(ADDON_PACK);
    }

    function test_EnableAddonPack_OnlyOwner() public {
        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Delay, 300);

        (PolicyRouter r,, SimpleEntitlementManager ent) = _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(address(0xBAD));
        vm.expectRevert(Router_Unauthorized.selector);
        r.enableAddonPack(ADDON_PACK);
    }

    function test_Evaluate_EnabledAddonRemainsActiveAfterRegistryDeactivation() public {
        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Revert, 0);

        (PolicyRouter r, PolicyPackRegistry registry, SimpleEntitlementManager ent) =
            _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        r.enableAddonPack(ADDON_PACK);

        registry.setPackActive(ADDON_PACK, false);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");
        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(uint256(delay), 0);
    }

    function test_Evaluate_EnabledAddonRemainsActiveAfterEntitlementRevoked() public {
        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Delay, 444);

        (PolicyRouter r,, SimpleEntitlementManager ent) = _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        r.enableAddonPack(ADDON_PACK);
        ent.setEntitlement(OWNER, ADDON_PACK, false);

        (Decision d, uint48 delay) = r.evaluate(address(0xCAFE), address(this), 0, "");
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(uint256(delay), 444);
    }

    function test_EnableAddonPack_RevertsWhenPackInactive() public {
        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Delay, 1);

        (PolicyRouter r, PolicyPackRegistry registry, SimpleEntitlementManager ent) =
            _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);
        registry.setPackActive(ADDON_PACK, false);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_PackNotActive.selector, ADDON_PACK));
        r.enableAddonPack(ADDON_PACK);
    }

    function test_EnableAddonPack_RevertsOnDuplicatePolicyAgainstBase() public {
        MockPolicy p = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = p;

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = p;

        (PolicyRouter r,, SimpleEntitlementManager ent) = _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_DuplicatePolicy.selector, address(p)));
        r.enableAddonPack(ADDON_PACK);
    }

    function test_EnableAddonPack_RevertsOnDuplicatePolicyInsideAddonPack() public {
        MockPolicy baseP = new MockPolicy(Decision.Allow, 0);
        MockPolicy dup = new MockPolicy(Decision.Delay, 10);

        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = baseP;

        MockPolicy[] memory addon = new MockPolicy[](2);
        addon[0] = dup;
        addon[1] = dup;

        (PolicyRouter r,, SimpleEntitlementManager ent) = _deployRouter(base, addon);
        ent.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_DuplicatePolicy.selector, address(dup)));
        r.enableAddonPack(ADDON_PACK);
    }

    function test_NotifyExecuted_EnabledAddonRemainsAfterRegistryDeactivation() public {
        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));

        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);
        address[] memory base = new address[](1);
        base[0] = address(basePolicy);
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, keccak256("base"), true, base);

        MockPostExecPolicy addonPolicy = new MockPostExecPolicy(Decision.Allow, 0);
        address[] memory addon = new address[](1);
        addon[0] = address(addonPolicy);
        registry.registerPack(ADDON_PACK, PACK_TYPE_ADDON, keccak256("addon"), true, addon);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter r = new PolicyRouter(OWNER, FIREWALL, address(registry), address(entitlement), BASE_PACK);

        entitlement.setEntitlement(OWNER, ADDON_PACK, true);
        vm.prank(OWNER);
        r.enableAddonPack(ADDON_PACK);

        registry.setPackActive(ADDON_PACK, false);

        vm.prank(FIREWALL);
        r.notifyExecuted(address(0xCAFE), address(0xBEEF), 1, hex"1234");

        assertEq(addonPolicy.executedCount(), 1);
    }
}
