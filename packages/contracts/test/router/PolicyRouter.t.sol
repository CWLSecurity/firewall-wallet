// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    PolicyRouter,
    Router_NotEntitled,
    Router_InvalidPackAccessMode,
    Router_Unauthorized,
    Router_PackNotActive,
    Router_InvalidPolicy,
    Router_DuplicatePolicy,
    Router_PolicyMissingMetadata,
    Router_InvalidPolicyMetadata
} from "../../src/PolicyRouter.sol";
import {PolicyPackRegistry} from "../../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../../src/SimpleEntitlementManager.sol";
import {
    Decision,
    IFirewallPolicy,
    IFirewallPostExecPolicy
} from "../../src/interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../../src/interfaces/IPolicyIntrospection.sol";
import {MockPolicy} from "../mocks/MockPolicies.sol";

error RevertingEvaluatePolicy_Boom();

contract MockPostExecPolicy is IFirewallPolicy, IFirewallPostExecPolicy, IPolicyIntrospection {
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

    function policyKey() external pure returns (bytes32) {
        return keccak256("mock-postexec-policy-v1");
    }

    function policyName() external pure returns (string memory) {
        return "MockPostExecPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Test post-exec policy.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](2);
        entries[0] = PolicyConfigEntry({
            key: bytes32("mock_decision"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(uint8(nextDecision))),
            unit: bytes32("enum")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("mock_delay_seconds"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(nextDelay)),
            unit: bytes32("seconds")
        });
    }
}

contract NonIntrospectPolicy is IFirewallPolicy {
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

contract RevertingEvaluatePolicy is IFirewallPolicy, IPolicyIntrospection {
    function evaluate(address, address, uint256, bytes calldata)
        external
        pure
        returns (Decision, uint48)
    {
        revert RevertingEvaluatePolicy_Boom();
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("reverting-evaluate-policy-v1");
    }

    function policyName() external pure returns (string memory) {
        return "RevertingEvaluatePolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Always reverts in evaluate for router revert-semantics tests.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external pure returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](1);
        entries[0] = PolicyConfigEntry({
            key: bytes32("mode"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("always_revert"),
            unit: bytes32("mode")
        });
    }
}

contract MockUnsafePolicyPackRegistry {
    mapping(uint256 => bool) internal _active;
    mapping(uint256 => uint8) internal _packType;
    mapping(uint256 => uint8) internal _packAccessMode;
    mapping(uint256 => address[]) internal _policies;

    function setPack(
        uint256 packId,
        uint8 packType,
        uint8 packAccessMode,
        bool active,
        address[] memory policies
    ) external {
        _active[packId] = active;
        _packType[packId] = packType;
        _packAccessMode[packId] = packAccessMode;
        _policies[packId] = policies;
    }

    function isPackActive(uint256 packId) external view returns (bool) {
        return _active[packId];
    }

    function packTypeOf(uint256 packId) external view returns (uint8) {
        return _packType[packId];
    }

    function packAccessModeOf(uint256 packId) external view returns (uint8) {
        return _packAccessMode[packId];
    }

    function getPackPolicies(uint256 packId) external view returns (address[] memory) {
        return _policies[packId];
    }
}

contract PolicyRouterTest is Test {
    uint8 internal constant PACK_TYPE_BASE = 0;
    uint8 internal constant PACK_TYPE_ADDON = 1;
    uint8 internal constant PACK_ACCESS_FREE = 0;
    uint8 internal constant PACK_ACCESS_ENTITLED = 1;

    uint256 internal constant BASE_PACK = 0;
    uint256 internal constant ADDON_PACK = 100;

    address internal OWNER = address(0xA11CE);
    address internal FIREWALL = address(0xF1EE);

    function _deployRouter(MockPolicy[] memory basePolicies, MockPolicy[] memory addonPolicies)
        internal
        returns (PolicyRouter router, PolicyPackRegistry registry, SimpleEntitlementManager entitlement)
    {
        return _deployRouterWithAccessMode(basePolicies, addonPolicies, PACK_ACCESS_ENTITLED);
    }

    function _deployRouterWithAccessMode(
        MockPolicy[] memory basePolicies,
        MockPolicy[] memory addonPolicies,
        uint8 addonAccessMode
    ) internal returns (PolicyRouter router, PolicyPackRegistry registry, SimpleEntitlementManager entitlement)
    {
        registry = new PolicyPackRegistry(address(this));

        address[] memory base = new address[](basePolicies.length);
        for (uint256 i = 0; i < basePolicies.length; i++) {
            base[i] = address(basePolicies[i]);
        }
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, keccak256("base"), true, base);

        address[] memory addon = new address[](addonPolicies.length);
        for (uint256 i = 0; i < addonPolicies.length; i++) {
            addon[i] = address(addonPolicies[i]);
        }
        registry.registerPack(ADDON_PACK, PACK_TYPE_ADDON, addonAccessMode, keccak256("addon"), true, addon);

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
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, keccak256("base"), true, base);

        MockPolicy addonP = new MockPolicy(Decision.Allow, 0);
        address[] memory addon = new address[](1);
        addon[0] = address(addonP);
        registry.registerPack(
            ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, keccak256("addon"), true, addon
        );

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

    function test_Evaluate_RevertsWhenBasePolicyEvaluateReverts() public {
        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));

        RevertingEvaluatePolicy baseReverting = new RevertingEvaluatePolicy();
        address[] memory base = new address[](1);
        base[0] = address(baseReverting);
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, keccak256("base"), true, base);

        MockPolicy addonAllow = new MockPolicy(Decision.Allow, 0);
        address[] memory addon = new address[](1);
        addon[0] = address(addonAllow);
        registry.registerPack(
            ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, keccak256("addon"), true, addon
        );

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter router = new PolicyRouter(OWNER, FIREWALL, address(registry), address(entitlement), BASE_PACK);

        vm.expectRevert(RevertingEvaluatePolicy_Boom.selector);
        router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
    }

    function test_Evaluate_RevertsWhenEnabledAddonPolicyEvaluateReverts() public {
        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));

        MockPolicy baseAllow = new MockPolicy(Decision.Allow, 0);
        address[] memory base = new address[](1);
        base[0] = address(baseAllow);
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, keccak256("base"), true, base);

        RevertingEvaluatePolicy addonReverting = new RevertingEvaluatePolicy();
        address[] memory addon = new address[](1);
        addon[0] = address(addonReverting);
        registry.registerPack(
            ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, keccak256("addon"), true, addon
        );

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter router = new PolicyRouter(OWNER, FIREWALL, address(registry), address(entitlement), BASE_PACK);

        (Decision beforeDecision, uint48 beforeDelay) = router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
        assertEq(uint256(beforeDecision), uint256(Decision.Allow));
        assertEq(beforeDelay, 0);

        entitlement.setEntitlement(OWNER, ADDON_PACK, true);
        vm.prank(OWNER);
        router.enableAddonPack(ADDON_PACK);

        vm.expectRevert(RevertingEvaluatePolicy_Boom.selector);
        router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
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

    function test_EnableAddonPack_FreeMode_DoesNotRequireEntitlement() public {
        MockPolicy[] memory base = new MockPolicy[](1);
        base[0] = new MockPolicy(Decision.Allow, 0);

        MockPolicy[] memory addon = new MockPolicy[](1);
        addon[0] = new MockPolicy(Decision.Delay, 300);

        (PolicyRouter r,,) = _deployRouterWithAccessMode(base, addon, PACK_ACCESS_FREE);

        vm.prank(OWNER);
        r.enableAddonPack(ADDON_PACK);

        assertTrue(r.isAddonPackEnabled(ADDON_PACK));
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
        registry.registerPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, keccak256("base"), true, base);

        MockPostExecPolicy addonPolicy = new MockPostExecPolicy(Decision.Allow, 0);
        address[] memory addon = new address[](1);
        addon[0] = address(addonPolicy);
        registry.registerPack(
            ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, keccak256("addon"), true, addon
        );

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

    function test_Constructor_RevertsWhenBasePolicyAddressIsNotContract() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(0xBEEF);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        vm.expectRevert(abi.encodeWithSelector(Router_InvalidPolicy.selector, address(0xBEEF)));
        new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);
    }

    function test_EnableAddonPack_RevertsWhenAddonPolicyAddressIsNotContract() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);

        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(basePolicy);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(0xCAFE);
        unsafeRegistry.setPack(ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, true, addonPolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter router = new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);
        entitlement.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_InvalidPolicy.selector, address(0xCAFE)));
        router.enableAddonPack(ADDON_PACK);
    }

    function test_EnableAddonPack_RevertsOnInvalidAccessMode() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);
        MockPolicy addonPolicy = new MockPolicy(Decision.Delay, 1);

        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(basePolicy);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(addonPolicy);
        unsafeRegistry.setPack(ADDON_PACK, PACK_TYPE_ADDON, 77, true, addonPolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter router = new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_InvalidPackAccessMode.selector, ADDON_PACK, uint8(77)));
        router.enableAddonPack(ADDON_PACK);
    }

    function test_Constructor_RevertsWhenBasePolicyMissingMetadata() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        NonIntrospectPolicy basePolicy = new NonIntrospectPolicy();

        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(basePolicy);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        vm.expectRevert(abi.encodeWithSelector(Router_PolicyMissingMetadata.selector, address(basePolicy)));
        new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);
    }

    function test_EnableAddonPack_RevertsWhenAddonPolicyMissingMetadata() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);
        NonIntrospectPolicy addonPolicy = new NonIntrospectPolicy();

        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(basePolicy);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(addonPolicy);
        unsafeRegistry.setPack(ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, true, addonPolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter router = new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);
        entitlement.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_PolicyMissingMetadata.selector, address(addonPolicy)));
        router.enableAddonPack(ADDON_PACK);
    }

    function test_Constructor_RevertsWhenBasePolicyMetadataInvalid() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        InvalidMetadataPolicy basePolicy = new InvalidMetadataPolicy();

        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(basePolicy);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        vm.expectRevert(abi.encodeWithSelector(Router_InvalidPolicyMetadata.selector, address(basePolicy)));
        new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);
    }

    function test_EnableAddonPack_RevertsWhenAddonPolicyMetadataInvalid() public {
        MockUnsafePolicyPackRegistry unsafeRegistry = new MockUnsafePolicyPackRegistry();
        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);
        InvalidMetadataPolicy addonPolicy = new InvalidMetadataPolicy();

        address[] memory basePolicies = new address[](1);
        basePolicies[0] = address(basePolicy);
        unsafeRegistry.setPack(BASE_PACK, PACK_TYPE_BASE, PACK_ACCESS_FREE, true, basePolicies);

        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(addonPolicy);
        unsafeRegistry.setPack(ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, true, addonPolicies);

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouter router = new PolicyRouter(OWNER, FIREWALL, address(unsafeRegistry), address(entitlement), BASE_PACK);
        entitlement.setEntitlement(OWNER, ADDON_PACK, true);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Router_InvalidPolicyMetadata.selector, address(addonPolicy)));
        router.enableAddonPack(ADDON_PACK);
    }
}
