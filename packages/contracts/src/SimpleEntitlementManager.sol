// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IEntitlementManager} from "./interfaces/IEntitlementManager.sol";

error Entitlement_Unauthorized();
error Entitlement_ZeroAddress();

/// @notice Minimal on-chain entitlement manager hook for curated add-on packs.
///         No payment/billing logic is included.
contract SimpleEntitlementManager is IEntitlementManager {
    address public owner;
    mapping(address => mapping(uint256 => bool)) public entitlements;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EntitlementSet(address indexed account, uint256 indexed packId, bool entitled);

    constructor(address owner_) {
        if (owner_ == address(0)) revert Entitlement_ZeroAddress();
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Entitlement_Unauthorized();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Entitlement_ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function setEntitlement(address account, uint256 packId, bool entitled) external onlyOwner {
        if (account == address(0)) revert Entitlement_ZeroAddress();
        entitlements[account][packId] = entitled;
        emit EntitlementSet(account, packId, entitled);
    }

    function isEntitled(address account, uint256 packId) external view returns (bool) {
        return entitlements[account][packId];
    }
}
