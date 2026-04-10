// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {FirewallModule} from "../src/FirewallModule.sol";

/// @notice One-shot queue relayer for scheduled Firewall Vault actions.
///         Intended to run in a loop (cron/systemd) during pilot stage.
contract RunQueueRelayer is Script {
    uint256 internal constant DEFAULT_SCAN_LIMIT = 128;

    struct BotConfig {
        uint256 relayerPrivateKey;
        address relayer;
    }

    function run() external {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        uint256 scanLimit = vm.envOr("QUEUE_SCAN_LIMIT", DEFAULT_SCAN_LIMIT);
        BotConfig memory cfg = _loadConfig();
        FirewallModule wallet = FirewallModule(payable(vaultAddress));
        bool relayerEnabled = wallet.isQueueExecutor(cfg.relayer);

        console2.log("vault", vaultAddress);
        console2.log("relayer", cfg.relayer);
        console2.log("relayerEnabled", relayerEnabled);
        if (!relayerEnabled) {
            console2.log("queue executor is not enabled for this vault; nothing to execute");
            return;
        }

        uint96 nextNonce = wallet.nextNonce();
        uint256 startNonce = uint256(nextNonce) > scanLimit ? uint256(nextNonce) - scanLimit : 0;

        uint256 executedCount = 0;
        console2.log("nextNonce", uint256(nextNonce));
        console2.log("scanStart", startNonce);

        for (uint256 nonce = startNonce; nonce < uint256(nextNonce); nonce++) {
            bool executed = _tryExecuteNonce(wallet, cfg, nonce);
            if (executed) {
                executedCount += 1;
            }
        }

        console2.log("executedCount", executedCount);
    }

    function _loadConfig() internal view returns (BotConfig memory cfg) {
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PK", uint256(0));
        cfg.relayerPrivateKey = vm.envOr("RELAYER_PRIVATE_KEY", deployerPrivateKey);
        require(cfg.relayerPrivateKey != 0, "RELAYER_PRIVATE_KEY missing");
        cfg.relayer = vm.addr(cfg.relayerPrivateKey);
    }

    function _tryExecuteNonce(FirewallModule wallet, BotConfig memory cfg, uint256 nonce)
        internal
        returns (bool)
    {
        bytes32 txId = wallet.scheduledTxIdByNonce(uint96(nonce));
        if (txId == bytes32(0)) return false;

        (bool exists, bool executed, , , uint48 unlockTime, ) = wallet.getScheduled(txId);
        if (!exists || executed || block.timestamp < unlockTime) return false;

        uint256 reserveWei = wallet.scheduledReserve(txId);
        if (reserveWei == 0) {
            console2.log("skip tx without reserved bot gas");
            console2.logBytes32(txId);
            return false;
        }

        bool success = false;
        vm.startBroadcast(cfg.relayerPrivateKey);
        try wallet.executeScheduledByExecutor(txId) {
            success = true;
        } catch Error(string memory reason) {
            console2.log("execute failed");
            console2.logBytes32(txId);
            console2.log(reason);
        } catch (bytes memory lowLevelData) {
            console2.log("execute failed (low-level)");
            console2.logBytes32(txId);
            console2.logBytes(lowLevelData);
        }
        vm.stopBroadcast();

        if (success) {
            console2.log("executed");
            console2.logBytes32(txId);
        }
        return success;
    }
}
