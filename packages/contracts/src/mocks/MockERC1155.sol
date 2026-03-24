// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC1155ReceiverMinimal {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

/// @notice Minimal ERC1155-like mock for receiver-hook tests.
contract MockERC1155 {
    mapping(uint256 => mapping(address => uint256)) public balanceOf;

    function mint(address to, uint256 id, uint256 amount) external {
        balanceOf[id][to] += amount;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data)
        external
    {
        require(balanceOf[id][from] >= amount, "NO_BALANCE");
        balanceOf[id][from] -= amount;
        balanceOf[id][to] += amount;

        if (to.code.length > 0) {
            bytes4 result =
                IERC1155ReceiverMinimal(to).onERC1155Received(msg.sender, from, id, amount, data);
            require(result == 0xf23a6e61, "UNSAFE_RECIPIENT");
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external {
        uint256 len = ids.length;
        require(len == amounts.length, "LENGTH_MISMATCH");
        for (uint256 i = 0; i < len; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            require(balanceOf[id][from] >= amount, "NO_BALANCE");
            balanceOf[id][from] -= amount;
            balanceOf[id][to] += amount;
        }

        if (to.code.length > 0) {
            bytes4 result =
                IERC1155ReceiverMinimal(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data);
            require(result == 0xbc197c81, "UNSAFE_RECIPIENT");
        }
    }
}
