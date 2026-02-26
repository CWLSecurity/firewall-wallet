// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {FirewallFactory} from "../src/FirewallFactory.sol";
import {PolicyRouter, Router_Unauthorized} from "../src/PolicyRouter.sol";
import {MockPolicy} from "./mocks/MockPolicies.sol";
import {Decision} from "../src/interfaces/IFirewallPolicy.sol";

contract FactoryRouterTest is Test {
    address internal OWNER = address(0xA11CE);
    address internal RECOVERY = address(0xB0B);

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery
    );

    function _deployFactory() internal returns (FirewallFactory f) {
        MockPolicy p = new MockPolicy(Decision.Allow, 0);
        address[] memory policies = new address[](1);
        policies[0] = address(p);
        f = new FirewallFactory(policies);
    }

    function _createWallet(FirewallFactory f) internal returns (address wallet, address router) {
        vm.recordLogs();
        wallet = f.createWallet(OWNER, RECOVERY);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("WalletCreated(address,address,address,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(f) &&
                entries[i].topics.length == 4 &&
                entries[i].topics[0] == sig
            ) {
                assertEq(address(uint160(uint256(entries[i].topics[2]))), wallet);
                router = address(uint160(uint256(entries[i].topics[3])));
                break;
            }
        }
        assertTrue(router != address(0), "WalletCreated not found");
    }

    function test_FactoryCreatesWalletAndRouter() public {
        FirewallFactory f = _deployFactory();
        (address wallet, address routerAddr) = _createWallet(f);

        PolicyRouter r = PolicyRouter(routerAddr);
        assertEq(r.owner(), OWNER);
        assertEq(r.firewallModule(), wallet);
        assertTrue(routerAddr != address(0));
        assertTrue(wallet != address(0));
        assertTrue(routerAddr != wallet);
    }

    function test_FactoryCreatesFreshRouterPerWallet() public {
        FirewallFactory f = _deployFactory();
        (, address r1) = _createWallet(f);
        (, address r2) = _createWallet(f);

        assertTrue(r1 != r2);
    }

    function test_NotifyExecuted_onlyWallet() public {
        FirewallFactory f = _deployFactory();
        (address wallet, address routerAddr) = _createWallet(f);
        PolicyRouter r = PolicyRouter(routerAddr);

        vm.prank(address(0xBAD));
        vm.expectRevert(Router_Unauthorized.selector);
        r.notifyExecuted(address(0xCAFE), address(0xBEEF), 0, "");

        vm.prank(wallet);
        r.notifyExecuted(address(0xCAFE), address(0xBEEF), 0, "");
    }

    function test_FactoryHasNoPostCreationControl() public {
        FirewallFactory f = _deployFactory();
        (, address routerAddr) = _createWallet(f);

        PolicyRouter r = PolicyRouter(routerAddr);
        assertTrue(r.owner() != address(f));
    }
}
