// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {FirewallModule} from "../../../src/FirewallModule.sol";
import {PolicyRouter} from "../../../src/PolicyRouter.sol";
import {Decision} from "../../../src/interfaces/IFirewallPolicy.sol";

contract V2VaultInvariantHandler is Test {
    address public immutable owner;

    FirewallModule[] internal wallets;
    PolicyRouter[] internal routers;
    bytes32[][] internal pendingByWallet;

    uint256 public unexpectedAllowFailureCount;
    uint256 public unexpectedDisallowedSuccessCount;
    uint256 public unexpectedEarlyExecutionSuccessCount;
    uint256 public unexpectedDelayScheduleFailureCount;
    uint256 public unexpectedAddonEnableFailureCount;

    constructor(address owner_, address[] memory walletAddrs, address[] memory routerAddrs) {
        require(walletAddrs.length == routerAddrs.length, "len");
        owner = owner_;

        for (uint256 i = 0; i < walletAddrs.length; i++) {
            wallets.push(FirewallModule(payable(walletAddrs[i])));
            routers.push(PolicyRouter(routerAddrs[i]));
            pendingByWallet.push();
        }
    }

    function actionExecuteNow(uint256 senderSeed, uint256 recipientSeed, uint96 amountSeed) external {
        if (wallets.length == 0) return;

        uint256 senderIdx = senderSeed % wallets.length;
        uint256 recipientIdx = recipientSeed % wallets.length;
        if (recipientIdx == senderIdx) {
            recipientIdx = (recipientIdx + 1) % wallets.length;
        }

        FirewallModule sender = wallets[senderIdx];
        PolicyRouter senderRouter = routers[senderIdx];
        address recipient = address(wallets[recipientIdx]);
        uint256 amount = bound(uint256(amountSeed), 1, 1 ether);

        _ensureLiquidity(sender, amount + 2 ether);
        (Decision decision, ) = senderRouter.evaluate(address(sender), recipient, amount, "");

        vm.prank(owner);
        (bool ok,) = address(sender).call(abi.encodeCall(FirewallModule.executeNow, (recipient, amount, bytes(""))));

        if (decision == Decision.Allow && !ok) {
            unexpectedAllowFailureCount++;
        } else if (decision != Decision.Allow && ok) {
            unexpectedDisallowedSuccessCount++;
        }
    }

    function actionSchedule(uint256 senderSeed, uint256 recipientSeed, uint96 amountSeed) external {
        if (wallets.length == 0) return;

        uint256 senderIdx = senderSeed % wallets.length;
        uint256 recipientIdx = recipientSeed % wallets.length;
        if (recipientIdx == senderIdx) {
            recipientIdx = (recipientIdx + 1) % wallets.length;
        }

        FirewallModule sender = wallets[senderIdx];
        PolicyRouter senderRouter = routers[senderIdx];
        address recipient = address(wallets[recipientIdx]);
        uint256 amount = bound(uint256(amountSeed), 1, 1 ether);

        _ensureLiquidity(sender, amount + 2 ether);
        (Decision decision, ) = senderRouter.evaluate(address(sender), recipient, amount, "");

        vm.prank(owner);
        (bool ok, bytes memory ret) =
            address(sender).call(abi.encodeCall(FirewallModule.schedule, (recipient, amount, bytes(""))));

        if (decision == Decision.Delay) {
            if (!ok || ret.length != 32) {
                unexpectedDelayScheduleFailureCount++;
                return;
            }
            bytes32 txId = abi.decode(ret, (bytes32));
            pendingByWallet[senderIdx].push(txId);
            return;
        }

        if (ok) {
            unexpectedDisallowedSuccessCount++;
        }
    }

    function actionExecuteScheduled(uint256 walletSeed, uint256 txSeed, uint256 timingSeed) external {
        if (wallets.length == 0) return;
        uint256 walletIdx = walletSeed % wallets.length;
        if (pendingByWallet[walletIdx].length == 0) return;

        uint256 txIdx = txSeed % pendingByWallet[walletIdx].length;
        bytes32 txId = pendingByWallet[walletIdx][txIdx];
        FirewallModule wallet = wallets[walletIdx];

        (bool exists, bool executed, , uint256 value, uint48 unlockTime, ) = wallet.getScheduled(txId);
        if (!exists || executed) {
            _removePending(walletIdx, txIdx);
            return;
        }

        bool tryEarly = (timingSeed & 1) == 0;
        if (tryEarly && block.timestamp < unlockTime) {
            vm.prank(owner);
            (bool earlyOk,) = address(wallet).call(abi.encodeCall(FirewallModule.executeScheduled, (txId)));
            if (earlyOk) {
                unexpectedEarlyExecutionSuccessCount++;
                _removePending(walletIdx, txIdx);
            }
            return;
        }

        if (block.timestamp < unlockTime) {
            vm.warp(unlockTime);
        }
        _ensureLiquidity(wallet, value + 2 ether);

        vm.prank(owner);
        (bool ok,) = address(wallet).call(abi.encodeCall(FirewallModule.executeScheduled, (txId)));
        if (ok) _removePending(walletIdx, txIdx);
    }

    function actionCancelScheduled(uint256 walletSeed, uint256 txSeed) external {
        if (wallets.length == 0) return;
        uint256 walletIdx = walletSeed % wallets.length;
        if (pendingByWallet[walletIdx].length == 0) return;

        uint256 txIdx = txSeed % pendingByWallet[walletIdx].length;
        bytes32 txId = pendingByWallet[walletIdx][txIdx];
        FirewallModule wallet = wallets[walletIdx];

        vm.prank(owner);
        (bool ok,) = address(wallet).call(abi.encodeCall(FirewallModule.cancelScheduled, (txId)));
        if (ok) {
            _removePending(walletIdx, txIdx);
            return;
        }

        (bool exists, bool executed, , , , ) = wallet.getScheduled(txId);
        if (!exists || executed) {
            _removePending(walletIdx, txIdx);
        }
    }

    function actionEnableAddon(uint256 walletSeed, uint8 packSelector) external {
        if (wallets.length == 0) return;
        uint256 walletIdx = walletSeed % wallets.length;
        PolicyRouter router = routers[walletIdx];

        uint256 packId;
        if (packSelector % 3 == 0) {
            packId = 2;
        } else if (packSelector % 3 == 1) {
            packId = 3;
        } else {
            packId = 4;
        }

        if (router.isAddonPackEnabled(packId)) return;

        vm.prank(owner);
        (bool ok,) = address(router).call(abi.encodeCall(PolicyRouter.enableAddonPack, (packId)));
        if (!ok) {
            unexpectedAddonEnableFailureCount++;
        }
    }

    function pendingConsistency() external view returns (bool) {
        for (uint256 i = 0; i < wallets.length; i++) {
            bytes32[] storage walletPending = pendingByWallet[i];
            for (uint256 j = 0; j < walletPending.length; j++) {
                (bool exists, bool executed, , , uint48 unlockTime, ) = wallets[i].getScheduled(walletPending[j]);
                if (!exists || executed || unlockTime == 0) {
                    return false;
                }
            }
        }
        return true;
    }

    function pendingCount(uint256 walletIdx) external view returns (uint256) {
        return pendingByWallet[walletIdx].length;
    }

    function walletCount() external view returns (uint256) {
        return wallets.length;
    }

    function walletAt(uint256 idx) external view returns (address) {
        return address(wallets[idx]);
    }

    function routerAt(uint256 idx) external view returns (address) {
        return address(routers[idx]);
    }

    function _removePending(uint256 walletIdx, uint256 txIdx) internal {
        bytes32[] storage walletPending = pendingByWallet[walletIdx];
        uint256 last = walletPending.length - 1;
        if (txIdx != last) {
            walletPending[txIdx] = walletPending[last];
        }
        walletPending.pop();
    }

    function _ensureLiquidity(FirewallModule wallet, uint256 minBalance) internal {
        uint256 current = address(wallet).balance;
        if (current < minBalance) {
            vm.deal(address(wallet), minBalance + 5 ether);
        }
    }
}
