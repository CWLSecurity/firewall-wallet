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
import {DeFiApprovalPolicy} from "../../src/policies/DeFiApprovalPolicy.sol";
import {ApprovalToNewSpenderDelayPolicy} from "../../src/policies/ApprovalToNewSpenderDelayPolicy.sol";
import {Erc20FirstNewRecipientDelayPolicy} from "../../src/policies/Erc20FirstNewRecipientDelayPolicy.sol";
import {LargeTransferDelayPolicy} from "../../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../../src/policies/NewReceiverDelayPolicy.sol";
import {NewEOAReceiverDelayPolicy} from "../../src/policies/NewEOAReceiverDelayPolicy.sol";

import {MockPolicy} from "../mocks/MockPolicies.sol";

abstract contract SmokeBase is Test {
    uint256 internal constant BASE_PACK_CONSERVATIVE = 0;
    uint256 internal constant BASE_PACK_DEFI = 1;
    uint256 internal constant ADDON_PACK_APPROVAL_HARDENING = 2;
    uint256 internal constant ADDON_PACK_NEW_RECEIVER_24H = 3;
    uint256 internal constant ADDON_PACK_LARGE_TRANSFER_24H = 4;
    uint16 internal constant PACK_VERSION_V1 = 1;

    address internal OWNER = address(this);
    address internal RECOVERY = address(0xB0B);

    uint256 internal constant LARGE_THRESHOLD = 0.05 ether;
    uint256 internal constant LARGE_ERC20_THRESHOLD_UNITS = 0.05 ether;
    uint48 internal constant LARGE_DELAY = 1 hours;
    uint48 internal constant NEW_RECEIVER_DELAY = 1 hours;

    uint256 internal constant DEFI_LARGE_THRESHOLD = 0.25 ether;
    uint256 internal constant DEFI_LARGE_ERC20_THRESHOLD_UNITS = 0.25 ether;
    uint48 internal constant DEFI_LARGE_DELAY = 30 minutes;
    uint48 internal constant DEFI_NEW_RECEIVER_DELAY = 30 minutes;
    uint48 internal constant DEFI_NEW_SPENDER_DELAY = 30 minutes;
    uint48 internal constant DEFI_NEW_ERC20_RECIPIENT_DELAY = 30 minutes;

    uint256 internal constant ADDON_LARGE_THRESHOLD = 1 ether;
    uint256 internal constant ADDON_LARGE_ERC20_THRESHOLD_UNITS = 1;
    uint48 internal constant ADDON_LARGE_DELAY = 24 hours;
    uint48 internal constant ADDON_NEW_RECEIVER_DELAY = 24 hours;

    FirewallFactory internal factory;
    PolicyPackRegistry internal registry;
    SimpleEntitlementManager internal entitlement;

    InfiniteApprovalPolicy internal conservativeApprove;
    DeFiApprovalPolicy internal defiApprove;
    ApprovalToNewSpenderDelayPolicy internal defiApprovalToNewSpender;
    Erc20FirstNewRecipientDelayPolicy internal defiErc20FirstRecipient;
    LargeTransferDelayPolicy internal conservativeLargeTransfer;
    LargeTransferDelayPolicy internal defiLargeTransfer;
    NewReceiverDelayPolicy internal conservativeNewReceiver;
    NewEOAReceiverDelayPolicy internal defiNewReceiver;
    InfiniteApprovalPolicy internal addonApprovalHardening;
    LargeTransferDelayPolicy internal addonLargeTransfer;
    NewReceiverDelayPolicy internal addonNewReceiver;

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
        defiApprove = new DeFiApprovalPolicy();
        defiApprovalToNewSpender = new ApprovalToNewSpenderDelayPolicy(DEFI_NEW_SPENDER_DELAY);
        defiErc20FirstRecipient = new Erc20FirstNewRecipientDelayPolicy(DEFI_NEW_ERC20_RECIPIENT_DELAY);
        conservativeLargeTransfer =
            new LargeTransferDelayPolicy(LARGE_THRESHOLD, LARGE_ERC20_THRESHOLD_UNITS, LARGE_DELAY);
        defiLargeTransfer =
            new LargeTransferDelayPolicy(DEFI_LARGE_THRESHOLD, DEFI_LARGE_ERC20_THRESHOLD_UNITS, DEFI_LARGE_DELAY);
        conservativeNewReceiver = new NewReceiverDelayPolicy(NEW_RECEIVER_DELAY);
        defiNewReceiver = new NewEOAReceiverDelayPolicy(DEFI_NEW_RECEIVER_DELAY);
        addonApprovalHardening = new InfiniteApprovalPolicy(type(uint256).max, false);
        addonLargeTransfer =
            new LargeTransferDelayPolicy(ADDON_LARGE_THRESHOLD, ADDON_LARGE_ERC20_THRESHOLD_UNITS, ADDON_LARGE_DELAY);
        addonNewReceiver = new NewReceiverDelayPolicy(ADDON_NEW_RECEIVER_DELAY);

        address[] memory conservative = new address[](3);
        conservative[0] = address(conservativeApprove);
        conservative[1] = address(conservativeLargeTransfer);
        conservative[2] = address(conservativeNewReceiver);
        registry.registerPackDetailed(
            BASE_PACK_CONSERVATIVE,
            registry.PACK_TYPE_BASE(),
            keccak256("base-conservative"),
            "base-conservative",
            PACK_VERSION_V1,
            true,
            conservative
        );

        address[] memory defi = new address[](5);
        defi[0] = address(defiApprove);
        defi[1] = address(defiApprovalToNewSpender);
        defi[2] = address(defiErc20FirstRecipient);
        defi[3] = address(defiLargeTransfer);
        defi[4] = address(defiNewReceiver);
        registry.registerPackDetailed(
            BASE_PACK_DEFI,
            registry.PACK_TYPE_BASE(),
            keccak256("base-defi"),
            "base-defi",
            PACK_VERSION_V1,
            true,
            defi
        );

        address[] memory approvalHardeningAddon = new address[](1);
        approvalHardeningAddon[0] = address(addonApprovalHardening);
        registry.registerPackDetailed(
            ADDON_PACK_APPROVAL_HARDENING,
            registry.PACK_TYPE_ADDON(),
            keccak256("addon-approval-hardening"),
            "addon-approval-hardening",
            PACK_VERSION_V1,
            true,
            approvalHardeningAddon
        );

        address[] memory newReceiverAddon = new address[](1);
        newReceiverAddon[0] = address(addonNewReceiver);
        registry.registerPackDetailed(
            ADDON_PACK_NEW_RECEIVER_24H,
            registry.PACK_TYPE_ADDON(),
            keccak256("addon-new-receiver-24h-delay"),
            "addon-new-receiver-24h-delay",
            PACK_VERSION_V1,
            true,
            newReceiverAddon
        );

        address[] memory largeTransferAddon = new address[](1);
        largeTransferAddon[0] = address(addonLargeTransfer);
        registry.registerPackDetailed(
            ADDON_PACK_LARGE_TRANSFER_24H,
            registry.PACK_TYPE_ADDON(),
            keccak256("addon-large-transfer-24h-delay"),
            "addon-large-transfer-24h-delay",
            PACK_VERSION_V1,
            true,
            largeTransferAddon
        );
    }

    function _deployV2WithCustomBase(address[] memory basePolicies, uint256 basePackId) internal {
        registry = new PolicyPackRegistry(address(this));
        entitlement = new SimpleEntitlementManager(address(this));
        factory = new FirewallFactory(address(registry), address(entitlement));

        registry.registerPackDetailed(
            basePackId,
            registry.PACK_TYPE_BASE(),
            keccak256("base-custom"),
            "base-custom",
            PACK_VERSION_V1,
            true,
            basePolicies
        );
    }

    function _registerAddonPack(uint256 packId, address[] memory policies, bool active) internal {
        registry.registerPackDetailed(
            packId,
            registry.PACK_TYPE_ADDON(),
            keccak256("addon"),
            "addon-custom",
            PACK_VERSION_V1,
            active,
            policies
        );
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
