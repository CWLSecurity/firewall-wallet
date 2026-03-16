// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPolicyPackRegistry {
    function isPackActive(uint256 packId) external view returns (bool);
    function packTypeOf(uint256 packId) external view returns (uint8);
    function getPackPolicies(uint256 packId) external view returns (address[] memory);
    function packCount() external view returns (uint256);
    function packIdAt(uint256 index) external view returns (uint256);
    function getPackMeta(uint256 packId)
        external
        view
        returns (
            bool active,
            uint8 packType,
            bytes32 metadata,
            string memory slug,
            uint16 version,
            uint256 policyCount
        );
}
