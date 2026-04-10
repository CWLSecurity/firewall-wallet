// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/StdInvariant.sol";
import {SmokeBase} from "../smoke/SmokeBase.t.sol";
import {FirewallModule} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {V2VaultInvariantHandler} from "./handlers/V2VaultInvariantHandler.t.sol";

contract V2VaultInvariant is StdInvariant, SmokeBase {
    uint256 internal constant WALLET_COUNT = 12;

    V2VaultInvariantHandler internal handler;
    address[] internal walletAddrs;
    address[] internal routerAddrs;

    function setUp() public {
        _deployV2WithRealBasePacks();

        for (uint256 i = 0; i < WALLET_COUNT; i++) {
            uint256 basePack = i % 2 == 0 ? BASE_PACK_CONSERVATIVE : BASE_PACK_DEFI;
            (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePack);

            if (i % 3 == 0) {
                router.enableAddonPack(ADDON_PACK_NEW_RECEIVER_24H);
            }
            if (i % 4 == 0) {
                router.enableAddonPack(ADDON_PACK_LARGE_TRANSFER_24H);
            }
            if (basePack == BASE_PACK_DEFI && i % 5 == 0) {
                router.enableAddonPack(ADDON_PACK_APPROVAL_HARDENING);
            }

            vm.deal(address(wallet), 50 ether);
            walletAddrs.push(address(wallet));
            routerAddrs.push(address(router));
        }

        handler = new V2VaultInvariantHandler(address(this), walletAddrs, routerAddrs);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.actionExecuteNow.selector;
        selectors[1] = handler.actionSchedule.selector;
        selectors[2] = handler.actionExecuteScheduled.selector;
        selectors[3] = handler.actionCancelScheduled.selector;
        selectors[4] = handler.actionEnableAddon.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_NoUnexpectedOutcomes() public view {
        assertEq(handler.unexpectedAllowFailureCount(), 0, "allow path failed unexpectedly");
        assertEq(handler.unexpectedDisallowedSuccessCount(), 0, "disallowed path unexpectedly succeeded");
        assertEq(handler.unexpectedEarlyExecutionSuccessCount(), 0, "early execute unexpectedly succeeded");
        assertEq(handler.unexpectedDelayScheduleFailureCount(), 0, "delay schedule unexpectedly failed");
        assertEq(handler.unexpectedAddonEnableFailureCount(), 0, "addon enable unexpectedly failed");
    }

    function invariant_PendingQueueEntriesRemainConsistent() public view {
        assertTrue(handler.pendingConsistency(), "tracked pending queue contains invalid entries");
    }

    function invariant_BindingsAndReserveFloorStayValid() public view {
        for (uint256 i = 0; i < walletAddrs.length; i++) {
            FirewallModule wallet = FirewallModule(payable(walletAddrs[i]));
            PolicyRouter router = PolicyRouter(routerAddrs[i]);

            assertEq(wallet.router(), address(router), "wallet->router binding changed");
            assertEq(router.firewallModule(), address(wallet), "router->wallet binding changed");
            assertEq(router.owner(), address(this), "router owner changed");
            assertLe(wallet.totalScheduledReserve(), address(wallet).balance, "reserved exceeds balance");
        }
    }
}
