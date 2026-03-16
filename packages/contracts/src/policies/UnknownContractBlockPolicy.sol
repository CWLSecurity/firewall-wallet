// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../interfaces/IPolicyIntrospection.sol";

error UnknownContract_Unauthorized();
error UnknownContract_ZeroAddress();

contract UnknownContractBlockPolicy is IFirewallPolicy, IPolicyIntrospection {
    address public immutable owner;

    /// @notice Global allowlist: target contract -> allowed
    mapping(address => bool) public allowed;

    event AllowedSet(address indexed target, bool allowed);

    constructor(address owner_) {
        if (owner_ == address(0)) revert UnknownContract_ZeroAddress();
        owner = owner_;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("unknown-contract-block-v1");
    }

    function policyName() external pure returns (string memory) {
        return "UnknownContractBlockPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Reverts calls to non-allowlisted contracts; EOAs are always allowed.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](4);
        entries[0] = PolicyConfigEntry({
            key: bytes32("owner"),
            valueType: PolicyConfigValueType.Address,
            value: bytes32(uint256(uint160(owner))),
            unit: bytes32("address")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("eoa_allowed"),
            valueType: PolicyConfigValueType.Bool,
            value: bytes32(uint256(1)),
            unit: bytes32("bool")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("unknown_contract_action"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("revert"),
            unit: bytes32("mode")
        });
        entries[3] = PolicyConfigEntry({
            key: bytes32("allowlist_reconstruct"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("events_required"),
            unit: bytes32("mode")
        });
    }

    function setAllowed(address target, bool isAllowed) external {
        if (msg.sender != owner) revert UnknownContract_Unauthorized();
        if (target == address(0)) revert UnknownContract_ZeroAddress();
        allowed[target] = isAllowed;
        emit AllowedSet(target, isAllowed);
    }

    function setAllowedBatch(address[] calldata targets, bool isAllowed) external {
        if (msg.sender != owner) revert UnknownContract_Unauthorized();
        uint256 len = targets.length;
        for (uint256 i = 0; i < len; i++) {
            address t = targets[i];
            if (t == address(0)) revert UnknownContract_ZeroAddress();
            allowed[t] = isAllowed;
            emit AllowedSet(t, isAllowed);
        }
    }

    /// @notice Blocks calls to unknown contracts. EOAs are always allowed.
    function evaluate(
        address, // vault (unused in MVP)
        address to,
        uint256, // value (unused)
        bytes calldata // data (unused)
    ) external view returns (Decision decision, uint48 delaySeconds) {
        // If target has code => it is a contract. Must be allowlisted.
        if (to.code.length > 0 && !allowed[to]) {
            return (Decision.Revert, 0);
        }
        return (Decision.Allow, 0);
    }
}
