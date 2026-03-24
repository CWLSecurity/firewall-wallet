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

/// @notice Delay transfers to new receivers.
///         First time → Delay
///         After successful execution → receiver becomes known.
contract NewReceiverDelayPolicy is IFirewallPolicy, IFirewallPostExecPolicy, IPolicyIntrospection {
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
    bool public constant EOA_ONLY = false;

    // vault => receiver => known
    mapping(address => mapping(address => bool)) public knownReceivers;

    constructor(uint48 _delaySeconds) {
        DELAY_SECONDS = _delaySeconds;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("new-receiver-delay-v1");
    }

    function policyName() external pure returns (string memory) {
        return "NewReceiverDelayPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Delays first transfer target per vault for both EOAs and contracts.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 1;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](3);
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
            value: bytes32("all_receivers"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address vault,
        address to,
        uint256,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        (bool applies, address receiver) = _receiverFromCall(to, data);
        if (!applies) {
            return (Decision.Allow, 0);
        }
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
        _assertTrustedHookCaller(vault);
        (bool applies, address receiver) = _receiverFromCall(to, data);
        if (!applies) return;
        knownReceivers[vault][receiver] = true;
    }

    function _receiverFromCall(address to, bytes calldata data)
        internal
        pure
        returns (bool applies, address receiver)
    {
        receiver = to;
        if (data.length < 4) return (true, receiver);

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        // Approval-like calls are governed by approval-focused policies and must not
        // be classified as "new receiver" candidates.
        if (_isApprovalLikeSelector(sel)) {
            return (false, address(0));
        }

        // ERC20 transfer(address,uint256)
        if (sel == TRANSFER_SELECTOR && data.length >= 68) {
            assembly {
                receiver := and(calldataload(add(data.offset, 4)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, receiver);
        }

        // ERC20 transferFrom(address,address,uint256)
        // ERC721 transferFrom(address,address,uint256)
        if (sel == TRANSFER_FROM_SELECTOR && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, receiver);
        }

        // ERC721 safeTransferFrom(address,address,uint256)
        if (sel == SAFE_TRANSFER_FROM_ERC721_SELECTOR && data.length >= 100) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, receiver);
        }

        // ERC721 safeTransferFrom(address,address,uint256,bytes)
        if (sel == SAFE_TRANSFER_FROM_ERC721_WITH_DATA_SELECTOR && data.length >= 132) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, receiver);
        }

        // ERC1155 safeTransferFrom(address,address,uint256,uint256,bytes)
        if (sel == SAFE_TRANSFER_FROM_ERC1155_SELECTOR && data.length >= 164) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, receiver);
        }

        // ERC1155 safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)
        if (sel == SAFE_BATCH_TRANSFER_FROM_ERC1155_SELECTOR && data.length >= 164) {
            assembly {
                receiver := and(calldataload(add(data.offset, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
            return (true, receiver);
        }

        return (true, receiver);
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
