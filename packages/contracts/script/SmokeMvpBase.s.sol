// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/*
Required env:
- DEPLOYER_PK: private key used to broadcast and own smoke wallets.

Optional env:
- MVP_FACTORY: existing FirewallFactory address; if empty, script deploys a local smoke stack.
- MVP_RECOVERY: recovery address for created wallets (defaults to owner/deployer).

Examples:
forge script script/SmokeMvpBase.s.sol:SmokeMvpBase \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $DEPLOYER_PK \
  --broadcast -vvv

forge script script/SmokeMvpBase.s.sol:SmokeMvpBase \
  --fork-url $BASE_RPC_URL \
  --private-key $DEPLOYER_PK \
  --broadcast -vvv
*/

import "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import {FirewallFactory} from "../src/FirewallFactory.sol";
import {FirewallModule} from "../src/FirewallModule.sol";
import {Decision} from "../src/interfaces/IFirewallPolicy.sol";

import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";
import {LargeTransferDelayPolicy} from "../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../src/policies/NewReceiverDelayPolicy.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";

contract SmokeMvpBase is Script {
    struct RunContext {
        FirewallFactory factory;
        address wallet0;
        address router0;
        address wallet1;
        address router1;
    }

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery,
        uint8 presetId
    );

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address owner = vm.addr(pk);
        address recovery = vm.envOr("MVP_RECOVERY", owner);
        address factoryAddr = vm.envOr("MVP_FACTORY", address(0));

        vm.startBroadcast(pk);

        RunContext memory ctx = _prepareContext(factoryAddr, owner, recovery);
        MockERC20 token = _deployAndMintMockToken(ctx.wallet0, ctx.wallet1);
        _runScheduleFlow(ctx.wallet0, address(token));
        _runPermitFlow(ctx.factory, address(token), ctx.wallet0, ctx.wallet1);

        vm.stopBroadcast();
    }

    function _prepareContext(address factoryAddr, address owner, address recovery)
        internal
        returns (RunContext memory ctx)
    {
        ctx.factory = _resolveFactory(factoryAddr);

        console2.log("factory", address(ctx.factory));
        console2.log("owner", owner);
        console2.log("recovery", recovery);

        (ctx.wallet0, ctx.router0) = _createWalletAndRouter(ctx.factory, owner, recovery, 0);
        (ctx.wallet1, ctx.router1) = _createWalletAndRouter(ctx.factory, owner, recovery, 1);

        console2.log("wallet_preset0", ctx.wallet0);
        console2.log("router_preset0", ctx.router0);
        console2.log("wallet_preset1", ctx.wallet1);
        console2.log("router_preset1", ctx.router1);
    }

    function _deployAndMintMockToken(address wallet0, address wallet1) internal returns (MockERC20 token) {
        token = new MockERC20();
        token.mint(wallet0, 100 ether);
        token.mint(wallet1, 100 ether);
        console2.log("mock_token", address(token));
    }

    function _runScheduleFlow(address wallet0, address token) internal {
        // 1) Delay path + getScheduled(txId) readback on preset 0 wallet.
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(0xCAFE),
            1 ether
        );

        bytes32 txId = FirewallModule(payable(wallet0)).schedule(token, 0, transferData);
        console2.logBytes32(txId);

        (
            bool exists,
            bool executed,
            address to,
            uint256 value,
            uint48 unlockTime,
            bytes32 dataHash
        ) = FirewallModule(payable(wallet0)).getScheduled(txId);

        console2.log("scheduled.exists", exists);
        console2.log("scheduled.executed", executed);
        console2.log("scheduled.to", to);
        console2.log("scheduled.value", value);
        console2.log("scheduled.unlockTime", uint256(unlockTime));
        console2.logBytes32(dataHash);
    }

    function _runPermitFlow(FirewallFactory factory, address token, address wallet0, address wallet1) internal view {
        // 2) Permit difference between presets via InfiniteApprovalPolicy evaluate path.
        bytes memory permitData = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            wallet0,
            address(0xBEEF),
            1 ether,
            block.timestamp + 1 days,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );

        Decision permitDecisionPreset0 = _permitDecisionFromPreset(factory, 0, token, wallet0, permitData);
        Decision permitDecisionPreset1 = _permitDecisionFromPreset(factory, 1, token, wallet1, permitData);

        console2.log("permit_decision_preset0", uint256(permitDecisionPreset0));
        console2.log("permit_decision_preset1", uint256(permitDecisionPreset1));
    }

    function _resolveFactory(address factoryAddr) internal returns (FirewallFactory factory) {
        if (factoryAddr != address(0)) {
            return FirewallFactory(factoryAddr);
        }

        InfiniteApprovalPolicy conservativeApprove = new InfiniteApprovalPolicy(type(uint256).max, false);
        InfiniteApprovalPolicy defiApprove = new InfiniteApprovalPolicy(type(uint256).max, true);

        // Small thresholds for smoke-flow convenience.
        LargeTransferDelayPolicy large = new LargeTransferDelayPolicy(0.05 ether, 1 hours);
        NewReceiverDelayPolicy newReceiver = new NewReceiverDelayPolicy(1 hours);

        address[] memory conservative = new address[](3);
        conservative[0] = address(conservativeApprove);
        conservative[1] = address(large);
        conservative[2] = address(newReceiver);

        address[] memory defi = new address[](3);
        defi[0] = address(defiApprove);
        defi[1] = address(large);
        defi[2] = address(newReceiver);

        factory = new FirewallFactory(conservative, defi);
    }

    function _createWalletAndRouter(FirewallFactory factory, address owner, address recovery, uint8 presetId)
        internal
        returns (address wallet, address router)
    {
        vm.recordLogs();
        wallet = factory.createWallet(owner, recovery, presetId);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 sig = keccak256("WalletCreated(address,address,address,address,uint8)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].emitter == address(factory) && entries[i].topics.length == 4
                    && entries[i].topics[0] == sig
            ) {
                router = address(uint160(uint256(entries[i].topics[3])));
                break;
            }
        }

        require(router != address(0), "WalletCreated router not found");
    }

    function _permitDecisionFromPreset(
        FirewallFactory factory,
        uint8 presetId,
        address token,
        address wallet,
        bytes memory permitData
    ) internal view returns (Decision decision) {
        address policyAddr = presetId == 0 ? factory.policiesConservative(0) : factory.policiesDefi(0);
        InfiniteApprovalPolicy policy = InfiniteApprovalPolicy(policyAddr);
        (decision,) = policy.evaluate(wallet, token, 0, permitData);
    }
}
