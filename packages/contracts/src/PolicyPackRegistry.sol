// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPolicyPackRegistry} from "./interfaces/IPolicyPackRegistry.sol";
import {IPolicyIntrospection, PolicyConfigEntry} from "./interfaces/IPolicyIntrospection.sol";

error Registry_Unauthorized();
error Registry_ZeroAddress();
error Registry_UnknownPack(uint256 packId);
error Registry_PackExists(uint256 packId);
error Registry_ZeroPolicies();
error Registry_InvalidPolicy(address policy);
error Registry_InvalidPackType(uint8 packType);
error Registry_PolicyMissingMetadata(address policy);
error Registry_InvalidPolicyMetadata(address policy);
error Registry_InvalidPackVersion(uint16 version);

contract PolicyPackRegistry is IPolicyPackRegistry {
    uint8 public constant PACK_TYPE_BASE = 0;
    uint8 public constant PACK_TYPE_ADDON = 1;

    address public owner;

    struct PackMeta {
        bool exists;
        bool active;
        uint8 packType;
        bytes32 metadata;
        string slug;
        uint16 version;
    }

    mapping(uint256 => PackMeta) internal _packMeta;
    mapping(uint256 => address[]) internal _packPolicies;
    uint256[] internal _packIds;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PackRegistered(
        uint256 indexed packId, uint8 indexed packType, bool active, bytes32 metadata
    );
    event PackRegisteredDetailed(
        uint256 indexed packId,
        uint8 indexed packType,
        bool active,
        bytes32 metadata,
        string slug,
        uint16 version
    );
    event PackStatusSet(uint256 indexed packId, bool active);

    constructor(address owner_) {
        if (owner_ == address(0)) revert Registry_ZeroAddress();
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Registry_Unauthorized();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Registry_ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function registerPack(
        uint256 packId,
        uint8 packType,
        bytes32 metadata,
        bool active,
        address[] calldata policies
    ) external onlyOwner {
        _registerPack(packId, packType, metadata, "", 1, active, policies);
    }

    function registerPackDetailed(
        uint256 packId,
        uint8 packType,
        bytes32 metadata,
        string calldata slug,
        uint16 version,
        bool active,
        address[] calldata policies
    ) external onlyOwner {
        _registerPack(packId, packType, metadata, slug, version, active, policies);
    }

    function _registerPack(
        uint256 packId,
        uint8 packType,
        bytes32 metadata,
        string memory slug,
        uint16 version,
        bool active,
        address[] calldata policies
    ) internal {
        if (packType != PACK_TYPE_BASE && packType != PACK_TYPE_ADDON) {
            revert Registry_InvalidPackType(packType);
        }
        if (_packMeta[packId].exists) revert Registry_PackExists(packId);
        if (version == 0) revert Registry_InvalidPackVersion(version);

        uint256 len = policies.length;
        if (len == 0) revert Registry_ZeroPolicies();

        for (uint256 i = 0; i < len; i++) {
            address policy = policies[i];
            if (policy == address(0)) revert Registry_InvalidPolicy(policy);
            if (policy.code.length == 0) revert Registry_InvalidPolicy(policy);
            _assertPolicyMetadata(policy);
            _packPolicies[packId].push(policy);
        }

        _packMeta[packId] = PackMeta({
            exists: true,
            active: active,
            packType: packType,
            metadata: metadata,
            slug: slug,
            version: version
        });
        _packIds.push(packId);

        emit PackRegistered(packId, packType, active, metadata);
        emit PackRegisteredDetailed(packId, packType, active, metadata, slug, version);
    }

    function setPackActive(uint256 packId, bool active) external onlyOwner {
        PackMeta storage meta = _packMeta[packId];
        if (!meta.exists) revert Registry_UnknownPack(packId);
        meta.active = active;
        emit PackStatusSet(packId, active);
    }

    function isPackActive(uint256 packId) external view returns (bool) {
        PackMeta storage meta = _packMeta[packId];
        return meta.exists && meta.active;
    }

    function packTypeOf(uint256 packId) external view returns (uint8) {
        PackMeta storage meta = _packMeta[packId];
        if (!meta.exists) revert Registry_UnknownPack(packId);
        return meta.packType;
    }

    function metadataOf(uint256 packId) external view returns (bytes32) {
        PackMeta storage meta = _packMeta[packId];
        if (!meta.exists) revert Registry_UnknownPack(packId);
        return meta.metadata;
    }

    function packCount() external view returns (uint256) {
        return _packIds.length;
    }

    function packIdAt(uint256 index) external view returns (uint256) {
        return _packIds[index];
    }

    function packIds() external view returns (uint256[] memory) {
        return _packIds;
    }

    function getPackMeta(uint256 packId)
        external
        view
        returns (
            bool active,
            uint8 packType,
            bytes32 metadata,
            string memory slug,
            uint16 version,
            uint256 policyCount
        )
    {
        PackMeta storage meta = _packMeta[packId];
        if (!meta.exists) revert Registry_UnknownPack(packId);
        return (
            meta.active,
            meta.packType,
            meta.metadata,
            meta.slug,
            meta.version,
            _packPolicies[packId].length
        );
    }

    function policyCountOf(uint256 packId) external view returns (uint256) {
        if (!_packMeta[packId].exists) revert Registry_UnknownPack(packId);
        return _packPolicies[packId].length;
    }

    function getPackPolicies(uint256 packId) external view returns (address[] memory) {
        if (!_packMeta[packId].exists) revert Registry_UnknownPack(packId);
        return _packPolicies[packId];
    }

    function _assertPolicyMetadata(address policy) internal view {
        IPolicyIntrospection introspection = IPolicyIntrospection(policy);

        bytes32 key;
        try introspection.policyKey() returns (bytes32 policyKey_) {
            key = policyKey_;
        } catch {
            revert Registry_PolicyMissingMetadata(policy);
        }

        string memory name;
        try introspection.policyName() returns (string memory policyName_) {
            name = policyName_;
        } catch {
            revert Registry_PolicyMissingMetadata(policy);
        }

        string memory description;
        try introspection.policyDescription() returns (string memory policyDescription_) {
            description = policyDescription_;
        } catch {
            revert Registry_PolicyMissingMetadata(policy);
        }

        uint16 version;
        try introspection.policyConfigVersion() returns (uint16 v) {
            version = v;
        } catch {
            revert Registry_PolicyMissingMetadata(policy);
        }

        PolicyConfigEntry[] memory entries;
        try introspection.policyConfig() returns (PolicyConfigEntry[] memory cfg) {
            entries = cfg;
        } catch {
            revert Registry_PolicyMissingMetadata(policy);
        }

        if (
            key == bytes32(0) || bytes(name).length == 0 || bytes(description).length == 0 || version == 0
                || entries.length == 0
        ) {
            revert Registry_InvalidPolicyMetadata(policy);
        }

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].key == bytes32(0)) revert Registry_InvalidPolicyMetadata(policy);
        }
    }
}
