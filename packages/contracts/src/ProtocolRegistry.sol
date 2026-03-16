// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IProtocolRegistry} from "./interfaces/IProtocolRegistry.sol";

error ProtocolRegistry_Unauthorized();
error ProtocolRegistry_ZeroAddress();
error ProtocolRegistry_InvalidProtocolId();
error ProtocolRegistry_ProtocolExists(bytes32 protocolId);
error ProtocolRegistry_UnknownProtocol(bytes32 protocolId);
error ProtocolRegistry_ProtocolVersionZero();
error ProtocolRegistry_TargetAlreadyMapped(address target, bytes32 protocolId);
error ProtocolRegistry_TargetUnmapped(address target);

contract ProtocolRegistry is IProtocolRegistry {
    address public owner;

    struct ProtocolMeta {
        bool exists;
        bool active;
        string slug;
        uint16 version;
        bytes32 metadata;
    }

    mapping(bytes32 => ProtocolMeta) internal _protocolMeta;
    bytes32[] internal _protocolIds;

    mapping(bytes32 => address[]) internal _protocolTargets;
    mapping(bytes32 => mapping(address => uint256)) internal _protocolTargetIndexPlusOne;
    mapping(address => bytes32) public protocolOf;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ProtocolRegistered(
        bytes32 indexed protocolId,
        bool active,
        string slug,
        uint16 version,
        bytes32 metadata
    );
    event ProtocolStatusSet(bytes32 indexed protocolId, bool active);
    event ProtocolMetadataSet(bytes32 indexed protocolId, string slug, uint16 version, bytes32 metadata);
    event ProtocolTargetSet(bytes32 indexed protocolId, address indexed target, bool indexed assigned);

    constructor(address owner_) {
        if (owner_ == address(0)) revert ProtocolRegistry_ZeroAddress();
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert ProtocolRegistry_Unauthorized();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ProtocolRegistry_ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function registerProtocol(
        bytes32 protocolId,
        bool active,
        string calldata slug,
        uint16 version,
        bytes32 metadata
    ) external onlyOwner {
        if (protocolId == bytes32(0)) revert ProtocolRegistry_InvalidProtocolId();
        if (_protocolMeta[protocolId].exists) revert ProtocolRegistry_ProtocolExists(protocolId);
        if (version == 0) revert ProtocolRegistry_ProtocolVersionZero();

        _protocolMeta[protocolId] = ProtocolMeta({
            exists: true,
            active: active,
            slug: slug,
            version: version,
            metadata: metadata
        });
        _protocolIds.push(protocolId);
        emit ProtocolRegistered(protocolId, active, slug, version, metadata);
    }

    function setProtocolActive(bytes32 protocolId, bool active) external onlyOwner {
        ProtocolMeta storage meta = _protocolMeta[protocolId];
        if (!meta.exists) revert ProtocolRegistry_UnknownProtocol(protocolId);
        meta.active = active;
        emit ProtocolStatusSet(protocolId, active);
    }

    function setProtocolMetadata(bytes32 protocolId, string calldata slug, uint16 version, bytes32 metadata)
        external
        onlyOwner
    {
        ProtocolMeta storage meta = _protocolMeta[protocolId];
        if (!meta.exists) revert ProtocolRegistry_UnknownProtocol(protocolId);
        if (version == 0) revert ProtocolRegistry_ProtocolVersionZero();
        meta.slug = slug;
        meta.version = version;
        meta.metadata = metadata;
        emit ProtocolMetadataSet(protocolId, slug, version, metadata);
    }

    function setProtocolTarget(bytes32 protocolId, address target, bool assigned) external onlyOwner {
        if (target == address(0)) revert ProtocolRegistry_ZeroAddress();
        ProtocolMeta storage meta = _protocolMeta[protocolId];
        if (!meta.exists) revert ProtocolRegistry_UnknownProtocol(protocolId);

        if (assigned) {
            bytes32 current = protocolOf[target];
            if (current != bytes32(0) && current != protocolId) {
                revert ProtocolRegistry_TargetAlreadyMapped(target, current);
            }
            if (_protocolTargetIndexPlusOne[protocolId][target] == 0) {
                _protocolTargets[protocolId].push(target);
                _protocolTargetIndexPlusOne[protocolId][target] = _protocolTargets[protocolId].length;
            }
            protocolOf[target] = protocolId;
            emit ProtocolTargetSet(protocolId, target, true);
            return;
        }

        bytes32 mapped = protocolOf[target];
        if (mapped != protocolId) revert ProtocolRegistry_TargetUnmapped(target);
        _removeProtocolTarget(protocolId, target);
        delete protocolOf[target];
        emit ProtocolTargetSet(protocolId, target, false);
    }

    function resolveProtocol(address target) external view returns (bytes32 protocolId, bool active) {
        protocolId = protocolOf[target];
        if (protocolId == bytes32(0)) return (bytes32(0), false);
        active = _protocolMeta[protocolId].active;
    }

    function protocolCount() external view returns (uint256) {
        return _protocolIds.length;
    }

    function protocolIdAt(uint256 index) external view returns (bytes32) {
        return _protocolIds[index];
    }

    function getProtocolMeta(bytes32 protocolId)
        external
        view
        returns (bool active, string memory slug, uint16 version, bytes32 metadata, uint256 targetCount)
    {
        ProtocolMeta storage meta = _protocolMeta[protocolId];
        if (!meta.exists) revert ProtocolRegistry_UnknownProtocol(protocolId);
        return (meta.active, meta.slug, meta.version, meta.metadata, _protocolTargets[protocolId].length);
    }

    function protocolTargetCount(bytes32 protocolId) external view returns (uint256) {
        if (!_protocolMeta[protocolId].exists) revert ProtocolRegistry_UnknownProtocol(protocolId);
        return _protocolTargets[protocolId].length;
    }

    function protocolTargetAt(bytes32 protocolId, uint256 index) external view returns (address) {
        if (!_protocolMeta[protocolId].exists) revert ProtocolRegistry_UnknownProtocol(protocolId);
        return _protocolTargets[protocolId][index];
    }

    function _removeProtocolTarget(bytes32 protocolId, address target) internal {
        uint256 indexPlusOne = _protocolTargetIndexPlusOne[protocolId][target];
        if (indexPlusOne == 0) revert ProtocolRegistry_TargetUnmapped(target);
        uint256 index = indexPlusOne - 1;

        address[] storage targets = _protocolTargets[protocolId];
        uint256 lastIndex = targets.length - 1;
        if (index != lastIndex) {
            address moved = targets[lastIndex];
            targets[index] = moved;
            _protocolTargetIndexPlusOne[protocolId][moved] = index + 1;
        }
        targets.pop();
        delete _protocolTargetIndexPlusOne[protocolId][target];
    }
}
