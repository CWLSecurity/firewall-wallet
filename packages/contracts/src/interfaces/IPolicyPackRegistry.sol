// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPolicyPackRegistry {
    function isPackActive(uint256 packId) external view returns (bool);
    function packTypeOf(uint256 packId) external view returns (uint8);
    function getPackPolicies(uint256 packId) external view returns (address[] memory);
}
