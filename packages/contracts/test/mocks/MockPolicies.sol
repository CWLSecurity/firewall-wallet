// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {IFirewallPolicy} from "../../src/interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../../src/interfaces/IPolicyIntrospection.sol";

contract MockPolicy is IFirewallPolicy, IPolicyIntrospection {
    Decision public nextDecision;
    uint48 public nextDelay;

    constructor(Decision d, uint48 delaySeconds) {
        nextDecision = d;
        nextDelay = delaySeconds;
    }

    function set(Decision d, uint48 delaySeconds) external {
        nextDecision = d;
        nextDelay = delaySeconds;
    }

    function evaluate(address to, address caller, uint256 value, bytes calldata data)
        external
        view
        returns (Decision decision, uint48 delaySeconds)
    {
        to; caller; value; data;
        return (nextDecision, nextDelay);
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("mock-policy-v1");
    }

    function policyName() external pure returns (string memory) {
        return "MockPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Test helper policy for router/registry/unit tests.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](2);
        entries[0] = PolicyConfigEntry({
            key: bytes32("mock_decision"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(uint8(nextDecision))),
            unit: bytes32("enum")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("mock_delay_seconds"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(nextDelay)),
            unit: bytes32("seconds")
        });
    }
}
