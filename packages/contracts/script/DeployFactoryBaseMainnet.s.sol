// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {FirewallFactory} from "../src/FirewallFactory.sol";
import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";
import {PolicyPackRegistry} from "../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../src/SimpleEntitlementManager.sol";

contract DeployFactoryBaseMainnet is Script {
    function run() external returns (FirewallFactory factory) {
        vm.startBroadcast();
        address owner = vm.envOr("PACK_OWNER", tx.origin);

        // Base policies preserve existing preset semantics and parameters.
        InfiniteApprovalPolicy conservativeApprove = new InfiniteApprovalPolicy(type(uint256).max, false);
        InfiniteApprovalPolicy defiApprove = new InfiniteApprovalPolicy(type(uint256).max, true);

        PolicyPackRegistry registry = new PolicyPackRegistry(owner);
        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(owner);

        // NOTE: Default base packs exclude UnknownContractBlockPolicy (centralized allowlist).
        address[] memory conservative = new address[](3);
        conservative[0] = address(conservativeApprove);
        conservative[1] = 0x6572d09a09891E8A36512d07bd9F1B79b86625bc;
        conservative[2] = 0xfE18b6db91b45d14693bf7980D1f958B17e18d18;
        registry.registerPack(0, registry.PACK_TYPE_BASE(), keccak256("base-conservative"), true, conservative);

        address[] memory defi = new address[](3);
        defi[0] = address(defiApprove);
        defi[1] = 0x6572d09a09891E8A36512d07bd9F1B79b86625bc;
        defi[2] = 0xfE18b6db91b45d14693bf7980D1f958B17e18d18;
        registry.registerPack(1, registry.PACK_TYPE_BASE(), keccak256("base-defi"), true, defi);

        factory = new FirewallFactory(address(registry), address(entitlement));
        vm.stopBroadcast();
    }
}
