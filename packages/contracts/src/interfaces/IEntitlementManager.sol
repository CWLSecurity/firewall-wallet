// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IEntitlementManager {
    function isEntitled(address owner, uint256 packId) external view returns (bool);
}
