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
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        address receiver = _receiverFromCall(to, data);
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
        address receiver = _receiverFromCall(to, data);
        knownReceivers[vault][receiver] = true;
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
                receiver := shr(96, calldataload(add(data.offset, 4)))
            }
            return receiver;
        }

        // transferFrom(address,address,uint256)
        if (sel == 0x23b872dd && data.length >= 100) {
            assembly {
                receiver := shr(96, calldataload(add(data.offset, 36)))
            }
            return receiver;
        }
    }
}
