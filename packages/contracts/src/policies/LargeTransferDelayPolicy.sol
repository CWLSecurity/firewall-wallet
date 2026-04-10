// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Decision, IFirewallPolicy} from "../interfaces/IFirewallPolicy.sol";
import {
    IPolicyIntrospection,
    PolicyConfigEntry,
    PolicyConfigValueType
} from "../interfaces/IPolicyIntrospection.sol";

/// @notice Delay policy for large native ETH value and large ERC20 transfer amounts.
///         Scope is intentionally narrow:
///         - native ETH value from tx `value`
///         - ERC20 `transfer(address,uint256)` amount
///         - ERC20 `transferFrom(address,address,uint256)` amount
///         ERC20 thresholds are normalized to 1e18 units using token decimals().
///         Stateless.
contract LargeTransferDelayPolicy is IFirewallPolicy, IPolicyIntrospection {
    uint256 public immutable ETH_THRESHOLD_WEI;
    uint256 public immutable ERC20_THRESHOLD_UNITS;
    uint48 public immutable DELAY_SECONDS;

    constructor(uint256 ethThresholdWei_, uint256 erc20ThresholdUnits_, uint48 delaySeconds_) {
        ETH_THRESHOLD_WEI = ethThresholdWei_;
        ERC20_THRESHOLD_UNITS = erc20ThresholdUnits_;
        DELAY_SECONDS = delaySeconds_;
    }

    function policyKey() external pure returns (bytes32) {
        return keccak256("large-transfer-delay-v1");
    }

    function policyName() external pure returns (string memory) {
        return "LargeTransferDelayPolicy";
    }

    function policyDescription() external pure returns (string memory) {
        return "Delays native ETH and ERC20 transfer/transferFrom at >= configured thresholds.";
    }

    function policyConfigVersion() external pure returns (uint16) {
        return 2;
    }

    function policyConfig() external view returns (PolicyConfigEntry[] memory entries) {
        entries = new PolicyConfigEntry[](6);
        entries[0] = PolicyConfigEntry({
            key: bytes32("eth_threshold_wei"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(ETH_THRESHOLD_WEI),
            unit: bytes32("wei")
        });
        entries[1] = PolicyConfigEntry({
            key: bytes32("erc20_threshold_units"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(ERC20_THRESHOLD_UNITS),
            unit: bytes32("token_units")
        });
        entries[2] = PolicyConfigEntry({
            key: bytes32("delay_seconds"),
            valueType: PolicyConfigValueType.Uint256,
            value: bytes32(uint256(DELAY_SECONDS)),
            unit: bytes32("seconds")
        });
        entries[3] = PolicyConfigEntry({
            key: bytes32("comparator_mode"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("gte"),
            unit: bytes32("mode")
        });
        entries[4] = PolicyConfigEntry({
            key: bytes32("selector_scope"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("eth+erc20xfers"),
            unit: bytes32("mode")
        });
        entries[5] = PolicyConfigEntry({
            key: bytes32("erc20_threshold_unit_scale"),
            valueType: PolicyConfigValueType.Bytes32,
            value: bytes32("1e18_normalized"),
            unit: bytes32("mode")
        });
    }

    function evaluate(
        address,
        address to,
        uint256 value,
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        if (value >= ETH_THRESHOLD_WEI) {
            return (Decision.Delay, DELAY_SECONDS);
        }

        (bool matchedTransferSelector, uint256 amount) = _erc20Amount(data);
        if (!matchedTransferSelector) {
            return (Decision.Allow, 0);
        }

        (uint256 normalizedAmount, bool normalizedOk) = _normalizeTo18Decimals(to, amount);
        if (!normalizedOk) {
            return (Decision.Delay, DELAY_SECONDS);
        }

        if (normalizedAmount >= ERC20_THRESHOLD_UNITS) {
            return (Decision.Delay, DELAY_SECONDS);
        }

        return (Decision.Allow, 0);
    }

    /// @notice Backward-compatible alias for legacy integrations.
    function THRESHOLD_WEI() external view returns (uint256) {
        return ETH_THRESHOLD_WEI;
    }

    function _erc20Amount(bytes calldata data) internal pure returns (bool matched, uint256 amount) {
        if (data.length < 4) return (false, 0);

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        // transfer(address,uint256)
        if (sel == 0xa9059cbb && data.length >= 68) {
            assembly {
                amount := calldataload(add(data.offset, 36))
            }
            return (true, amount);
        }

        // transferFrom(address,address,uint256)
        if (sel == 0x23b872dd && data.length >= 100) {
            assembly {
                amount := calldataload(add(data.offset, 68))
            }
            return (true, amount);
        }

        return (false, 0);
    }

    function _normalizeTo18Decimals(address token, uint256 amount)
        internal
        view
        returns (uint256 normalizedAmount, bool normalizedOk)
    {
        (uint8 tokenDecimals, bool hasDecimals) = _readTokenDecimals(token);
        uint8 decimals = hasDecimals ? tokenDecimals : 18;

        if (decimals == 18) {
            return (amount, true);
        }

        if (decimals < 18) {
            uint256 factor = 10 ** uint256(18 - decimals);
            if (amount > type(uint256).max / factor) {
                return (type(uint256).max, true);
            }
            return (amount * factor, true);
        }

        uint256 scaleDown = uint256(decimals - 18);
        if (scaleDown > 77) {
            return (0, false);
        }

        uint256 divisor = 10 ** scaleDown;
        return (amount / divisor, true);
    }

    function _readTokenDecimals(address token) internal view returns (uint8 decimals, bool ok) {
        (bool success, bytes memory returndata) = token.staticcall(hex"313ce567");
        if (!success || returndata.length < 32) {
            return (0, false);
        }

        uint256 parsed = abi.decode(returndata, (uint256));
        if (parsed > type(uint8).max) {
            return (0, false);
        }

        return (uint8(parsed), true);
    }
}
