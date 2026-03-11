// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {FirewallFactory} from "../../src/FirewallFactory.sol";
import {FirewallModule} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {PolicyPackRegistry} from "../../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../../src/SimpleEntitlementManager.sol";

import {InfiniteApprovalPolicy} from "../../src/policies/InfiniteApprovalPolicy.sol";
import {LargeTransferDelayPolicy} from "../../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../../src/policies/NewReceiverDelayPolicy.sol";

import {MockPolicy} from "../mocks/MockPolicies.sol";

abstract contract SmokeBase is Test {
    uint256 internal constant BASE_PACK_CONSERVATIVE = 0;
    uint256 internal constant BASE_PACK_DEFI = 1;

    address internal OWNER = address(this);
    address internal RECOVERY = address(0xB0B);

    uint256 internal constant LARGE_THRESHOLD = 1 ether;
    uint48 internal constant LARGE_DELAY = 2 days;
    uint48 internal constant NEW_RECEIVER_DELAY = 1 days;

    FirewallFactory internal factory;
    PolicyPackRegistry internal registry;
    SimpleEntitlementManager internal entitlement;

    InfiniteApprovalPolicy internal conservativeApprove;
    InfiniteApprovalPolicy internal defiApprove;
    LargeTransferDelayPolicy internal largeTransfer;
    NewReceiverDelayPolicy internal newReceiver;

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery,
        uint256 basePackId
    );

    function _deployV2WithRealBasePacks() internal {
        registry = new PolicyPackRegistry(address(this));
        entitlement = new SimpleEntitlementManager(address(this));
        factory = new FirewallFactory(address(registry), address(entitlement));

        conservativeApprove = new InfiniteApprovalPolicy(type(uint256).max, false);
        defiApprove = new InfiniteApprovalPolicy(type(uint256).max, true);
        largeTransfer = new LargeTransferDelayPolicy(LARGE_THRESHOLD, LARGE_DELAY);
        newReceiver = new NewReceiverDelayPolicy(NEW_RECEIVER_DELAY);

        address[] memory conservative = new address[](3);
        conservative[0] = address(conservativeApprove);
        conservative[1] = address(largeTransfer);
        conservative[2] = address(newReceiver);
        registry.registerPack(
            BASE_PACK_CONSERVATIVE,
            registry.PACK_TYPE_BASE(),
            keccak256("base-conservative"),
            true,
            conservative
        );

        address[] memory defi = new address[](3);
        defi[0] = address(defiApprove);
        defi[1] = address(largeTransfer);
        defi[2] = address(newReceiver);
        registry.registerPack(BASE_PACK_DEFI, registry.PACK_TYPE_BASE(), keccak256("base-defi"), true, defi);
    }

    function _deployV2WithCustomBase(address[] memory basePolicies, uint256 basePackId) internal {
        registry = new PolicyPackRegistry(address(this));
        entitlement = new SimpleEntitlementManager(address(this));
        factory = new FirewallFactory(address(registry), address(entitlement));

        registry.registerPack(basePackId, registry.PACK_TYPE_BASE(), keccak256("base-custom"), true, basePolicies);
    }

    function _registerAddonPack(uint256 packId, address[] memory policies, bool active) internal {
        registry.registerPack(packId, registry.PACK_TYPE_ADDON(), keccak256("addon"), active, policies);
    }

    function _createWalletAndRouter(uint256 basePackId)
        internal
        returns (FirewallModule wallet, PolicyRouter router)
    {
        vm.recordLogs();
        address walletAddr = factory.createWallet(OWNER, RECOVERY, basePackId);
        wallet = FirewallModule(payable(walletAddr));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("WalletCreated(address,address,address,address,uint256)");
        address routerAddr = address(0);
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(factory) &&
                entries[i].topics.length == 4 &&
                entries[i].topics[0] == sig
            ) {
                assertEq(address(uint160(uint256(entries[i].topics[1]))), OWNER);
                assertEq(address(uint160(uint256(entries[i].topics[2]))), walletAddr);
                routerAddr = address(uint160(uint256(entries[i].topics[3])));
                (address recoveryFromEvent, uint256 basePackIdFromEvent) =
                    abi.decode(entries[i].data, (address, uint256));
                assertEq(recoveryFromEvent, RECOVERY);
                assertEq(basePackIdFromEvent, basePackId);
                break;
            }
        }

        assertTrue(routerAddr != address(0), "WalletCreated router not found");
        router = PolicyRouter(routerAddr);
    }

    function _grantEntitlement(uint256 packId, bool entitled) internal {
        entitlement.setEntitlement(OWNER, packId, entitled);
    }

    function _makeMockPolicy(Decision d, uint48 delaySeconds) internal returns (MockPolicy) {
        return new MockPolicy(d, delaySeconds);
    }
}
