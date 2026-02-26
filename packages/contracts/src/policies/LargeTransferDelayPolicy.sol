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
        bytes calldata data
    ) external view returns (Decision decision, uint48 delayOut) {
        if (value > THRESHOLD_WEI) {
            return (Decision.Delay, DELAY_SECONDS);
        }

        uint256 amount = _erc20Amount(data);
        if (amount > THRESHOLD_WEI) {
            return (Decision.Delay, DELAY_SECONDS);
        }

        return (Decision.Allow, 0);
    }

    function _erc20Amount(bytes calldata data) internal pure returns (uint256 amount) {
        if (data.length < 4) return 0;

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset)
        }

        // transfer(address,uint256)
        if (sel == 0xa9059cbb && data.length >= 68) {
            assembly {
                amount := calldataload(add(data.offset, 36))
            }
            return amount;
        }

        // transferFrom(address,address,uint256)
        if (sel == 0x23b872dd && data.length >= 100) {
            assembly {
                amount := calldataload(add(data.offset, 68))
            }
            return amount;
        }

        return 0;
    }
}
