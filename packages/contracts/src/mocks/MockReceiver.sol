// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Простейший получатель для тестов: принимает ETH и фиксирует параметры вызова.
contract MockReceiver {
    address public lastSender;
    uint256 public lastValue;
    bytes public lastData;
    uint256 public callCount;

    event Received(address indexed sender, uint256 value, bytes data);

    receive() external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = "";
        callCount++;
        emit Received(msg.sender, msg.value, "");
    }

    fallback() external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = msg.data;
        callCount++;
        emit Received(msg.sender, msg.value, msg.data);
    }

    function ping(uint256 x) external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        lastData = abi.encode(x);
        callCount++;
        emit Received(msg.sender, msg.value, abi.encode(x));
    }
}
