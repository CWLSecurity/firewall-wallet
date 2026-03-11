// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPolicyPackRegistry} from "./interfaces/IPolicyPackRegistry.sol";

error Registry_Unauthorized();
error Registry_ZeroAddress();
error Registry_UnknownPack(uint256 packId);
error Registry_PackExists(uint256 packId);
error Registry_ZeroPolicies();
error Registry_InvalidPolicy(address policy);
error Registry_InvalidPackType(uint8 packType);

contract PolicyPackRegistry is IPolicyPackRegistry {
    uint8 public constant PACK_TYPE_BASE = 0;
    uint8 public constant PACK_TYPE_ADDON = 1;

    address public owner;

    struct PackMeta {
        bool exists;
        bool active;
        uint8 packType;
        bytes32 metadata;
    }

    mapping(uint256 => PackMeta) internal _packMeta;
    mapping(uint256 => address[]) internal _packPolicies;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PackRegistered(
        uint256 indexed packId, uint8 indexed packType, bool active, bytes32 metadata
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
        if (packType != PACK_TYPE_BASE && packType != PACK_TYPE_ADDON) {
            revert Registry_InvalidPackType(packType);
        }
        if (_packMeta[packId].exists) revert Registry_PackExists(packId);

        uint256 len = policies.length;
        if (len == 0) revert Registry_ZeroPolicies();

        for (uint256 i = 0; i < len; i++) {
            address policy = policies[i];
            if (policy == address(0)) revert Registry_InvalidPolicy(policy);
            _packPolicies[packId].push(policy);
        }

        _packMeta[packId] =
            PackMeta({exists: true, active: active, packType: packType, metadata: metadata});

        emit PackRegistered(packId, packType, active, metadata);
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

    function policyCountOf(uint256 packId) external view returns (uint256) {
        if (!_packMeta[packId].exists) revert Registry_UnknownPack(packId);
        return _packPolicies[packId].length;
    }

    function getPackPolicies(uint256 packId) external view returns (address[] memory) {
        if (!_packMeta[packId].exists) revert Registry_UnknownPack(packId);
        return _packPolicies[packId];
    }
}
