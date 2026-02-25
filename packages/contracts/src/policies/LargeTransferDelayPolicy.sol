// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";

/// @notice If native value > threshold => Delay for delaySeconds.
///         MVP: only checks `value` (ETH), no ERC20 parsing yet.
///         Stateless.
contract LargeTransferDelayPolicy is IFirewallPolicy {
    uint256 public immutable THRESHOLD_WEI;
    uint48 public immutable DELAY_SECONDS;

    constructor(uint256 _thresholdWei, uint48 _delaySeconds) {
        THRESHOLD_WEI = _thresholdWei;
        DELAY_SECONDS = _delaySeconds;
    }

    function evaluate(
        address,
        address,
        uint256 value,
        bytes calldata
    ) external view returns (Decision decision, uint48 delayOut) {
        if (value > THRESHOLD_WEI) {
            return (Decision.Delay, DELAY_SECONDS);
        }

        return (Decision.Allow, 0);
    }
}
