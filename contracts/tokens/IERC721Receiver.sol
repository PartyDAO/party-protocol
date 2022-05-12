// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

interface IERC721Receiver {

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
