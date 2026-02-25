// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FirewallModule} from "./FirewallModule.sol";
import {PolicyRouter} from "./PolicyRouter.sol";

error Factory_ZeroAddress();
error Factory_ZeroPolicies();

/// @notice MVP deploy-based factory. No admin powers over wallets after creation.
contract FirewallFactory {
    address[] public policies;

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery
    );

    constructor(address[] memory policies_) {
        if (policies_.length == 0) revert Factory_ZeroPolicies();
        for (uint256 i = 0; i < policies_.length; i++) {
            if (policies_[i] == address(0)) revert Factory_ZeroAddress();
            policies.push(policies_[i]);
        }
    }

    function createWallet(address owner, address recovery) external returns (address wallet) {
        if (owner == address(0)) revert Factory_ZeroAddress();
        if (recovery == address(0)) revert Factory_ZeroAddress();

        FirewallModule m = new FirewallModule();
        address[] memory policiesMem = new address[](policies.length);
        for (uint256 i = 0; i < policies.length; i++) {
            policiesMem[i] = policies[i];
        }
        PolicyRouter router = new PolicyRouter(owner, address(m), policiesMem);
        m.init(address(router), owner, recovery);
        wallet = address(m);

        emit WalletCreated(owner, wallet, address(router), recovery);
    }
}
