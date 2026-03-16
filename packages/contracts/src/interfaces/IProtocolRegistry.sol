// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IProtocolRegistry {
    function resolveProtocol(address target) external view returns (bytes32 protocolId, bool active);
}
