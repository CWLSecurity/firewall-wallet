// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision} from "../../src/interfaces/IFirewallPolicy.sol";
import {IFirewallPolicy} from "../../src/interfaces/IFirewallPolicy.sol";

contract MockPolicy is IFirewallPolicy {
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
}
