// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy, IFirewallPostExecPolicy} from "./interfaces/IFirewallPolicy.sol";

error Router_ZeroPolicies();
error Router_InvalidPolicy(address policy);

// NEW
error Router_Unauthorized();
error Router_ZeroAddress();
error Router_FirewallAlreadySet();

contract PolicyRouter {
    IFirewallPolicy[] public policies;

    // NEW: owner = deployer (для one-time настройки)
    address public immutable owner;

    // NEW: кто имеет право дергать notifyExecuted
    address public firewallModule;

    // NEW: события для операционного контроля
    event FirewallModuleSet(address indexed firewallModule);
    event PostExecHookFailed(address indexed policy, bytes returndata);

    constructor(address owner_, address firewallModule_, address[] memory _policies) {
        if (owner_ == address(0)) revert Router_ZeroAddress();
        owner = owner_;
        if (firewallModule_ == address(0)) revert Router_ZeroAddress();
        firewallModule = firewallModule_;

        if (_policies.length == 0) revert Router_ZeroPolicies();

        for (uint256 i = 0; i < _policies.length; i++) {
            address p = _policies[i];
            if (p == address(0)) revert Router_InvalidPolicy(p);
            policies.push(IFirewallPolicy(p));
        }
    }

    function policyCount() external view returns (uint256) {
        return policies.length;
    }

    // NEW: one-time привязка модуля (legacy; not used when bound in constructor)
    function setFirewallModule(address _module) external {
        if (msg.sender != owner) revert Router_Unauthorized();
        if (_module == address(0)) revert Router_ZeroAddress();
        if (firewallModule != address(0)) revert Router_FirewallAlreadySet();

        firewallModule = _module;
        emit FirewallModuleSet(_module);
    }

    /// Главная функция — агрегирует решения всех политик
    function evaluate(
        address vault,
        address to,
        uint256 value,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delaySeconds) {
        Decision finalDecision = Decision.Allow;
        uint48 maxDelay = 0;

        uint256 len = policies.length;

        for (uint256 i = 0; i < len; i++) {
            (Decision d, uint48 ds) = policies[i].evaluate(vault, to, value, data);

            if (d == Decision.Revert) {
                return (Decision.Revert, 0);
            }

            if (d == Decision.Delay) {
                finalDecision = Decision.Delay;
                if (ds > maxDelay) {
                    maxDelay = ds;
                }
            }
        }

        return (finalDecision, maxDelay);
    }

    /// Уведомление политик после успешного выполнения транзакции
    /// Нужно для stateful-политик (NewReceiverDelay)
    function notifyExecuted(
        address vault,
        address to,
        uint256 value,
        bytes calldata data
    ) external {
        // NEW: запрет подделки post-exec
        if (msg.sender != firewallModule) revert Router_Unauthorized();

        uint256 len = policies.length;

        for (uint256 i = 0; i < len; i++) {
            address p = address(policies[i]);

            (bool ok, bytes memory ret) = p.call(
                abi.encodeWithSelector(
                    IFirewallPostExecPolicy.onExecuted.selector,
                    vault,
                    to,
                    value,
                    data
                )
            );

            // NEW: не ревертить, но логировать провал hook'а
            if (!ok) {
                emit PostExecHookFailed(p, ret);
            }
        }
    }
}
