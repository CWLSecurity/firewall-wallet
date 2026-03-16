// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

enum PolicyConfigValueType {
    Uint256,
    Bool,
    Address,
    Bytes32
}

struct PolicyConfigEntry {
    bytes32 key;
    PolicyConfigValueType valueType;
    bytes32 value;
    bytes32 unit;
}

/// @notice Required policy metadata contract for registry/router admission.
///         Every admitted policy must expose:
///         - stable policy identity (`policyKey`, `policyName`)
///         - short human-readable description (`policyDescription`)
///         - structured machine-readable config snapshot (`policyConfigVersion`, `policyConfig`)
interface IPolicyIntrospection {
    function policyKey() external pure returns (bytes32);
    function policyName() external pure returns (string memory);
    function policyDescription() external pure returns (string memory);
    function policyConfigVersion() external pure returns (uint16);
    function policyConfig() external view returns (PolicyConfigEntry[] memory entries);
}
