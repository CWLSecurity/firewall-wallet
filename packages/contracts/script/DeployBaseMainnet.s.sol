// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {PolicyRouter} from "../src/PolicyRouter.sol";
import {FirewallModule} from "../src/FirewallModule.sol";
import {PolicyPackRegistry} from "../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../src/SimpleEntitlementManager.sol";

import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";
import {LargeTransferDelayPolicy} from "../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../src/policies/NewReceiverDelayPolicy.sol";
import {UnknownContractBlockPolicy} from "../src/policies/UnknownContractBlockPolicy.sol";

contract DeployBaseMainnet is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address owner = vm.envAddress("OWNER");
        address recovery = vm.envAddress("RECOVERY");

        vm.startBroadcast(pk);

        // NOTE: Deprecated path. Prefer Factory deployments for production.
        PolicyPackRegistry registry = new PolicyPackRegistry(owner);
        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(owner);

        // 1) Deploy policies
        // InfiniteApprovalPolicy: constructor(uint256,bool)
        InfiniteApprovalPolicy pApprove = new InfiniteApprovalPolicy(type(uint256).max, false);

        LargeTransferDelayPolicy pLarge = new LargeTransferDelayPolicy(
            0.05 ether,
            3600
        );

        NewReceiverDelayPolicy pNew = new NewReceiverDelayPolicy(
            3600
        );

        // UnknownContractBlockPolicy: constructor(address)
        UnknownContractBlockPolicy pUnknown = new UnknownContractBlockPolicy(owner);

        address[] memory base = new address[](4);
        base[0] = address(pApprove);
        base[1] = address(pLarge);
        base[2] = address(pNew);
        base[3] = address(pUnknown);
        registry.registerPack(0, registry.PACK_TYPE_BASE(), keccak256("base-conservative"), true, base);

        // 2) Deploy firewall + router
        FirewallModule firewall = new FirewallModule();

        PolicyRouter router =
            new PolicyRouter(owner, address(firewall), address(registry), address(entitlement), 0);

        // 3) Init firewall
        firewall.init(address(router), owner, recovery);

        vm.stopBroadcast();

        // 4) Save addresses
        string memory obj = "deploy";
        vm.serializeAddress(obj, "router", address(router));
        vm.serializeAddress(obj, "firewall", address(firewall));
        vm.serializeAddress(obj, "policyPackRegistry", address(registry));
        vm.serializeAddress(obj, "entitlementManager", address(entitlement));
        vm.serializeAddress(obj, "policy_infiniteApproval", address(pApprove));
        vm.serializeAddress(obj, "policy_largeTransferDelay", address(pLarge));
        vm.serializeAddress(obj, "policy_newReceiverDelay", address(pNew));
        vm.serializeAddress(obj, "policy_unknownContractBlock", address(pUnknown));
        string memory out = vm.serializeString(obj, "network", "base-mainnet");
        vm.writeJson(out, "deployments/base-mainnet.json");
    }
}
