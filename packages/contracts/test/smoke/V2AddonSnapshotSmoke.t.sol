// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {
    PolicyRouter,
    Router_DuplicatePolicy,
    Router_PackNotActive
} from "../../src/PolicyRouter.sol";
import {FirewallModule} from "../../src/FirewallModule.sol";
import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {MockPolicy} from "../mocks/MockPolicies.sol";

contract V2AddonSnapshotSmoke is SmokeBase {
    uint256 internal constant BASE_PACK = 0;
    uint256 internal constant ADDON_DELAY_PACK = 100;
    uint256 internal constant ADDON_REVERT_PACK = 101;
    uint256 internal constant ADDON_DUP_PACK = 102;

    function _deployWithAllowBase() internal returns (FirewallModule wallet, PolicyRouter router, MockPolicy baseAllow) {
        baseAllow = _makeMockPolicy(Decision.Allow, 0);
        address[] memory base = new address[](1);
        base[0] = address(baseAllow);
        _deployV2WithCustomBase(base, BASE_PACK);
        (wallet, router) = _createWalletAndRouter(BASE_PACK);
    }

    function test_Smoke_EnableAddonAndSnapshotPolicies() public {
        (, PolicyRouter router,) = _deployWithAllowBase();

        MockPolicy delayAddon = _makeMockPolicy(Decision.Delay, 777);
        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(delayAddon);
        _registerAddonPack(ADDON_DELAY_PACK, addonPolicies, true);

        _grantEntitlement(ADDON_DELAY_PACK, true);
        router.enableAddonPack(ADDON_DELAY_PACK);

        assertEq(router.addonPackCount(), 1);
        assertEq(router.enabledAddonPackAt(0), ADDON_DELAY_PACK);
        assertEq(router.enabledAddonPolicyCount(ADDON_DELAY_PACK), 1);
        assertEq(router.enabledAddonPolicyAt(ADDON_DELAY_PACK, 0), address(delayAddon));

        (Decision d, uint48 delay) = router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delay, 777);
    }

    function test_Smoke_EnabledAddonRemainsAfterRegistryDeactivation() public {
        (, PolicyRouter router,) = _deployWithAllowBase();

        MockPolicy delayAddon = _makeMockPolicy(Decision.Delay, 500);
        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(delayAddon);
        _registerAddonPack(ADDON_DELAY_PACK, addonPolicies, true);

        _grantEntitlement(ADDON_DELAY_PACK, true);
        router.enableAddonPack(ADDON_DELAY_PACK);

        registry.setPackActive(ADDON_DELAY_PACK, false);

        (Decision d, uint48 delay) = router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delay, 500);

        (, PolicyRouter router2) = _createWalletAndRouter(BASE_PACK);
        _grantEntitlement(ADDON_DELAY_PACK, true);
        vm.expectRevert(abi.encodeWithSelector(Router_PackNotActive.selector, ADDON_DELAY_PACK));
        router2.enableAddonPack(ADDON_DELAY_PACK);
    }

    function test_Smoke_EnabledAddonRemainsAfterEntitlementRevocation() public {
        (, PolicyRouter router,) = _deployWithAllowBase();

        MockPolicy delayAddon = _makeMockPolicy(Decision.Delay, 321);
        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(delayAddon);
        _registerAddonPack(ADDON_DELAY_PACK, addonPolicies, true);

        _grantEntitlement(ADDON_DELAY_PACK, true);
        router.enableAddonPack(ADDON_DELAY_PACK);
        _grantEntitlement(ADDON_DELAY_PACK, false);

        (Decision d, uint48 delay) = router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delay, 321);
    }

    function test_Smoke_DuplicatePolicyRejection_InsidePack() public {
        (, PolicyRouter router,) = _deployWithAllowBase();

        MockPolicy dup = _makeMockPolicy(Decision.Delay, 9);
        address[] memory addonPolicies = new address[](2);
        addonPolicies[0] = address(dup);
        addonPolicies[1] = address(dup);
        _registerAddonPack(ADDON_DUP_PACK, addonPolicies, true);
        _grantEntitlement(ADDON_DUP_PACK, true);

        vm.expectRevert(abi.encodeWithSelector(Router_DuplicatePolicy.selector, address(dup)));
        router.enableAddonPack(ADDON_DUP_PACK);
    }

    function test_Smoke_DuplicatePolicyRejection_AgainstBase() public {
        MockPolicy baseDelay = _makeMockPolicy(Decision.Delay, 11);
        address[] memory base = new address[](1);
        base[0] = address(baseDelay);
        _deployV2WithCustomBase(base, BASE_PACK);

        (, PolicyRouter router) = _createWalletAndRouter(BASE_PACK);

        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(baseDelay);
        _registerAddonPack(ADDON_DUP_PACK, addonPolicies, true);
        _grantEntitlement(ADDON_DUP_PACK, true);

        vm.expectRevert(abi.encodeWithSelector(Router_DuplicatePolicy.selector, address(baseDelay)));
        router.enableAddonPack(ADDON_DUP_PACK);
    }

    function test_Smoke_DuplicatePolicyRejection_AgainstPreviouslyEnabledAddon() public {
        (, PolicyRouter router,) = _deployWithAllowBase();

        MockPolicy shared = _makeMockPolicy(Decision.Delay, 7);
        address[] memory addonOne = new address[](1);
        addonOne[0] = address(shared);
        _registerAddonPack(ADDON_DELAY_PACK, addonOne, true);
        _grantEntitlement(ADDON_DELAY_PACK, true);
        router.enableAddonPack(ADDON_DELAY_PACK);

        address[] memory addonTwo = new address[](1);
        addonTwo[0] = address(shared);
        _registerAddonPack(ADDON_DUP_PACK, addonTwo, true);
        _grantEntitlement(ADDON_DUP_PACK, true);

        vm.expectRevert(abi.encodeWithSelector(Router_DuplicatePolicy.selector, address(shared)));
        router.enableAddonPack(ADDON_DUP_PACK);
    }

    function test_Smoke_DecisionPriority_RevertDominatesAcrossBaseAndAddon() public {
        MockPolicy baseDelay = _makeMockPolicy(Decision.Delay, 100);
        address[] memory base = new address[](1);
        base[0] = address(baseDelay);
        _deployV2WithCustomBase(base, BASE_PACK);

        (, PolicyRouter router) = _createWalletAndRouter(BASE_PACK);

        MockPolicy addonRevert = _makeMockPolicy(Decision.Revert, 0);
        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(addonRevert);
        _registerAddonPack(ADDON_REVERT_PACK, addonPolicies, true);
        _grantEntitlement(ADDON_REVERT_PACK, true);
        router.enableAddonPack(ADDON_REVERT_PACK);

        (Decision d, uint48 delay) = router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
        assertEq(uint256(d), uint256(Decision.Revert));
        assertEq(delay, 0);
    }

    function test_Smoke_DecisionPriority_MaxDelayAcrossBaseAndAddon() public {
        MockPolicy baseDelay = _makeMockPolicy(Decision.Delay, 100);
        address[] memory base = new address[](1);
        base[0] = address(baseDelay);
        _deployV2WithCustomBase(base, BASE_PACK);

        (, PolicyRouter router) = _createWalletAndRouter(BASE_PACK);

        MockPolicy addonDelay = _makeMockPolicy(Decision.Delay, 300);
        address[] memory addonPolicies = new address[](1);
        addonPolicies[0] = address(addonDelay);
        _registerAddonPack(ADDON_DELAY_PACK, addonPolicies, true);
        _grantEntitlement(ADDON_DELAY_PACK, true);
        router.enableAddonPack(ADDON_DELAY_PACK);

        (Decision d, uint48 delay) = router.evaluate(address(0xCAFE), address(0xBEEF), 0, "");
        assertEq(uint256(d), uint256(Decision.Delay));
        assertEq(delay, 300);
    }
}
