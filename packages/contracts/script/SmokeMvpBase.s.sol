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
import {Decision, IFirewallPolicy} from "../src/interfaces/IFirewallPolicy.sol";
import {PolicyPackRegistry} from "../src/PolicyPackRegistry.sol";
import {SimpleEntitlementManager} from "../src/SimpleEntitlementManager.sol";

import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";
import {DeFiApprovalPolicy} from "../src/policies/DeFiApprovalPolicy.sol";
import {ApprovalToNewSpenderDelayPolicy} from "../src/policies/ApprovalToNewSpenderDelayPolicy.sol";
import {Erc20FirstNewRecipientDelayPolicy} from "../src/policies/Erc20FirstNewRecipientDelayPolicy.sol";
import {LargeTransferDelayPolicy} from "../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../src/policies/NewReceiverDelayPolicy.sol";
import {NewEOAReceiverDelayPolicy} from "../src/policies/NewEOAReceiverDelayPolicy.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";

contract SmokeMvpBase is Script {
    uint16 internal constant PACK_VERSION_V1 = 1;
    uint256 internal constant BASE_PACK_CONSERVATIVE = 0;
    uint256 internal constant BASE_PACK_DEFI = 1;
    uint256 internal constant ADDON_PACK_APPROVAL_HARDENING = 2;
    uint256 internal constant ADDON_PACK_NEW_RECEIVER_24H = 3;
    uint256 internal constant ADDON_PACK_LARGE_TRANSFER_24H = 4;

    struct SmokePolicies {
        address conservativeApprove;
        address defiApprove;
        address defiApprovalToNewSpender;
        address defiErc20FirstRecipient;
        address conservativeLarge;
        address defiLarge;
        address addonLarge;
        address conservativeNewReceiver;
        address defiNewReceiver;
        address addonNewReceiver;
        address addonApprovalHardening;
    }

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
        uint256 basePackId
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
        ctx.factory = _resolveFactory(factoryAddr, owner);

        console2.log("factory", address(ctx.factory));
        console2.log("owner", owner);
        console2.log("recovery", recovery);

        (ctx.wallet0, ctx.router0) = _createWalletAndRouter(ctx.factory, owner, recovery, uint8(BASE_PACK_CONSERVATIVE));
        (ctx.wallet1, ctx.router1) = _createWalletAndRouter(ctx.factory, owner, recovery, uint8(BASE_PACK_DEFI));

        console2.log("wallet_base0_conservative", ctx.wallet0);
        console2.log("router_base0_conservative", ctx.router0);
        console2.log("wallet_base1_defi_trader", ctx.wallet1);
        console2.log("router_base1_defi_trader", ctx.router1);
    }

    function _deployAndMintMockToken(address wallet0, address wallet1) internal returns (MockERC20 token) {
        token = new MockERC20();
        token.mint(wallet0, 100 ether);
        token.mint(wallet1, 100 ether);
        console2.log("mock_token", address(token));
    }

    function _runScheduleFlow(address wallet0, address token) internal {
        // 1) Delay path + getScheduled(txId) readback on base pack 0 wallet.
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
        // 2) Permit difference between base packs via base approval policy evaluate path.
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

        Decision permitDecisionBase0 = _permitDecisionFromBasePack(factory, 0, token, wallet0, permitData);
        Decision permitDecisionBase1 = _permitDecisionFromBasePack(factory, 1, token, wallet1, permitData);

        console2.log("permit_decision_base0", uint256(permitDecisionBase0));
        console2.log("permit_decision_base1", uint256(permitDecisionBase1));
    }

    function _resolveFactory(address factoryAddr, address owner)
        internal
        returns (FirewallFactory factory)
    {
        if (factoryAddr != address(0)) {
            return FirewallFactory(factoryAddr);
        }

        SmokePolicies memory policies = _deploySmokePolicies();

        PolicyPackRegistry registry = new PolicyPackRegistry(owner);
        SimpleEntitlementManager entitlement = new SimpleEntitlementManager(owner);
        _registerSmokePacks(registry, policies);

        factory = new FirewallFactory(address(registry), address(entitlement));
    }

    function _deploySmokePolicies() internal returns (SmokePolicies memory policies) {
        policies.conservativeApprove = address(new InfiniteApprovalPolicy(type(uint256).max, false));
        policies.defiApprove = address(new DeFiApprovalPolicy());
        policies.defiApprovalToNewSpender = address(new ApprovalToNewSpenderDelayPolicy(30 minutes));
        policies.defiErc20FirstRecipient = address(new Erc20FirstNewRecipientDelayPolicy(30 minutes));

        // Small thresholds for smoke-flow convenience.
        policies.conservativeLarge = address(new LargeTransferDelayPolicy(0.05 ether, 0.05 ether, 1 hours));
        policies.defiLarge = address(new LargeTransferDelayPolicy(0.25 ether, 0.25 ether, 30 minutes));
        policies.addonLarge = address(new LargeTransferDelayPolicy(1 ether, 1, 24 hours));
        policies.conservativeNewReceiver = address(new NewReceiverDelayPolicy(1 hours));
        policies.defiNewReceiver = address(new NewEOAReceiverDelayPolicy(30 minutes));
        policies.addonNewReceiver = address(new NewReceiverDelayPolicy(24 hours));
        policies.addonApprovalHardening = address(new InfiniteApprovalPolicy(type(uint256).max, false));
    }

    function _registerSmokePacks(PolicyPackRegistry registry, SmokePolicies memory policies) internal {
        address[] memory conservative = new address[](3);
        conservative[0] = policies.conservativeApprove;
        conservative[1] = policies.conservativeLarge;
        conservative[2] = policies.conservativeNewReceiver;
        registry.registerPackDetailed(
            BASE_PACK_CONSERVATIVE,
            registry.PACK_TYPE_BASE(),
            registry.PACK_ACCESS_FREE(),
            keccak256("base-conservative"),
            "base-conservative",
            PACK_VERSION_V1,
            true,
            conservative
        );

        address[] memory defi = new address[](5);
        defi[0] = policies.defiApprove;
        defi[1] = policies.defiApprovalToNewSpender;
        defi[2] = policies.defiErc20FirstRecipient;
        defi[3] = policies.defiLarge;
        defi[4] = policies.defiNewReceiver;
        registry.registerPackDetailed(
            BASE_PACK_DEFI,
            registry.PACK_TYPE_BASE(),
            registry.PACK_ACCESS_FREE(),
            keccak256("base-defi"),
            "base-defi",
            PACK_VERSION_V1,
            true,
            defi
        );

        address[] memory approvalHardeningAddon = new address[](1);
        approvalHardeningAddon[0] = policies.addonApprovalHardening;
        registry.registerPackDetailed(
            ADDON_PACK_APPROVAL_HARDENING,
            registry.PACK_TYPE_ADDON(),
            registry.PACK_ACCESS_FREE(),
            keccak256("addon-approval-hardening"),
            "addon-approval-hardening",
            PACK_VERSION_V1,
            true,
            approvalHardeningAddon
        );

        address[] memory newReceiverAddon = new address[](1);
        newReceiverAddon[0] = policies.addonNewReceiver;
        registry.registerPackDetailed(
            ADDON_PACK_NEW_RECEIVER_24H,
            registry.PACK_TYPE_ADDON(),
            registry.PACK_ACCESS_FREE(),
            keccak256("addon-new-receiver-24h-delay"),
            "addon-new-receiver-24h-delay",
            PACK_VERSION_V1,
            true,
            newReceiverAddon
        );

        address[] memory largeTransferAddon = new address[](1);
        largeTransferAddon[0] = policies.addonLarge;
        registry.registerPackDetailed(
            ADDON_PACK_LARGE_TRANSFER_24H,
            registry.PACK_TYPE_ADDON(),
            registry.PACK_ACCESS_FREE(),
            keccak256("addon-large-transfer-24h-delay"),
            "addon-large-transfer-24h-delay",
            PACK_VERSION_V1,
            true,
            largeTransferAddon
        );
    }

    function _createWalletAndRouter(FirewallFactory factory, address owner, address recovery, uint8 basePackId)
        internal
        returns (address wallet, address router)
    {
        vm.recordLogs();
        wallet = factory.createWallet(owner, recovery, basePackId);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 sig = keccak256("WalletCreated(address,address,address,address,uint256)");
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

    function _permitDecisionFromBasePack(
        FirewallFactory factory,
        uint8 basePackId,
        address token,
        address wallet,
        bytes memory permitData
    ) internal view returns (Decision decision) {
        PolicyPackRegistry registry = PolicyPackRegistry(factory.policyPackRegistry());
        address[] memory policies = registry.getPackPolicies(basePackId);
        address policyAddr = policies[0];
        (decision,) = IFirewallPolicy(policyAddr).evaluate(wallet, token, 0, permitData);
    }
}
