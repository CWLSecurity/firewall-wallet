// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

enum Decision {
    Allow,
    Delay,
    Revert
}

interface IFirewallPolicy {
    function evaluate(
        address vault,
        address to,
        uint256 value,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delaySeconds);
}

interface IFirewallPostExecPolicy {
    function onExecuted(
        address vault,
        address to,
        uint256 value,
        bytes calldata data
    ) external;
}
