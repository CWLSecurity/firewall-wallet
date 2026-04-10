// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PolicyRouter} from "./PolicyRouter.sol";

/// @notice Stateless helper that deploys PolicyRouter instances.
///         Kept separate to avoid embedding router creation bytecode into FirewallFactory.
contract PolicyRouterDeployer {
    function deploy(
        address owner,
        address firewallModule,
        address policyPackRegistry,
        address entitlementManager,
        uint256 basePackId
    ) external returns (address router) {
        router = address(
            new PolicyRouter(owner, firewallModule, policyPackRegistry, entitlementManager, basePackId)
        );
    }
}

