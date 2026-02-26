// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FirewallModule} from "./FirewallModule.sol";
import {PolicyRouter} from "./PolicyRouter.sol";

error Factory_ZeroAddress();
error Factory_ZeroPolicies();
error Factory_InvalidPreset(uint8 presetId);

/// @notice MVP deploy-based factory. No admin powers over wallets after creation.
contract FirewallFactory {
    address[] public policiesConservative;
    address[] public policiesDefi;

    event WalletCreated(
        address indexed owner,
        address indexed wallet,
        address indexed router,
        address recovery,
        uint8 presetId
    );

    constructor(address[] memory conservative_, address[] memory defi_) {
        _setPolicies(policiesConservative, conservative_);
        _setPolicies(policiesDefi, defi_);
    }

    function _setPolicies(address[] storage dst, address[] memory src) internal {
        if (src.length == 0) revert Factory_ZeroPolicies();
        for (uint256 i = 0; i < src.length; i++) {
            if (src[i] == address(0)) revert Factory_ZeroAddress();
            dst.push(src[i]);
        }
    }

    function createWallet(address owner, address recovery, uint8 presetId)
        external
        returns (address wallet)
    {
        if (owner == address(0)) revert Factory_ZeroAddress();
        if (recovery == address(0)) revert Factory_ZeroAddress();

        FirewallModule m = new FirewallModule();
        address[] storage src = _policiesForPreset(presetId);
        address[] memory policiesMem = new address[](src.length);
        for (uint256 i = 0; i < src.length; i++) {
            policiesMem[i] = src[i];
        }
        PolicyRouter router = new PolicyRouter(owner, address(m), policiesMem);
        m.init(address(router), owner, recovery);
        wallet = address(m);

        emit WalletCreated(owner, wallet, address(router), recovery, presetId);
    }

    function _policiesForPreset(uint8 presetId) internal view returns (address[] storage) {
        if (presetId == 0) return policiesConservative;
        if (presetId == 1) return policiesDefi;
        revert Factory_InvalidPreset(presetId);
    }
}
