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

error ApprovalToNewSpenderDelay_UnauthorizedHookCaller();

/// @notice DeFi-oriented approval guard:
///         - approve/increaseAllowance with zero amount: allow
///         - non-zero approval to EOA spender: revert
///         - non-zero approval to new contract spender: delay
///         - non-zero approval to known contract spender: allow
///         - known state is scoped by (vault, token, spender) to prevent cross-token priming
///         Supports parseable permit-like selectors: EIP-2612, DAI-style permit,
///         and Permit2 approve(token, spender, amount, expiration).
contract ApprovalToNewSpenderDelayPolicy is
    IFirewallPolicy,
    IFirewallPostExecPolicy,
    IPolicyIntrospection
{
    bytes4 internal constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;
    bytes4 internal constant PERMIT_EIP2612_SELECTOR = 0xd505accf;
    bytes4 internal constant PERMIT_DAI_SELECTOR = 0x8fcbaf0c;
    bytes4 internal constant PERMIT2_APPROVE_SELECTOR = 0x87517c45;

    uint48 public immutable DELAY_SECONDS;
    // vault => token => spender => known
    mapping(address => mapping(address => mapping(address => bool))) public knownSpenders;

    constructor(uint48 delaySeconds_) {
        DELAY_SECONDS = delaySeconds_;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("approval-to-new-spender-delay-v1");
    }

    function policyName() external pure returns (string memory) {
        return "ApprovalToNewSpenderDelayPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Delays first non-zero approvals to new contract spenders; reverts non-zero approvals to EOAs.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 2;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](5);
        entries[0] = PolicyConfigEntry({
            key: bytes32("delay_seconds"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(DELAY_SECONDS)),
            unit: bytes32("seconds")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("known_scope"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("vault_token_spender"),
            unit: bytes32("mode")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("eoa_nonzero_action"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("revert"),
            unit: bytes32("mode")
        });
        entries[3] = PolicyConfigEntry({
            key: bytes32("new_contract_action"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("delay"),
            unit: bytes32("mode")
        });
        entries[4] = PolicyConfigEntry({
            key: bytes32("permit2_approve_supported"),
            valueType: PolicyConfigValueType.Bool,
            value: _boolToBytes32(true),
            unit: bytes32("bool")
        });
    }

    function evaluate(
        address vault,
        address token,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        (bool matched, address spender, bool isNonZeroApproval, address parsedTokenScope) = _parseApproval(data);
        if (!matched || !isNonZeroApproval) {
            return (Decision.Allow, 0);
        }

        address tokenScope = parsedTokenScope == address(0) ? token : parsedTokenScope;

        if (spender.code.length == 0) {
            return (Decision.Revert, 0);
        }

        if (knownSpenders[vault][tokenScope][spender]) {
            return (Decision.Allow, 0);
        }

        return (Decision.Delay, DELAY_SECONDS);
    }

    function onExecuted(
        address vault,
        address token,
        uint256,
        bytes calldata data
    ) external {
        _assertTrustedHookCaller(vault);

        (bool matched, address spender, bool isNonZeroApproval, address parsedTokenScope) = _parseApproval(data);
        if (!matched || !isNonZeroApproval) return;
        if (spender.code.length == 0) return;

        address tokenScope = parsedTokenScope == address(0) ? token : parsedTokenScope;
        knownSpenders[vault][tokenScope][spender] = true;
    }

    function _parseApproval(bytes calldata data)
        internal
        pure
        returns (bool matched, address spender, bool isNonZeroApproval, address tokenScope)
    {
        if (data.length < 4) return (false, address(0), false, address(0));

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        // approve(address spender, uint256 amount)
        if (sel == APPROVE_SELECTOR) {
            if (data.length < 68) return (false, address(0), false, address(0));
            uint256 amount;
            assembly {
                spender := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
                amount := calldataload(add(data.offset, 36))
            }
            return (true, spender, amount != 0, address(0));
        }

        // increaseAllowance(address spender, uint256 addedValue)
        if (sel == INCREASE_ALLOWANCE_SELECTOR) {
            if (data.length < 68) return (false, address(0), false, address(0));
            uint256 added;
            assembly {
                spender := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
                added := calldataload(add(data.offset, 36))
            }
            return (true, spender, added != 0, address(0));
        }

        // permit(address owner, address spender, uint256 value, ...)
        if (sel == PERMIT_EIP2612_SELECTOR) {
            if (data.length < 228) return (false, address(0), false, address(0));
            uint256 value;
            assembly {
                spender := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
                value := calldataload(add(data.offset, 68))
            }
            return (true, spender, value != 0, address(0));
        }

        // permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, ...)
        if (sel == PERMIT_DAI_SELECTOR) {
            if (data.length < 260) return (false, address(0), false, address(0));
            uint256 allowed;
            assembly {
                spender := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
                allowed := calldataload(add(data.offset, 132))
            }
            return (true, spender, allowed != 0, address(0));
        }

        // Permit2 approve(address token, address spender, uint160 amount, uint48 expiration)
        if (sel == PERMIT2_APPROVE_SELECTOR) {
            if (data.length < 132) return (false, address(0), false, address(0));
            uint256 amount;
            assembly {
                tokenScope := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
                spender := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
                amount := calldataload(add(data.offset, 68))
            }
            return (true, spender, amount != 0, tokenScope);
        }

        return (false, address(0), false, address(0));
    }

    function _boolToBytes32(bool value) internal pure returns (bytes32) {
        return value ? bytes32(uint256(1)) : bytes32(0);
    }

    function _assertTrustedHookCaller(address vault) internal view {
        if (msg.sender != IFirewallModuleView(vault).router()) {
            revert ApprovalToNewSpenderDelay_UnauthorizedHookCaller();
        }
    }
}
