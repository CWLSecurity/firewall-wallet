// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SmokeBase} from "./SmokeBase.t.sol";
import {Decision, IFirewallPolicy} from "../../src/interfaces/IFirewallPolicy.sol";
import {FirewallModule} from "../../src/FirewallModule.sol";
import {PolicyRouter} from "../../src/PolicyRouter.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockReceiver} from "../../src/mocks/MockReceiver.sol";

contract V2DecisionFoldParity is SmokeBase {
    struct EvalContext {
        address vault;
        address to;
        uint256 value;
        bytes data;
    }

    function setUp() public {
        _deployV2WithRealBasePacks();
    }

    function test_DecisionFoldParity_AcrossBaseAndAddonSnapshots() public {
        uint8[4] memory conservativeMasks = [uint8(0), uint8(2), uint8(4), uint8(6)];
        for (uint256 i = 0; i < conservativeMasks.length; i++) {
            _runParitySet(BASE_PACK_CONSERVATIVE, conservativeMasks[i], i);
        }

        for (uint8 mask = 0; mask < 8; mask++) {
            _runParitySet(BASE_PACK_DEFI, mask, mask);
        }
    }

    function _runParitySet(uint256 basePackId, uint8 mask, uint256 idx) internal {
        (FirewallModule wallet, PolicyRouter router) = _createWalletAndRouter(basePackId);
        _enableMask(router, basePackId, mask);

        vm.deal(address(wallet), 5 ether);

        address trustedEoa = address(uint160(0x300000 + (basePackId * 0x100) + idx));
        MockReceiver contractTarget = new MockReceiver();
        MockERC20 token = new MockERC20();
        token.mint(address(wallet), 10 ether);

        _assertParity(router, address(wallet), trustedEoa, 0.01 ether, "", "native_small");
        _assertParity(router, address(wallet), trustedEoa, 1 ether, "", "native_large");

        bytes memory erc20Transfer =
            abi.encodeWithSignature("transfer(address,uint256)", trustedEoa, 0.1 ether);
        _assertParity(router, address(wallet), address(token), 0, erc20Transfer, "erc20_transfer");

        bytes memory unknownCall = abi.encodeWithSignature("ping(uint256)", 1);
        _assertParity(
            router, address(wallet), address(contractTarget), 0, unknownCall, "unknown_selector_contract"
        );
    }

    function _assertParity(
        PolicyRouter router,
        address vault,
        address to,
        uint256 value,
        bytes memory data,
        string memory label
    ) internal view {
        (bool routerOk, Decision routerDecision, uint48 routerDelay) = _evalRouter(router, vault, to, value, data);
        (bool modelOk, Decision modelDecision, uint48 modelDelay) = _manualFold(router, vault, to, value, data);

        assertEq(routerOk, modelOk, string.concat(label, ": ok mismatch"));
        if (!routerOk) {
            return;
        }

        assertEq(
            uint256(routerDecision),
            uint256(modelDecision),
            string.concat(label, ": decision mismatch")
        );
        assertEq(routerDelay, modelDelay, string.concat(label, ": delay mismatch"));
    }

    function _manualFold(PolicyRouter router, address vault, address to, uint256 value, bytes memory data)
        internal
        view
        returns (bool ok, Decision decision, uint48 delaySeconds)
    {
        EvalContext memory ctx = EvalContext({vault: vault, to: to, value: value, data: data});
        decision = Decision.Allow;
        delaySeconds = 0;

        (ok, decision, delaySeconds) = _foldBasePolicies(router, ctx, decision, delaySeconds);
        if (!ok || decision == Decision.Revert) return (ok, decision, delaySeconds);

        (ok, decision, delaySeconds) = _foldAddonPolicies(router, ctx, decision, delaySeconds);
        return (ok, decision, delaySeconds);
    }

    function _foldBasePolicies(
        PolicyRouter router,
        EvalContext memory ctx,
        Decision currentDecision,
        uint48 currentDelay
    ) internal view returns (bool ok, Decision decision, uint48 delaySeconds) {
        decision = currentDecision;
        delaySeconds = currentDelay;

        uint256 baseCount = router.policyCount();
        for (uint256 i = 0; i < baseCount; i++) {
            address policy = address(router.policies(i));
            (ok, decision, delaySeconds) = _foldSinglePolicy(policy, ctx, decision, delaySeconds);
            if (!ok || decision == Decision.Revert) return (ok, decision, delaySeconds);
        }

        return (true, decision, delaySeconds);
    }

    function _foldAddonPolicies(
        PolicyRouter router,
        EvalContext memory ctx,
        Decision currentDecision,
        uint48 currentDelay
    ) internal view returns (bool ok, Decision decision, uint48 delaySeconds) {
        decision = currentDecision;
        delaySeconds = currentDelay;

        uint256 addonPackCount = router.addonPackCount();
        for (uint256 i = 0; i < addonPackCount; i++) {
            uint256 packId = router.enabledAddonPackAt(i);
            uint256 packPolicyCount = router.enabledAddonPolicyCount(packId);
            for (uint256 j = 0; j < packPolicyCount; j++) {
                address policy = router.enabledAddonPolicyAt(packId, j);
                (ok, decision, delaySeconds) = _foldSinglePolicy(policy, ctx, decision, delaySeconds);
                if (!ok || decision == Decision.Revert) return (ok, decision, delaySeconds);
            }
        }

        return (true, decision, delaySeconds);
    }

    function _foldSinglePolicy(
        address policy,
        EvalContext memory ctx,
        Decision currentDecision,
        uint48 currentDelay
    ) internal view returns (bool ok, Decision decision, uint48 delaySeconds) {
        (bool policyOk, Decision nextDecision, uint48 nextDelay) =
            _evalPolicy(policy, ctx.vault, ctx.to, ctx.value, ctx.data);
        if (!policyOk) {
            return (false, Decision.Revert, 0);
        }
        (decision, delaySeconds) = _fold(currentDecision, currentDelay, nextDecision, nextDelay);
        return (true, decision, delaySeconds);
    }

    function _evalRouter(PolicyRouter router, address vault, address to, uint256 value, bytes memory data)
        internal
        view
        returns (bool ok, Decision decision, uint48 delaySeconds)
    {
        try router.evaluate(vault, to, value, data) returns (Decision d, uint48 ds) {
            return (true, d, ds);
        } catch {
            return (false, Decision.Revert, 0);
        }
    }

    function _evalPolicy(address policy, address vault, address to, uint256 value, bytes memory data)
        internal
        view
        returns (bool ok, Decision decision, uint48 delaySeconds)
    {
        try IFirewallPolicy(policy).evaluate(vault, to, value, data) returns (Decision d, uint48 ds) {
            return (true, d, ds);
        } catch {
            return (false, Decision.Revert, 0);
        }
    }

    function _fold(Decision current, uint48 currentDelay, Decision next, uint48 nextDelay)
        internal
        pure
        returns (Decision finalDecision, uint48 maxDelay)
    {
        if (next == Decision.Revert) {
            return (Decision.Revert, 0);
        }

        finalDecision = current;
        maxDelay = currentDelay;
        if (next == Decision.Delay) {
            finalDecision = Decision.Delay;
            if (nextDelay > maxDelay) {
                maxDelay = nextDelay;
            }
        }
    }

    function _enableMask(PolicyRouter router, uint256 basePackId, uint8 mask) internal {
        if ((mask & 0x01) != 0) {
            if (basePackId == BASE_PACK_DEFI) {
                _enableAddonIfDisabled(router, ADDON_PACK_APPROVAL_HARDENING);
            }
        }
        if ((mask & 0x02) != 0) {
            _enableAddonIfDisabled(router, ADDON_PACK_NEW_RECEIVER_24H);
        }
        if ((mask & 0x04) != 0) {
            _enableAddonIfDisabled(router, ADDON_PACK_LARGE_TRANSFER_24H);
        }
    }

    function _enableAddonIfDisabled(PolicyRouter router, uint256 packId) internal {
        if (router.isAddonPackEnabled(packId)) return;
        _grantEntitlement(packId, true);
        router.enableAddonPack(packId);
    }
}
