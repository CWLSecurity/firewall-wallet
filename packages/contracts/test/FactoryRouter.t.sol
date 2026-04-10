// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {
    FirewallFactory,
    Factory_ZeroAddress,
    Factory_UnauthorizedOwner,
    Factory_InvalidBasePack,
    Factory_InactiveBasePack,
    Factory_InvalidRouterDeployer
} from "../src/FirewallFactory.sol";
import {PolicyRouterDeployer} from "../src/PolicyRouterDeployer.sol";
import {FirewallModule} from "../src/FirewallModule.sol";
import {PolicyRouter, Router_Unauthorized} from "../src/PolicyRouter.sol";
import {PolicyPackRegistry} from "../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../src/SimpleEntitlementManager.sol";
import {MockPolicy} from "./mocks/MockPolicies.sol";
import {Decision} from "../src/interfaces/IFirewallPolicy.sol";

contract FactoryRouterTest is Test {
    uint8 internal constant PACK_TYPE_BASE = 0;
    uint8 internal constant PACK_TYPE_ADDON = 1;
    uint8 internal constant PACK_ACCESS_FREE = 0;
    uint8 internal constant PACK_ACCESS_ENTITLED = 1;

    uint256 internal constant BASE_PACK_CONSERVATIVE = 0;
    uint256 internal constant BASE_PACK_DEFI = 1;
    uint256 internal constant ADDON_PACK = 100;

    address internal OWNER = address(0xA11CE);
    address internal RECOVERY = address(0xB0B);

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery,
        uint256 basePackId
    );

    function _deployFactory() internal returns (FirewallFactory factory, address basePolicy) {
        MockPolicy basePolicyConservative = new MockPolicy(Decision.Allow, 0);
        MockPolicy basePolicyDefi = new MockPolicy(Decision.Allow, 0);
        MockPolicy addonPolicy = new MockPolicy(Decision.Delay, 100);

        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));
        address[] memory conservative = new address[](1);
        conservative[0] = address(basePolicyConservative);
        registry.registerPack(
            BASE_PACK_CONSERVATIVE,
            PACK_TYPE_BASE,
            PACK_ACCESS_FREE,
            keccak256("base-conservative"),
            true,
            conservative
        );

        address[] memory defi = new address[](1);
        defi[0] = address(basePolicyDefi);
        registry.registerPack(BASE_PACK_DEFI, PACK_TYPE_BASE, PACK_ACCESS_FREE, keccak256("base-defi"), true, defi);

        address[] memory addon = new address[](1);
        addon[0] = address(addonPolicy);
        registry.registerPack(
            ADDON_PACK, PACK_TYPE_ADDON, PACK_ACCESS_ENTITLED, keccak256("addon-delay"), true, addon
        );

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouterDeployer routerDeployer = new PolicyRouterDeployer();
        factory = new FirewallFactory(address(registry), address(entitlement), address(routerDeployer));
        basePolicy = address(basePolicyConservative);
    }

    function _createWallet(FirewallFactory f, uint256 basePackId)
        internal
        returns (address wallet, address router)
    {
        vm.recordLogs();
        vm.prank(OWNER);
        wallet = f.createWallet(OWNER, RECOVERY, basePackId);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("WalletCreated(address,address,address,address,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(f) &&
                entries[i].topics.length == 4 &&
                entries[i].topics[0] == sig
            ) {
                assertEq(address(uint160(uint256(entries[i].topics[2]))), wallet);
                router = address(uint160(uint256(entries[i].topics[3])));
                break;
            }
        }
        assertTrue(router != address(0), "WalletCreated not found");
    }

    function _createWalletWithValue(FirewallFactory f, uint256 basePackId, uint256 valueWei)
        internal
        returns (address wallet, address router)
    {
        vm.recordLogs();
        vm.deal(OWNER, valueWei + 1 ether);
        vm.prank(OWNER);
        wallet = f.createWallet{value: valueWei}(OWNER, RECOVERY, basePackId);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("WalletCreated(address,address,address,address,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(f) &&
                entries[i].topics.length == 4 &&
                entries[i].topics[0] == sig
            ) {
                assertEq(address(uint160(uint256(entries[i].topics[2]))), wallet);
                router = address(uint160(uint256(entries[i].topics[3])));
                break;
            }
        }
        assertTrue(router != address(0), "WalletCreated not found");
    }

    function test_FactoryCreatesWalletAndRouter() public {
        (FirewallFactory f, address expectedBasePolicy) = _deployFactory();
        (address wallet, address routerAddr) = _createWallet(f, BASE_PACK_CONSERVATIVE);

        PolicyRouter r = PolicyRouter(routerAddr);
        assertEq(r.owner(), OWNER);
        assertEq(r.firewallModule(), wallet);
        assertEq(r.basePackId(), BASE_PACK_CONSERVATIVE);
        assertEq(address(r.policies(0)), expectedBasePolicy);
        assertEq(FirewallModule(payable(wallet)).feeConfigAdmin(), OWNER);
        assertTrue(routerAddr != address(0));
        assertTrue(wallet != address(0));
        assertTrue(routerAddr != wallet);
        assertEq(f.latestWalletOfOwner(OWNER), wallet);
    }

    function test_FactoryCreateWallet_ForwardsInitialBotGasBuffer() public {
        (FirewallFactory f,) = _deployFactory();
        uint256 initialBotGasWei = 0.0002 ether;
        (address wallet,) = _createWalletWithValue(f, BASE_PACK_CONSERVATIVE, initialBotGasWei);

        assertEq(address(wallet).balance, initialBotGasWei);
        assertEq(FirewallModule(payable(wallet)).botGasBuffer(), initialBotGasWei);
    }

    function test_FactoryRejectsAddonAsBasePack() public {
        (FirewallFactory f,) = _deployFactory();
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Factory_InvalidBasePack.selector, ADDON_PACK));
        f.createWallet(OWNER, RECOVERY, ADDON_PACK);
    }

    function test_FactoryRejectsInactiveBasePack() public {
        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);
        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));
        address[] memory conservative = new address[](1);
        conservative[0] = address(basePolicy);
        registry.registerPack(
            BASE_PACK_CONSERVATIVE,
            PACK_TYPE_BASE,
            PACK_ACCESS_FREE,
            keccak256("base-conservative"),
            false,
            conservative
        );

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouterDeployer routerDeployer = new PolicyRouterDeployer();
        FirewallFactory f =
            new FirewallFactory(address(registry), address(entitlement), address(routerDeployer));

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(Factory_InactiveBasePack.selector, BASE_PACK_CONSERVATIVE)
        );
        f.createWallet(OWNER, RECOVERY, BASE_PACK_CONSERVATIVE);
    }

    function test_FactoryRejectsZeroOwner() public {
        (FirewallFactory f,) = _deployFactory();
        vm.expectRevert(Factory_ZeroAddress.selector);
        f.createWallet(address(0), RECOVERY, BASE_PACK_CONSERVATIVE);
    }

    function test_FactoryRejectsZeroRecovery() public {
        (FirewallFactory f,) = _deployFactory();
        vm.prank(OWNER);
        vm.expectRevert(Factory_ZeroAddress.selector);
        f.createWallet(OWNER, address(0), BASE_PACK_CONSERVATIVE);
    }

    function test_FactoryRejectsNonOwnerCaller() public {
        (FirewallFactory f,) = _deployFactory();
        vm.expectRevert(abi.encodeWithSelector(Factory_UnauthorizedOwner.selector, address(this), OWNER));
        f.createWallet(OWNER, RECOVERY, BASE_PACK_CONSERVATIVE);
    }

    function test_FactoryConstructorRejectsZeroRegistry() public {
        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        PolicyRouterDeployer routerDeployer = new PolicyRouterDeployer();
        vm.expectRevert(Factory_ZeroAddress.selector);
        new FirewallFactory(address(0), address(entitlement), address(routerDeployer));
    }

    function test_FactoryConstructorRejectsZeroRouterDeployer() public {
        MockPolicy basePolicy = new MockPolicy(Decision.Allow, 0);
        PolicyPackRegistry registry = new PolicyPackRegistry(address(this));
        address[] memory conservative = new address[](1);
        conservative[0] = address(basePolicy);
        registry.registerPack(
            BASE_PACK_CONSERVATIVE,
            PACK_TYPE_BASE,
            PACK_ACCESS_FREE,
            keccak256("base-conservative"),
            true,
            conservative
        );

        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(address(this));
        vm.expectRevert(
            abi.encodeWithSelector(Factory_InvalidRouterDeployer.selector, address(0))
        );
        new FirewallFactory(address(registry), address(entitlement), address(0));
    }

    function test_FactoryCreatesFreshRouterPerWallet() public {
        (FirewallFactory f,) = _deployFactory();
        (address w1, address r1) = _createWallet(f, BASE_PACK_CONSERVATIVE);
        (address w2, address r2) = _createWallet(f, BASE_PACK_DEFI);

        assertTrue(r1 != r2);
        assertTrue(f.isFactoryVault(w1));
        assertTrue(f.isFactoryVault(w2));
        assertFalse(f.isFactoryVault(address(0xBEEF)));
        assertEq(f.latestWalletOfOwner(OWNER), w2);
    }

    function test_NotifyExecuted_onlyWallet() public {
        (FirewallFactory f,) = _deployFactory();
        (address wallet, address routerAddr) = _createWallet(f, BASE_PACK_CONSERVATIVE);
        PolicyRouter r = PolicyRouter(routerAddr);

        vm.prank(address(0xBAD));
        vm.expectRevert(Router_Unauthorized.selector);
        r.notifyExecuted(address(0xCAFE), address(0xBEEF), 0, "");

        vm.prank(wallet);
        r.notifyExecuted(address(0xCAFE), address(0xBEEF), 0, "");
    }

    function test_FactoryHasNoPostCreationControl() public {
        (FirewallFactory f,) = _deployFactory();
        (, address routerAddr) = _createWallet(f, BASE_PACK_CONSERVATIVE);

        PolicyRouter r = PolicyRouter(routerAddr);
        assertTrue(r.owner() != address(f));
    }
}
