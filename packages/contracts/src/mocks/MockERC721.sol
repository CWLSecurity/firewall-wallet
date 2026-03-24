// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC721ReceiverMinimal {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/// @notice Minimal ERC721-like mock for receiver-hook tests.
contract MockERC721 {
    mapping(uint256 => address) public ownerOf;

    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(ownerOf[tokenId] == from, "NOT_OWNER");
        ownerOf[tokenId] = to;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            bytes4 result =
                IERC721ReceiverMinimal(to).onERC721Received(msg.sender, from, tokenId, data);
            require(result == 0x150b7a02, "UNSAFE_RECIPIENT");
        }
    }
}
