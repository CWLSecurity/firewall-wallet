// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {FirewallFactory} from "../src/FirewallFactory.sol";

contract DeployFactoryBaseMainnet is Script {
    function run() external returns (FirewallFactory factory) {
        vm.startBroadcast();
        // NOTE: Default preset excludes UnknownContractBlockPolicy (centralized allowlist).
        address[] memory policies = new address[](3);
        policies[0] = 0xA9891C83eaf199845aDf70D060a8363f9A79D22f; // InfiniteApprovalPolicy
        policies[1] = 0x2eE727528bCCEF98F765Ccd0C66bFfcFd4E7e06B; // LargeTransferDelayPolicy
        policies[2] = 0x2013080Ce5ceaf2a232dB3e2bCDd2dd9312A55E4; // NewReceiverDelayPolicy
        factory = new FirewallFactory(policies);
        vm.stopBroadcast();
    }
}
