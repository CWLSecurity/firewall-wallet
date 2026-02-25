// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    Decision,
    IFirewallPolicy,
    IFirewallPostExecPolicy
} from "../interfaces/IFirewallPolicy.sol";

/// @notice Delay transfers to new receivers.
///         First time → Delay
///         After successful execution → receiver becomes known.
contract NewReceiverDelayPolicy is IFirewallPolicy, IFirewallPostExecPolicy {
    uint48 public immutable DELAY_SECONDS;

    // vault => receiver => known
    mapping(address => mapping(address => bool)) public knownReceivers;

    constructor(uint48 _delaySeconds) {
        DELAY_SECONDS = _delaySeconds;
    }

    function evaluate(
        address vault,
        address to,
        uint256,
        bytes calldata
    ) external view returns (Decision decision, uint48 delayOut) {
        if (knownReceivers[vault][to]) {
            return (Decision.Allow, 0);
        }

        return (Decision.Delay, DELAY_SECONDS);
    }

    /// @notice Called by Router after successful execution
    function onExecuted(
        address vault,
        address to,
        uint256,
        bytes calldata
    ) external {
        knownReceivers[vault][to] = true;
    }
}
