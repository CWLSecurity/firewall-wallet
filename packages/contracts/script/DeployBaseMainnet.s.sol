// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {PolicyRouter} from "../src/PolicyRouter.sol";
import {FirewallModule} from "../src/FirewallModule.sol";

import {InfiniteApprovalPolicy} from "../src/policies/InfiniteApprovalPolicy.sol";
import {LargeTransferDelayPolicy} from "../src/policies/LargeTransferDelayPolicy.sol";
import {NewReceiverDelayPolicy} from "../src/policies/NewReceiverDelayPolicy.sol";
import {UnknownContractBlockPolicy} from "../src/policies/UnknownContractBlockPolicy.sol";

contract DeployBaseMainnet is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address owner = vm.envAddress("OWNER");
        address recovery = vm.envAddress("RECOVERY");

        vm.startBroadcast(pk);

        // 1) Deploy policies
        // InfiniteApprovalPolicy: constructor(uint256)
        InfiniteApprovalPolicy pApprove = new InfiniteApprovalPolicy(type(uint256).max);

        // Если компиляция скажет, что сигнатуры отличаются — поправим.
        LargeTransferDelayPolicy pLarge = new LargeTransferDelayPolicy(
            0.05 ether,
            3600
        );

        NewReceiverDelayPolicy pNew = new NewReceiverDelayPolicy(
            3600
        );

        // UnknownContractBlockPolicy: constructor(address)
        UnknownContractBlockPolicy pUnknown = new UnknownContractBlockPolicy(owner);

        // 2) Router (requires address[] in constructor)
        address[] memory arr = new address[](4) ;
        arr[0] = address(pApprove);
        arr[1] = address(pLarge);
        arr[2] = address(pNew);
        arr[3] = address(pUnknown);

        PolicyRouter router = new PolicyRouter(arr);

        // 3) Deploy firewall
        FirewallModule firewall = new FirewallModule();

        // 4) Init firewall
        firewall.init(address(router), owner, recovery);

        // 5) Bind router -> firewall
        router.setFirewallModule(address(firewall));

        vm.stopBroadcast();

        // 6) Save addresses
        string memory obj = "deploy";
        vm.serializeAddress(obj, "router", address(router));
        vm.serializeAddress(obj, "firewall", address(firewall));
        vm.serializeAddress(obj, "policy_infiniteApproval", address(pApprove));
        vm.serializeAddress(obj, "policy_largeTransferDelay", address(pLarge));
        vm.serializeAddress(obj, "policy_newReceiverDelay", address(pNew));
        vm.serializeAddress(obj, "policy_unknownContractBlock", address(pUnknown));
        string memory out = vm.serializeString(obj, "network", "base-mainnet");
        vm.writeJson(out, "deployments/base-mainnet.json");
    }
}
