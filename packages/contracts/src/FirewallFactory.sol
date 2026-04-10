// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FirewallModule} from "./FirewallModule.sol";
import {IPolicyPackRegistry} from "./interfaces/IPolicyPackRegistry.sol";

error Factory_ZeroAddress();
error Factory_UnauthorizedOwner(address caller, address owner);
error Factory_InvalidBasePack(uint256 packId);
error Factory_InactiveBasePack(uint256 packId);
error Factory_InvalidRouterDeployer(address deployer);

interface IPolicyRouterDeployer {
    function deploy(
        address owner,
        address firewallModule,
        address policyPackRegistry,
        address entitlementManager,
        uint256 basePackId
    ) external returns (address router);
}

/// @notice MVP deploy-based factory. No admin powers over wallets after creation.
contract FirewallFactory {
    uint8 internal constant PACK_TYPE_BASE = 0;

    uint256 public constant BASE_PACK_CONSERVATIVE = 0;
    uint256 public constant BASE_PACK_DEFI = 1;

    address public immutable policyPackRegistry;
    address public immutable entitlementManager;
    address public immutable policyRouterDeployer;
    // Legacy deployment-level admin record (kept for introspection/backward compatibility).
    address public immutable feeConfigAdmin;
    mapping(address => bool) public isFactoryVault;
    mapping(address => address) public latestWalletOfOwner;

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery,
        uint256 basePackId
    );

    constructor(address policyPackRegistry_, address entitlementManager_, address policyRouterDeployer_) {
        if (policyPackRegistry_ == address(0)) revert Factory_ZeroAddress();
        if (policyRouterDeployer_ == address(0) || policyRouterDeployer_.code.length == 0) {
            revert Factory_InvalidRouterDeployer(policyRouterDeployer_);
        }
        policyPackRegistry = policyPackRegistry_;
        entitlementManager = entitlementManager_;
        policyRouterDeployer = policyRouterDeployer_;
        feeConfigAdmin = msg.sender;
    }

    function createWallet(address owner, address recovery, uint256 basePackId)
        external
        payable
        returns (address wallet)
    {
        if (owner == address(0)) revert Factory_ZeroAddress();
        if (msg.sender != owner) revert Factory_UnauthorizedOwner(msg.sender, owner);
        if (recovery == address(0)) revert Factory_ZeroAddress();

        IPolicyPackRegistry registry = IPolicyPackRegistry(policyPackRegistry);
        if (!registry.isPackActive(basePackId)) revert Factory_InactiveBasePack(basePackId);
        if (registry.packTypeOf(basePackId) != PACK_TYPE_BASE) {
            revert Factory_InvalidBasePack(basePackId);
        }

        FirewallModule m = new FirewallModule();
        address router = IPolicyRouterDeployer(policyRouterDeployer).deploy(
            owner, address(m), policyPackRegistry, entitlementManager, basePackId
        );
        // Vault owner is fee-config admin by default to avoid centralized fee-control risk.
        m.init{value: msg.value}(router, owner, recovery, owner, address(0));
        wallet = address(m);
        isFactoryVault[wallet] = true;
        latestWalletOfOwner[owner] = wallet;

        emit WalletCreated(owner, wallet, router, recovery, basePackId);
    }
}
