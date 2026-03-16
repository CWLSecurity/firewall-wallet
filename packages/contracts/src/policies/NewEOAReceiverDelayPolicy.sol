// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    Decision,
    IFirewallPolicy,
    IFirewallPostExecPolicy
} from "../interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../interfaces/IPolicyIntrospection.sol";
import {IFirewallModuleView} from "../interfaces/IFirewallModuleView.sol";

error ReceiverDelay_UnauthorizedHookCaller();

/// @notice Delay first transfer to a new EOA receiver.
///         Calls to contracts are allowed immediately.
contract NewEOAReceiverDelayPolicy is IFirewallPolicy, IFirewallPostExecPolicy, IPolicyIntrospection {
    uint48 public immutable DELAY_SECONDS;
    bool public constant EOA_ONLY = true;

    // vault => receiver => known
    mapping(address => mapping(address => bool)) public knownReceivers;

    constructor(uint48 _delaySeconds) {
        DELAY_SECONDS = _delaySeconds;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("new-eoa-receiver-delay-v1");
    }

    function policyName() external pure returns (string memory) {
        return "NewEOAReceiverDelayPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Delays first transfer to a new EOA receiver; contract receivers are allowed immediately.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](3);
        entries[0] = PolicyConfigEntry({
            key: bytes32("delay_seconds"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(DELAY_SECONDS)),
            unit: bytes32("seconds")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("eoa_only"),
            valueType: PolicyConfigValueType.Bool,
            value: _boolToBytes32(EOA_ONLY),
            unit: bytes32("bool")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("receiver_scope"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("eoa_receivers"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address vault,
        address to,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        address receiver = _receiverFromCall(to, data);

        // Only first-time EOA receivers are delayed.
        if (receiver.code.length > 0) {
            return (Decision.Allow, 0);
        }

        if (knownReceivers[vault][receiver]) {
            return (Decision.Allow, 0);
        }

        return (Decision.Delay, DELAY_SECONDS);
    }

    /// @notice Called by Router after successful execution
    function onExecuted(
        address vault,
        address to,
        uint256,
        bytes calldata data
    ) external {
        _assertTrustedHookCaller(vault);
        address receiver = _receiverFromCall(to, data);
        if (receiver.code.length == 0) {
            knownReceivers[vault][receiver] = true;
        }
    }

    function _receiverFromCall(address to, bytes calldata data) internal pure returns (address receiver) {
        receiver = to;
        if (data.length < 4) return receiver;

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        // transfer(address,uint256)
        if (sel == 0xa9059cbb && data.length >= 68) {
            assembly {
                receiver := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return receiver;
        }

        // transferFrom(address,address,uint256)
        if (sel == 0x23b872dd && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return receiver;
        }
    }

    function _assertTrustedHookCaller(address vault) internal view {
        if (msg.sender != IFirewallModuleView(vault).router()) {
            revert ReceiverDelay_UnauthorizedHookCaller();
        }
    }

    function _boolToBytes32(bool value) internal pure returns (bytes32) {
        return value ? bytes32(uint256(1)) : bytes32(0);
    }
}
