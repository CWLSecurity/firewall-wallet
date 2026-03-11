// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {FirewallFactory} from "../src/FirewallFactory.sol";
import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";

contract DeployFactoryBaseMainnet is Script {
    function run() external returns (FirewallFactory factory) {
        vm.startBroadcast();
        // NOTE: Default presets exclude UnknownContractBlockPolicy (centralized allowlist).
        InfiniteApprovalPolicy conservativeApprove = new InfiniteApprovalPolicy(type(uint256).max, false);
        InfiniteApprovalPolicy defiApprove = new InfiniteApprovalPolicy(type(uint256).max, true);

        address[] memory conservative = new address[](3);
        conservative[0] = address(conservativeApprove); // InfiniteApprovalPolicy (permit blocked, stricter)
        conservative[1] = 0x2eE727528bCCEF98F765Ccd0C66bFfcFd4E7e06B; // LargeTransferDelayPolicy
        conservative[2] = 0x2013080Ce5ceaf2a232dB3e2bCDd2dd9312A55E4; // NewReceiverDelayPolicy

        address[] memory defi = new address[](3);
        defi[0] = address(defiApprove); // InfiniteApprovalPolicy (permit allowed, less strict)
        defi[1] = 0x2eE727528bCCEF98F765Ccd0C66bFfcFd4E7e06B; // LargeTransferDelayPolicy
        defi[2] = 0x2013080Ce5ceaf2a232dB3e2bCDd2dd9312A55E4; // NewReceiverDelayPolicy

        factory = new FirewallFactory(conservative, defi);
        vm.stopBroadcast();
    }
}
