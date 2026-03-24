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
///         Unknown-selector calls to new contract targets are also delayed once.
contract NewEOAReceiverDelayPolicy is IFirewallPolicy, IFirewallPostExecPolicy, IPolicyIntrospection {
    bytes4 internal constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes4 internal constant TRANSFER_FROM_SELECTOR = 0x23b872dd;
    bytes4 internal constant SAFE_TRANSFER_FROM_ERC721_SELECTOR = 0x42842e0e;
    bytes4 internal constant SAFE_TRANSFER_FROM_ERC721_WITH_DATA_SELECTOR = 0xb88d4fde;
    bytes4 internal constant SAFE_TRANSFER_FROM_ERC1155_SELECTOR = 0xf242432a;
    bytes4 internal constant SAFE_BATCH_TRANSFER_FROM_ERC1155_SELECTOR = 0x2eb2c2d6;

    bytes4 internal constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;
    bytes4 internal constant SET_APPROVAL_FOR_ALL_SELECTOR = 0xa22cb465;
    bytes4 internal constant PERMIT_EIP2612_SELECTOR = 0xd505accf;
    bytes4 internal constant PERMIT_DAI_SELECTOR = 0x8fcbaf0c;
    bytes4 internal constant PERMIT2_SINGLE_SELECTOR = 0x2b67b570;
    bytes4 internal constant PERMIT2_BATCH_SELECTOR = 0x2a2d80d1;
    bytes4 internal constant PERMIT2_TRANSFER_FROM_SELECTOR = 0x6949bce4;
    bytes4 internal constant PERMIT2_WITNESS_TRANSFER_FROM_SELECTOR = 0x2eda8726;

    uint48 public immutable DELAY_SECONDS;
    bool public constant EOA_ONLY = true;

    // vault => eoa receiver => known
    mapping(address => mapping(address => bool)) public knownReceivers;
    // vault => contract target => known (unknown-selector first-call hardening)
    mapping(address => mapping(address => bool)) public knownContractTargets;

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
        return
            "Delays first transfer to a new EOA receiver and delays first unknown-selector call to a new contract target.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 2;
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
        entries[3] = PolicyConfigEntry({
            key: bytes32("unknown_contract_selector_action"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("delay_first_call"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address vault,
        address to,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        (address receiver, bool parsedTransferSelector, bool approvalLike, bool hasSelector) =
            _receiverFromCall(to, data);

        // Receiver-aware transfer selectors: delay first new EOA receiver only.
        if (parsedTransferSelector) {
            if (receiver.code.length > 0) {
                return (Decision.Allow, 0);
            }
            if (knownReceivers[vault][receiver]) {
                return (Decision.Allow, 0);
            }
            return (Decision.Delay, DELAY_SECONDS);
        }

        // Approval-like selectors are governed by approval-focused policies.
        if (approvalLike) {
            return (Decision.Allow, 0);
        }

        // Native/plain transfer path (no selector): preserve classic "new EOA delay".
        if (!hasSelector) {
            if (to.code.length > 0) {
                return (Decision.Allow, 0);
            }
            if (knownReceivers[vault][to]) {
                return (Decision.Allow, 0);
            }
            return (Decision.Delay, DELAY_SECONDS);
        }

        // Unknown selector to EOA remains out of scope.
        if (to.code.length == 0) {
            return (Decision.Allow, 0);
        }

        // Unknown selector to a new contract target gets delayed once.
        if (knownContractTargets[vault][to]) {
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

        (address receiver, bool parsedTransferSelector, bool approvalLike, bool hasSelector) =
            _receiverFromCall(to, data);

        if (parsedTransferSelector) {
            if (receiver.code.length == 0) {
                knownReceivers[vault][receiver] = true;
            }
            return;
        }

        if (!hasSelector) {
            if (to.code.length == 0) {
                knownReceivers[vault][to] = true;
            }
            return;
        }

        if (!approvalLike && to.code.length > 0) {
            knownContractTargets[vault][to] = true;
        }
    }

    function _receiverFromCall(address to, bytes calldata data)
        internal
        pure
        returns (address receiver, bool parsedTransferSelector, bool approvalLike, bool hasSelector)
    {
        receiver = to;
        parsedTransferSelector = false;
        approvalLike = false;
        hasSelector = data.length >= 4;
        if (!hasSelector) {
            return (receiver, parsedTransferSelector, approvalLike, hasSelector);
        }

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        if (_isApprovalLikeSelector(sel)) {
            return (receiver, false, true, true);
        }

        // ERC20 transfer(address,uint256)
        if (sel == TRANSFER_SELECTOR && data.length >= 68) {
            assembly {
                receiver := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true);
        }

        // ERC20 transferFrom(address,address,uint256)
        // ERC721 transferFrom(address,address,uint256)
        if (sel == TRANSFER_FROM_SELECTOR && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true);
        }

        // ERC721 safeTransferFrom(address,address,uint256)
        if (sel == SAFE_TRANSFER_FROM_ERC721_SELECTOR && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true);
        }

        // ERC721 safeTransferFrom(address,address,uint256,bytes)
        if (sel == SAFE_TRANSFER_FROM_ERC721_WITH_DATA_SELECTOR && data.length >= 132) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true);
        }

        // ERC1155 safeTransferFrom(address,address,uint256,uint256,bytes)
        if (sel == SAFE_TRANSFER_FROM_ERC1155_SELECTOR && data.length >= 164) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true);
        }

        // ERC1155 safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)
        if (sel == SAFE_BATCH_TRANSFER_FROM_ERC1155_SELECTOR && data.length >= 164) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true);
        }

        return (receiver, false, false, true);
    }

    function _isApprovalLikeSelector(bytes4 sel) internal pure returns (bool) {
        return sel == APPROVE_SELECTOR || sel == INCREASE_ALLOWANCE_SELECTOR
            || sel == SET_APPROVAL_FOR_ALL_SELECTOR || sel == PERMIT_EIP2612_SELECTOR
            || sel == PERMIT_DAI_SELECTOR || sel == PERMIT2_SINGLE_SELECTOR
            || sel == PERMIT2_BATCH_SELECTOR || sel == PERMIT2_TRANSFER_FROM_SELECTOR
            || sel == PERMIT2_WITNESS_TRANSFER_FROM_SELECTOR;
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
