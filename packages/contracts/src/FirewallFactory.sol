// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FirewallModule} from "./FirewallModule.sol";
import {PolicyRouter} from "./PolicyRouter.sol";
import {IPolicyPackRegistry} from "./interfaces/IPolicyPackRegistry.sol";

error Factory_ZeroAddress();
error Factory_UnauthorizedOwner(address caller, address owner);
error Factory_InvalidBasePack(uint256 packId);
error Factory_InactiveBasePack(uint256 packId);

/// @notice MVP deploy-based factory. No admin powers over wallets after creation.
contract FirewallFactory {
    uint8 internal constant PACK_TYPE_BASE = 0;

    uint256 public constant BASE_PACK_CONSERVATIVE = 0;
    uint256 public constant BASE_PACK_DEFI = 1;

    address public immutable policyPackRegistry;
    address public immutable entitlementManager;
    address public immutable feeConfigAdmin;
    mapping(address => bool) public isFactoryVault;

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery,
        uint256 basePackId
    );

    constructor(address policyPackRegistry_, address entitlementManager_) {
        if (policyPackRegistry_ == address(0)) revert Factory_ZeroAddress();
        policyPackRegistry = policyPackRegistry_;
        entitlementManager = entitlementManager_;
        feeConfigAdmin = msg.sender;
    }

    function createWallet(address owner, address recovery, uint256 basePackId)
        external
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
        PolicyRouter router =
            new PolicyRouter(owner, address(m), policyPackRegistry, entitlementManager, basePackId);
        m.init(address(router), owner, recovery, feeConfigAdmin, address(0));
        wallet = address(m);
        isFactoryVault[wallet] = true;

        emit WalletCreated(owner, wallet, address(router), recovery, basePackId);
    }
}
