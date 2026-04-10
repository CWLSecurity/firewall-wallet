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
///         Unknown-selector calls are delayed for first-time EOA targets and
///         first-time (contract target, selector) pairs.
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
    bytes4 internal constant PERMIT2_APPROVE_SELECTOR = 0x87517c45;
    bytes4 internal constant PERMIT2_SINGLE_SELECTOR = 0x2b67b570;
    bytes4 internal constant PERMIT2_BATCH_SELECTOR = 0x2a2d80d1;
    bytes4 internal constant PERMIT2_TRANSFER_FROM_SELECTOR = 0x6949bce4;
    bytes4 internal constant PERMIT2_WITNESS_TRANSFER_FROM_SELECTOR = 0x2eda8726;

    uint48 public immutable DELAY_SECONDS;
    bool public constant EOA_ONLY = true;

    // vault => eoa receiver => known
    mapping(address => mapping(address => bool)) public knownReceivers;
    // Legacy coarse-grained marker retained for backwards compatibility in reads.
    // vault => contract target => seen
    mapping(address => mapping(address => bool)) public knownContractTargets;
    // vault => contract target => selector => known (unknown-selector first-call hardening)
    mapping(address => mapping(address => mapping(bytes4 => bool))) public knownContractTargetSelectors;
    // vault => contract target => selector => code fingerprint snapshotted at first successful execution
    mapping(address => mapping(address => mapping(bytes4 => bytes32))) public knownContractTargetSelectorCodehash;

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
            "Delays first transfer to a new EOA receiver and delays first unknown-selector call per target+selector with codehash revalidation.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 4;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](7);
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
        entries[4] = PolicyConfigEntry({
            key: bytes32("unknown_contract_selector_scope"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("target+selector"),
            unit: bytes32("mode")
        });
        entries[5] = PolicyConfigEntry({
            key: bytes32("unknown_eoa_selector_action"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("delay_first_call"),
            unit: bytes32("mode")
        });
        entries[6] = PolicyConfigEntry({
            key: bytes32("unknown_contract_revalidate"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("codehash+implhash"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address vault,
        address to,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        (address receiver, bool parsedTransferSelector, bool approvalLike, bool hasSelector, bytes4 selector) =
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

        // Any call path to EOA preserves "first new EOA delay" semantics.
        if (to.code.length == 0) {
            if (knownReceivers[vault][to]) {
                return (Decision.Allow, 0);
            }
            return (Decision.Delay, DELAY_SECONDS);
        }

        // No-selector calls to contracts are out of scope for this policy family.
        if (!hasSelector) {
            return (Decision.Allow, 0);
        }

        // Unknown selector is trusted only while contract codehash stays unchanged.
        if (
            knownContractTargetSelectors[vault][to][selector]
                && knownContractTargetSelectorCodehash[vault][to][selector] == _targetFingerprint(to)
        ) {
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

        (address receiver, bool parsedTransferSelector, bool approvalLike, bool hasSelector, bytes4 selector) =
            _receiverFromCall(to, data);

        if (parsedTransferSelector) {
            if (receiver.code.length == 0) {
                knownReceivers[vault][receiver] = true;
            }
            return;
        }

        if (to.code.length == 0) {
            knownReceivers[vault][to] = true;
            return;
        }

        if (!approvalLike && hasSelector) {
            knownContractTargets[vault][to] = true;
            knownContractTargetSelectors[vault][to][selector] = true;
            knownContractTargetSelectorCodehash[vault][to][selector] = _targetFingerprint(to);
        }
    }

    function _receiverFromCall(address to, bytes calldata data)
        internal
        pure
        returns (address receiver, bool parsedTransferSelector, bool approvalLike, bool hasSelector, bytes4 selector)
    {
        receiver = to;
        parsedTransferSelector = false;
        approvalLike = false;
        hasSelector = data.length >= 4;
        selector = bytes4(0);
        if (!hasSelector) {
            return (receiver, parsedTransferSelector, approvalLike, hasSelector, selector);
        }

        assembly {
            selector := calldataload(data.offset)
        }

        if (_isApprovalLikeSelector(selector)) {
            return (receiver, false, true, true, selector);
        }

        // ERC20 transfer(address,uint256)
        if (selector == TRANSFER_SELECTOR && data.length >= 68) {
            assembly {
                receiver := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true, selector);
        }

        // ERC20 transferFrom(address,address,uint256)
        // ERC721 transferFrom(address,address,uint256)
        if (selector == TRANSFER_FROM_SELECTOR && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true, selector);
        }

        // ERC721 safeTransferFrom(address,address,uint256)
        if (selector == SAFE_TRANSFER_FROM_ERC721_SELECTOR && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true, selector);
        }

        // ERC721 safeTransferFrom(address,address,uint256,bytes)
        if (selector == SAFE_TRANSFER_FROM_ERC721_WITH_DATA_SELECTOR && data.length >= 132) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true, selector);
        }

        // ERC1155 safeTransferFrom(address,address,uint256,uint256,bytes)
        if (selector == SAFE_TRANSFER_FROM_ERC1155_SELECTOR && data.length >= 164) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true, selector);
        }

        // ERC1155 safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)
        if (selector == SAFE_BATCH_TRANSFER_FROM_ERC1155_SELECTOR && data.length >= 164) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (receiver, true, false, true, selector);
        }

        return (receiver, false, false, true, selector);
    }

    function _isApprovalLikeSelector(bytes4 sel) internal pure returns (bool) {
        return sel == APPROVE_SELECTOR || sel == INCREASE_ALLOWANCE_SELECTOR
            || sel == SET_APPROVAL_FOR_ALL_SELECTOR || sel == PERMIT_EIP2612_SELECTOR
            || sel == PERMIT_DAI_SELECTOR || sel == PERMIT2_APPROVE_SELECTOR
            || sel == PERMIT2_SINGLE_SELECTOR
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

    function _extCodeHash(address target) internal view returns (bytes32 codehash) {
        assembly {
            codehash := extcodehash(target)
        }
    }

    function _targetFingerprint(address target) internal view returns (bytes32) {
        return keccak256(abi.encode(_extCodeHash(target), _implementationCodeHash(target)));
    }

    function _implementationCodeHash(address target) internal view returns (bytes32) {
        (bool success, bytes memory returndata) = target.staticcall(hex"5c60da1b");
        if (!success || returndata.length < 32) {
            return bytes32(0);
        }

        address implementation = address(uint160(uint256(bytes32(returndata))));
        if (implementation.code.length == 0) {
            return bytes32(0);
        }

        return _extCodeHash(implementation);
    }
}
