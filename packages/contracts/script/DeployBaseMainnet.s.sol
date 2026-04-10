// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {FirewallFactory} from "../src/FirewallFactory.sol";
import {PolicyRouterDeployer} from "../src/PolicyRouterDeployer.sol";
import {PolicyPackRegistry} from "../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../src/SimpleEntitlementManager.sol";

import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";
import {DeFiApprovalPolicy} from "../src/policies/DeFiApprovalPolicy.sol";
import {ApprovalToNewSpenderDelayPolicy} from "../src/policies/ApprovalToNewSpenderDelayPolicy.sol";
import {Erc20FirstNewRecipientDelayPolicy} from "../src/policies/Erc20FirstNewRecipientDelayPolicy.sol";
import {LargeTransferDelayPolicy} from "../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../src/policies/NewReceiverDelayPolicy.sol";
import {NewEOAReceiverDelayPolicy} from "../src/policies/NewEOAReceiverDelayPolicy.sol";

contract DeployBaseMainnet is Script {
    uint16 internal constant PACK_VERSION_V1 = 1;
    uint256 internal constant BASE_PACK_CONSERVATIVE = 0;
    uint256 internal constant BASE_PACK_DEFI = 1;
    uint256 internal constant ADDON_PACK_APPROVAL_HARDENING = 2;
    uint256 internal constant ADDON_PACK_NEW_RECEIVER_24H = 3;
    uint256 internal constant ADDON_PACK_LARGE_TRANSFER_24H = 4;

    struct PackConfig {
        uint256 conservativeLargeEthThresholdWei;
        uint256 conservativeLargeErc20ThresholdUnits;
        uint48 conservativeLargeDelaySeconds;
        uint48 conservativeNewReceiverDelaySeconds;
        uint256 defiLargeEthThresholdWei;
        uint256 defiLargeErc20ThresholdUnits;
        uint48 defiLargeDelaySeconds;
        uint48 defiApprovalToNewSpenderDelaySeconds;
        uint48 defiErc20FirstRecipientDelaySeconds;
        uint48 defiNewReceiverDelaySeconds;
        uint256 addonLargeEthThresholdWei;
        uint256 addonLargeErc20ThresholdUnits;
        uint48 addonLargeDelaySeconds;
        uint48 addonNewReceiverDelaySeconds;
    }

    struct DeploySnapshot {
        address factory;
        address policyRouterDeployer;
        address registry;
        address entitlement;
        address conservativeApprove;
        address defiApprove;
        address defiApprovalToNewSpender;
        address defiErc20FirstRecipient;
        address addonApprovalHardening;
        address conservativeLargeTransfer;
        address defiLargeTransfer;
        address addonLargeTransfer;
        address conservativeNewReceiver;
        address defiNewReceiver;
        address addonNewReceiver;
    }

    function run() external returns (FirewallFactory factory) {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address owner = vm.envOr("PACK_OWNER", vm.addr(pk));
        PackConfig memory cfg = PackConfig({
            // TEMP(TEST): conservative large-transfer thresholds set to zero. Revert to 0.05 ether for production.
            conservativeLargeEthThresholdWei: vm.envOr("LARGE_TRANSFER_THRESHOLD_WEI", uint256(0)),
            conservativeLargeErc20ThresholdUnits: vm.envOr(
                "LARGE_TRANSFER_ERC20_THRESHOLD_UNITS", uint256(0)
            ),
            conservativeLargeDelaySeconds: uint48(vm.envOr("LARGE_TRANSFER_DELAY_SECONDS", uint256(3600))),
            conservativeNewReceiverDelaySeconds: uint48(vm.envOr("NEW_RECEIVER_DELAY_SECONDS", uint256(3600))),
            defiLargeEthThresholdWei: vm.envOr("DEFI_LARGE_TRANSFER_THRESHOLD_WEI", uint256(0.25 ether)),
            defiLargeErc20ThresholdUnits: vm.envOr(
                "DEFI_LARGE_TRANSFER_ERC20_THRESHOLD_UNITS", uint256(0.25 ether)
            ),
            defiLargeDelaySeconds: uint48(vm.envOr("DEFI_LARGE_TRANSFER_DELAY_SECONDS", uint256(1800))),
            defiApprovalToNewSpenderDelaySeconds: uint48(
                vm.envOr("DEFI_APPROVAL_TO_NEW_SPENDER_DELAY_SECONDS", uint256(1800))
            ),
            defiErc20FirstRecipientDelaySeconds: uint48(
                vm.envOr("DEFI_ERC20_FIRST_RECIPIENT_DELAY_SECONDS", uint256(1800))
            ),
            defiNewReceiverDelaySeconds: uint48(vm.envOr("DEFI_NEW_RECEIVER_DELAY_SECONDS", uint256(1800))),
            addonLargeEthThresholdWei: vm.envOr("VAULT_LARGE_TRANSFER_THRESHOLD_WEI", uint256(1 ether)),
            addonLargeErc20ThresholdUnits: vm.envOr(
                "VAULT_LARGE_TRANSFER_ERC20_THRESHOLD_UNITS", uint256(1)
            ),
            addonLargeDelaySeconds: uint48(vm.envOr("VAULT_LARGE_TRANSFER_DELAY_SECONDS", uint256(24 hours))),
            addonNewReceiverDelaySeconds: uint48(vm.envOr("VAULT_NEW_RECEIVER_DELAY_SECONDS", uint256(24 hours)))
        });

        bool writeOutput = vm.envOr("WRITE_DEPLOYMENT_JSON", false);
        string memory outPath = vm.envOr("DEPLOYMENT_OUT_PATH", string("deployments/base-mainnet-v2.json"));

        DeploySnapshot memory snapshot;
        (factory, snapshot) = _deployV2(pk, owner, cfg);
        if (writeOutput) _writeDeploymentJson(snapshot, cfg, outPath);
    }

    function _deployV2(uint256 pk, address owner, PackConfig memory cfg)
        internal
        returns (FirewallFactory factory, DeploySnapshot memory snapshot)
    {
        vm.startBroadcast(pk);

        snapshot = _deployPolicies(cfg);

        PolicyPackRegistry registry = new PolicyPackRegistry(owner);
        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(owner);
        PolicyRouterDeployer routerDeployer = new PolicyRouterDeployer();

        _registerPacks(registry, snapshot);

        factory =
            new FirewallFactory(address(registry), address(entitlement), address(routerDeployer));
        vm.stopBroadcast();

        snapshot.factory = address(factory);
        snapshot.policyRouterDeployer = address(routerDeployer);
        snapshot.registry = address(registry);
        snapshot.entitlement = address(entitlement);
    }

    function _deployPolicies(PackConfig memory cfg) internal returns (DeploySnapshot memory snapshot) {
        snapshot.conservativeApprove = address(new InfiniteApprovalPolicy(type(uint256).max, false));
        snapshot.defiApprove = address(new DeFiApprovalPolicy());
        snapshot.defiApprovalToNewSpender =
            address(new ApprovalToNewSpenderDelayPolicy(cfg.defiApprovalToNewSpenderDelaySeconds));
        snapshot.defiErc20FirstRecipient =
            address(new Erc20FirstNewRecipientDelayPolicy(cfg.defiErc20FirstRecipientDelaySeconds));
        snapshot.addonApprovalHardening = address(new InfiniteApprovalPolicy(type(uint256).max, false));
        snapshot.conservativeLargeTransfer = address(
            new LargeTransferDelayPolicy(
                cfg.conservativeLargeEthThresholdWei,
                cfg.conservativeLargeErc20ThresholdUnits,
                cfg.conservativeLargeDelaySeconds
            )
        );
        snapshot.defiLargeTransfer = address(
            new LargeTransferDelayPolicy(
                cfg.defiLargeEthThresholdWei, cfg.defiLargeErc20ThresholdUnits, cfg.defiLargeDelaySeconds
            )
        );
        snapshot.addonLargeTransfer = address(
            new LargeTransferDelayPolicy(
                cfg.addonLargeEthThresholdWei, cfg.addonLargeErc20ThresholdUnits, cfg.addonLargeDelaySeconds
            )
        );
        snapshot.conservativeNewReceiver = address(new NewReceiverDelayPolicy(cfg.conservativeNewReceiverDelaySeconds));
        snapshot.defiNewReceiver = address(new NewEOAReceiverDelayPolicy(cfg.defiNewReceiverDelaySeconds));
        snapshot.addonNewReceiver = address(new NewReceiverDelayPolicy(cfg.addonNewReceiverDelaySeconds));
    }

    function _registerPacks(PolicyPackRegistry registry, DeploySnapshot memory snapshot) internal {
        // Base Pack 0: Conservative
        address[] memory conservative = new address[](3);
        conservative[0] = snapshot.conservativeApprove;
        conservative[1] = snapshot.conservativeLargeTransfer;
        conservative[2] = snapshot.conservativeNewReceiver;
        registry.registerPackDetailed(
            BASE_PACK_CONSERVATIVE,
            registry.PACK_TYPE_BASE(),
            registry.PACK_ACCESS_FREE(),
            keccak256("base-conservative"),
            "base-conservative",
            PACK_VERSION_V1,
            true,
            conservative
        );

        // Base Pack 1: DeFi Trader
        address[] memory defi = new address[](5);
        defi[0] = snapshot.defiApprove;
        defi[1] = snapshot.defiApprovalToNewSpender;
        defi[2] = snapshot.defiErc20FirstRecipient;
        defi[3] = snapshot.defiLargeTransfer;
        defi[4] = snapshot.defiNewReceiver;
        registry.registerPackDetailed(
            BASE_PACK_DEFI,
            registry.PACK_TYPE_BASE(),
            registry.PACK_ACCESS_FREE(),
            keccak256("base-defi"),
            "base-defi",
            PACK_VERSION_V1,
            true,
            defi
        );

        // Add-on Pack 2: Approval Hardening
        address[] memory approvalHardeningAddon = new address[](1);
        approvalHardeningAddon[0] = snapshot.addonApprovalHardening;
        registry.registerPackDetailed(
            ADDON_PACK_APPROVAL_HARDENING,
            registry.PACK_TYPE_ADDON(),
            registry.PACK_ACCESS_FREE(),
            keccak256("addon-approval-hardening"),
            "addon-approval-hardening",
            PACK_VERSION_V1,
            true,
            approvalHardeningAddon
        );

        // Add-on Pack 3: New Receiver 24h Delay
        address[] memory newReceiverAddon = new address[](1);
        newReceiverAddon[0] = snapshot.addonNewReceiver;
        registry.registerPackDetailed(
            ADDON_PACK_NEW_RECEIVER_24H,
            registry.PACK_TYPE_ADDON(),
            registry.PACK_ACCESS_FREE(),
            keccak256("addon-new-receiver-24h-delay"),
            "addon-new-receiver-24h-delay",
            PACK_VERSION_V1,
            true,
            newReceiverAddon
        );

        // Add-on Pack 4: Large Transfer 24h Delay
        address[] memory largeTransferAddon = new address[](1);
        largeTransferAddon[0] = snapshot.addonLargeTransfer;
        registry.registerPackDetailed(
            ADDON_PACK_LARGE_TRANSFER_24H,
            registry.PACK_TYPE_ADDON(),
            registry.PACK_ACCESS_FREE(),
            keccak256("addon-large-transfer-24h-delay"),
            "addon-large-transfer-24h-delay",
            PACK_VERSION_V1,
            true,
            largeTransferAddon
        );
    }

    function _writeDeploymentJson(DeploySnapshot memory snapshot, PackConfig memory cfg, string memory outPath)
        internal
    {
        string memory obj = "deploy";
        vm.serializeString(obj, "architecture", "wallet-v2-pack-factory");
        vm.serializeAddress(obj, "factory", snapshot.factory);
        vm.serializeAddress(obj, "policyRouterDeployer", snapshot.policyRouterDeployer);
        vm.serializeAddress(obj, "policyPackRegistry", snapshot.registry);
        vm.serializeAddress(obj, "entitlementManager", snapshot.entitlement);
        vm.serializeAddress(obj, "policy_infiniteApproval_conservative", snapshot.conservativeApprove);
        vm.serializeAddress(obj, "policy_approval_defi", snapshot.defiApprove);
        vm.serializeAddress(obj, "policy_approvalToNewSpenderDelay_defi", snapshot.defiApprovalToNewSpender);
        vm.serializeAddress(obj, "policy_erc20FirstNewRecipientDelay_defi", snapshot.defiErc20FirstRecipient);
        vm.serializeAddress(obj, "policy_infiniteApproval_addonApprovalHardening", snapshot.addonApprovalHardening);
        vm.serializeAddress(obj, "policy_largeTransferDelay_conservative", snapshot.conservativeLargeTransfer);
        vm.serializeAddress(obj, "policy_largeTransferDelay_defi", snapshot.defiLargeTransfer);
        vm.serializeAddress(obj, "policy_largeTransferDelay_addonLargeTransfer24h", snapshot.addonLargeTransfer);
        vm.serializeAddress(obj, "policy_newReceiverDelay_conservative", snapshot.conservativeNewReceiver);
        vm.serializeAddress(obj, "policy_newReceiverDelay_defi", snapshot.defiNewReceiver);
        vm.serializeAddress(obj, "policy_newReceiverDelay_addonNewReceiver24h", snapshot.addonNewReceiver);
        vm.serializeUint(obj, "basePackConservative", BASE_PACK_CONSERVATIVE);
        vm.serializeUint(obj, "basePackDefi", BASE_PACK_DEFI);
        vm.serializeUint(obj, "addonPackApprovalHardening", ADDON_PACK_APPROVAL_HARDENING);
        vm.serializeUint(obj, "addonPackNewReceiver24h", ADDON_PACK_NEW_RECEIVER_24H);
        vm.serializeUint(obj, "addonPackLargeTransfer24h", ADDON_PACK_LARGE_TRANSFER_24H);
        vm.serializeString(obj, "basePackConservativeSlug", "base-conservative");
        vm.serializeString(obj, "basePackDefiSlug", "base-defi");
        vm.serializeString(obj, "addonPackApprovalHardeningSlug", "addon-approval-hardening");
        vm.serializeString(obj, "addonPackNewReceiver24hSlug", "addon-new-receiver-24h-delay");
        vm.serializeString(obj, "addonPackLargeTransfer24hSlug", "addon-large-transfer-24h-delay");
        vm.serializeUint(obj, "packVersion", PACK_VERSION_V1);
        vm.serializeUint(obj, "conservativeLargeTransferThresholdWei", cfg.conservativeLargeEthThresholdWei);
        vm.serializeUint(
            obj, "conservativeLargeTransferErc20ThresholdUnits", cfg.conservativeLargeErc20ThresholdUnits
        );
        vm.serializeUint(obj, "conservativeLargeTransferDelaySeconds", cfg.conservativeLargeDelaySeconds);
        vm.serializeUint(obj, "conservativeNewReceiverDelaySeconds", cfg.conservativeNewReceiverDelaySeconds);
        vm.serializeUint(obj, "defiLargeTransferThresholdWei", cfg.defiLargeEthThresholdWei);
        vm.serializeUint(obj, "defiLargeTransferErc20ThresholdUnits", cfg.defiLargeErc20ThresholdUnits);
        vm.serializeUint(obj, "defiLargeTransferDelaySeconds", cfg.defiLargeDelaySeconds);
        vm.serializeUint(obj, "defiApprovalToNewSpenderDelaySeconds", cfg.defiApprovalToNewSpenderDelaySeconds);
        vm.serializeUint(obj, "defiErc20FirstRecipientDelaySeconds", cfg.defiErc20FirstRecipientDelaySeconds);
        vm.serializeUint(obj, "defiNewReceiverDelaySeconds", cfg.defiNewReceiverDelaySeconds);
        vm.serializeUint(obj, "addonLargeTransferThresholdWei", cfg.addonLargeEthThresholdWei);
        vm.serializeUint(obj, "addonLargeTransferErc20ThresholdUnits", cfg.addonLargeErc20ThresholdUnits);
        vm.serializeUint(obj, "addonLargeTransferDelaySeconds", cfg.addonLargeDelaySeconds);
        vm.serializeUint(obj, "addonNewReceiverDelaySeconds", cfg.addonNewReceiverDelaySeconds);
        string memory out = vm.serializeString(obj, "network", "base-mainnet");
        vm.writeJson(out, outPath);
    }
}
