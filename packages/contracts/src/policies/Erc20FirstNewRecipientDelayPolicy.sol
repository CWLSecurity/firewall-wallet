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

error Erc20FirstNewRecipientDelay_UnauthorizedHookCaller();

/// @notice Delays first ERC20 transfer/transferFrom recipient per vault.
///         Non-transfer selectors are ignored.
///         Known recipient state is scoped by (vault, token, recipient) to prevent cross-token priming.
contract Erc20FirstNewRecipientDelayPolicy is
    IFirewallPolicy,
    IFirewallPostExecPolicy,
    IPolicyIntrospection
{
    bytes4 internal constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes4 internal constant TRANSFER_FROM_SELECTOR = 0x23b872dd;

    uint48 public immutable DELAY_SECONDS;
    // vault => token => recipient => known
    mapping(address => mapping(address => mapping(address => bool))) public knownRecipients;

    constructor(uint48 delaySeconds_) {
        DELAY_SECONDS = delaySeconds_;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("erc20-first-new-recipient-delay-v1");
    }

    function policyName() external pure returns (string memory) {
        return "Erc20FirstNewRecipientDelayPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Delays first ERC20 transfer/transferFrom recipient per (vault, token).";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](4);
        entries[0] = PolicyConfigEntry({
            key: bytes32("delay_seconds"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(DELAY_SECONDS)),
            unit: bytes32("seconds")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("known_scope"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("vault_token_rcpt"),
            unit: bytes32("mode")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("selector_scope"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("transfer+from"),
            unit: bytes32("mode")
        });
        entries[3] = PolicyConfigEntry({
            key: bytes32("first_recipient_action"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("delay"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address vault,
        address token,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        (bool matched, address recipient) = _parseRecipient(data);
        if (!matched) {
            return (Decision.Allow, 0);
        }

        if (knownRecipients[vault][token][recipient]) {
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

        (bool matched, address recipient) = _parseRecipient(data);
        if (!matched) return;
        knownRecipients[vault][token][recipient] = true;
    }

    function _parseRecipient(bytes calldata data) internal pure returns (bool matched, address recipient) {
        if (data.length < 4) return (false, address(0));

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        // transfer(address,uint256)
        if (sel == TRANSFER_SELECTOR) {
            if (data.length < 68) return (false, address(0));
            assembly {
                recipient := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, recipient);
        }

        // transferFrom(address,address,uint256)
        if (sel == TRANSFER_FROM_SELECTOR) {
            if (data.length < 100) return (false, address(0));
            assembly {
                recipient := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, recipient);
        }

        return (false, address(0));
    }

    function _assertTrustedHookCaller(address vault) internal view {
        if (msg.sender != IFirewallModuleView(vault).router()) {
            revert Erc20FirstNewRecipientDelay_UnauthorizedHookCaller();
        }
    }
}
