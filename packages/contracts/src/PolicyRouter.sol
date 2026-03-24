// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy, IFirewallPostExecPolicy} from "./interfaces/IFirewallPolicy.sol";
import {IPolicyPackRegistry} from "./interfaces/IPolicyPackRegistry.sol";
import {IEntitlementManager} from "./interfaces/IEntitlementManager.sol";
import {IPolicyIntrospection, PolicyConfigEntry} from "./interfaces/IPolicyIntrospection.sol";

error Router_ZeroPolicies();
error Router_InvalidPolicy(address policy);
error Router_Unauthorized();
error Router_ZeroAddress();
error Router_FirewallAlreadySet();
error Router_InvalidBasePack(uint256 packId);
error Router_InvalidAddonPack(uint256 packId);
error Router_PackNotActive(uint256 packId);
error Router_PackAlreadyEnabled(uint256 packId);
error Router_NotEntitled(uint256 packId);
error Router_EntitlementUnavailable();
error Router_InvalidPackAccessMode(uint256 packId, uint8 packAccessMode);
error Router_DuplicatePolicy(address policy);
error Router_PolicyMissingMetadata(address policy);
error Router_InvalidPolicyMetadata(address policy);

contract PolicyRouter {
    uint8 internal constant PACK_TYPE_BASE = 0;
    uint8 internal constant PACK_TYPE_ADDON = 1;
    uint8 internal constant PACK_ACCESS_FREE = 0;
    uint8 internal constant PACK_ACCESS_ENTITLED = 1;

    // Base policies are fixed at creation and cannot be removed.
    IFirewallPolicy[] public policies;

    address public immutable owner;
    address public immutable policyPackRegistry;
    address public immutable entitlementManager;
    uint256 public immutable basePackId;
    address public firewallModule;

    event FirewallModuleSet(address indexed firewallModule);
    event PostExecHookFailed(address indexed policy, bytes returndata);
    event AddonPackEnabled(uint256 indexed packId);

    uint256[] internal _enabledAddonPackIds;
    mapping(uint256 => bool) public isAddonPackEnabled;
    mapping(uint256 => address[]) internal _enabledAddonPoliciesByPack;

    constructor(
        address owner_,
        address firewallModule_,
        address policyPackRegistry_,
        address entitlementManager_,
        uint256 basePackId_
    ) {
        if (owner_ == address(0)) revert Router_ZeroAddress();
        if (firewallModule_ == address(0)) revert Router_ZeroAddress();
        if (policyPackRegistry_ == address(0)) revert Router_ZeroAddress();

        owner = owner_;
        firewallModule = firewallModule_;
        policyPackRegistry = policyPackRegistry_;
        entitlementManager = entitlementManager_;
        basePackId = basePackId_;

        IPolicyPackRegistry registry = IPolicyPackRegistry(policyPackRegistry_);
        if (!registry.isPackActive(basePackId_)) revert Router_PackNotActive(basePackId_);
        if (registry.packTypeOf(basePackId_) != PACK_TYPE_BASE) {
            revert Router_InvalidBasePack(basePackId_);
        }

        address[] memory basePolicies = registry.getPackPolicies(basePackId_);
        uint256 len = basePolicies.length;
        if (len == 0) revert Router_ZeroPolicies();

        for (uint256 i = 0; i < len; i++) {
            address p = basePolicies[i];
            if (p == address(0)) revert Router_InvalidPolicy(p);
            if (p.code.length == 0) revert Router_InvalidPolicy(p);
            _assertPolicyMetadata(p);
            for (uint256 j = 0; j < i; j++) {
                if (basePolicies[j] == p) revert Router_DuplicatePolicy(p);
            }
            policies.push(IFirewallPolicy(p));
        }
    }

    function policyCount() external view returns (uint256) {
        return policies.length;
    }

    function addonPackCount() external view returns (uint256) {
        return _enabledAddonPackIds.length;
    }

    function enabledAddonPackAt(uint256 index) external view returns (uint256) {
        return _enabledAddonPackIds[index];
    }

    function enabledAddonPolicyAt(uint256 packId, uint256 index) external view returns (address) {
        return _enabledAddonPoliciesByPack[packId][index];
    }

    function enabledAddonPolicyCount(uint256 packId) external view returns (uint256) {
        return _enabledAddonPoliciesByPack[packId].length;
    }

    function enableAddonPack(uint256 packId) external {
        if (msg.sender != owner) revert Router_Unauthorized();
        if (isAddonPackEnabled[packId]) revert Router_PackAlreadyEnabled(packId);

        IPolicyPackRegistry registry = IPolicyPackRegistry(policyPackRegistry);
        if (!registry.isPackActive(packId)) revert Router_PackNotActive(packId);
        if (registry.packTypeOf(packId) != PACK_TYPE_ADDON) revert Router_InvalidAddonPack(packId);

        uint8 packAccessMode = registry.packAccessModeOf(packId);
        if (packAccessMode == PACK_ACCESS_ENTITLED) {
            if (entitlementManager == address(0)) revert Router_EntitlementUnavailable();
            if (!IEntitlementManager(entitlementManager).isEntitled(owner, packId)) {
                revert Router_NotEntitled(packId);
            }
        } else if (packAccessMode != PACK_ACCESS_FREE) {
            revert Router_InvalidPackAccessMode(packId, packAccessMode);
        }

        address[] memory addonPolicies = registry.getPackPolicies(packId);
        if (addonPolicies.length == 0) revert Router_ZeroPolicies();
        for (uint256 i = 0; i < addonPolicies.length; i++) {
            address policy = addonPolicies[i];
            if (policy == address(0)) revert Router_InvalidPolicy(policy);
            if (policy.code.length == 0) revert Router_InvalidPolicy(policy);
            _assertPolicyMetadata(policy);
            _assertPolicyUnique(policy, addonPolicies, i);
            _enabledAddonPoliciesByPack[packId].push(policy);
        }

        isAddonPackEnabled[packId] = true;
        _enabledAddonPackIds.push(packId);
        emit AddonPackEnabled(packId);
    }

    // Legacy one-time binding (constructor already binds in V2).
    function setFirewallModule(address _module) external {
        if (msg.sender != owner) revert Router_Unauthorized();
        if (_module == address(0)) revert Router_ZeroAddress();
        if (firewallModule != address(0)) revert Router_FirewallAlreadySet();

        firewallModule = _module;
        emit FirewallModuleSet(_module);
    }

    function evaluate(
        address vault,
        address to,
        uint256 value,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delaySeconds) {
        (Decision finalDecision, uint48 maxDelay) = _evaluateBasePolicies(vault, to, value, data);
        if (finalDecision == Decision.Revert) return (Decision.Revert, 0);

        (finalDecision, maxDelay) =
            _evaluateAddonSnapshots(vault, to, value, data, finalDecision, maxDelay);
        return (finalDecision, maxDelay);
    }

    function notifyExecuted(
        address vault,
        address to,
        uint256 value,
        bytes calldata data
    ) external {
        if (msg.sender != firewallModule) revert Router_Unauthorized();

        uint256 baseLen = policies.length;
        for (uint256 i = 0; i < baseLen; i++) {
            _notify(address(policies[i]), vault, to, value, data);
        }

        uint256 addonPackLen = _enabledAddonPackIds.length;
        for (uint256 i = 0; i < addonPackLen; i++) {
            uint256 packId = _enabledAddonPackIds[i];
            address[] storage addonPolicies = _enabledAddonPoliciesByPack[packId];
            uint256 addonPolicyLen = addonPolicies.length;
            for (uint256 j = 0; j < addonPolicyLen; j++) {
                _notify(addonPolicies[j], vault, to, value, data);
            }
        }
    }

    function _notify(address policy, address vault, address to, uint256 value, bytes calldata data)
        internal
    {
        (bool ok, bytes memory ret) = policy.call(
            abi.encodeWithSelector(IFirewallPostExecPolicy.onExecuted.selector, vault, to, value, data)
        );
        if (!ok) emit PostExecHookFailed(policy, ret);
    }

    function _foldDecision(
        Decision currentDecision,
        uint48 currentDelay,
        Decision nextDecision,
        uint48 nextDelay
    ) internal pure returns (Decision finalDecision, uint48 maxDelay) {
        if (nextDecision == Decision.Revert) return (Decision.Revert, 0);

        finalDecision = currentDecision;
        maxDelay = currentDelay;
        if (nextDecision == Decision.Delay) {
            finalDecision = Decision.Delay;
            if (nextDelay > maxDelay) maxDelay = nextDelay;
        }
    }

    function _evaluateBasePolicies(address vault, address to, uint256 value, bytes calldata data)
        internal
        view
        returns (Decision finalDecision, uint48 maxDelay)
    {
        finalDecision = Decision.Allow;
        maxDelay = 0;

        uint256 baseLen = policies.length;
        for (uint256 i = 0; i < baseLen; i++) {
            (Decision d, uint48 ds) = policies[i].evaluate(vault, to, value, data);
            (finalDecision, maxDelay) = _foldDecision(finalDecision, maxDelay, d, ds);
            if (finalDecision == Decision.Revert) return (Decision.Revert, 0);
        }
    }

    function _evaluateAddonSnapshots(
        address vault,
        address to,
        uint256 value,
        bytes calldata data,
        Decision initialDecision,
        uint48 initialDelay
    ) internal view returns (Decision finalDecision, uint48 maxDelay) {
        finalDecision = initialDecision;
        maxDelay = initialDelay;

        uint256 addonPackLen = _enabledAddonPackIds.length;
        for (uint256 i = 0; i < addonPackLen; i++) {
            (finalDecision, maxDelay) = _evaluateSingleAddonSnapshot(
                _enabledAddonPackIds[i], vault, to, value, data, finalDecision, maxDelay
            );
            if (finalDecision == Decision.Revert) return (Decision.Revert, 0);
        }
    }

    function _evaluateSingleAddonSnapshot(
        uint256 packId,
        address vault,
        address to,
        uint256 value,
        bytes calldata data,
        Decision initialDecision,
        uint48 initialDelay
    ) internal view returns (Decision finalDecision, uint48 maxDelay) {
        finalDecision = initialDecision;
        maxDelay = initialDelay;

        address[] storage addonPolicies = _enabledAddonPoliciesByPack[packId];
        uint256 addonPolicyLen = addonPolicies.length;
        for (uint256 j = 0; j < addonPolicyLen; j++) {
            (Decision d, uint48 ds) = IFirewallPolicy(addonPolicies[j]).evaluate(vault, to, value, data);
            (finalDecision, maxDelay) = _foldDecision(finalDecision, maxDelay, d, ds);
            if (finalDecision == Decision.Revert) return (Decision.Revert, 0);
        }
    }

    function _assertPolicyUnique(address policy, address[] memory packPolicies, uint256 index) internal view {
        uint256 baseLen = policies.length;
        for (uint256 i = 0; i < baseLen; i++) {
            if (address(policies[i]) == policy) revert Router_DuplicatePolicy(policy);
        }

        uint256 enabledPackLen = _enabledAddonPackIds.length;
        for (uint256 i = 0; i < enabledPackLen; i++) {
            address[] storage existing = _enabledAddonPoliciesByPack[_enabledAddonPackIds[i]];
            uint256 existingLen = existing.length;
            for (uint256 j = 0; j < existingLen; j++) {
                if (existing[j] == policy) revert Router_DuplicatePolicy(policy);
            }
        }

        for (uint256 i = 0; i < index; i++) {
            if (packPolicies[i] == policy) revert Router_DuplicatePolicy(policy);
        }
    }

    function _assertPolicyMetadata(address policy) internal view {
        IPolicyIntrospection introspection = IPolicyIntrospection(policy);

        bytes32 key;
        try introspection.policyKey() returns (bytes32 policyKey_) {
            key = policyKey_;
        } catch {
            revert Router_PolicyMissingMetadata(policy);
        }

        string memory name;
        try introspection.policyName() returns (string memory policyName_) {
            name = policyName_;
        } catch {
            revert Router_PolicyMissingMetadata(policy);
        }

        string memory description;
        try introspection.policyDescription() returns (string memory policyDescription_) {
            description = policyDescription_;
        } catch {
            revert Router_PolicyMissingMetadata(policy);
        }

        uint16 version;
        try introspection.policyConfigVersion() returns (uint16 v) {
            version = v;
        } catch {
            revert Router_PolicyMissingMetadata(policy);
        }

        PolicyConfigEntry[] memory entries;
        try introspection.policyConfig() returns (PolicyConfigEntry[] memory cfg) {
            entries = cfg;
        } catch {
            revert Router_PolicyMissingMetadata(policy);
        }

        if (
            key == bytes32(0) || bytes(name).length == 0 || bytes(description).length == 0 || version == 0
                || entries.length == 0
        ) {
            revert Router_InvalidPolicyMetadata(policy);
        }

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].key == bytes32(0)) revert Router_InvalidPolicyMetadata(policy);
        }
    }
}
