pragma solidity ^0.8;

// SPDX-License-Identifier: Apache-2.0
import "./IERC721.sol";


interface IERC4907 is IERC721 {
    // does this event needed?
    event UserChanged(uint256 indexed tokenId, address indexed user, uint64 expires);

    function userOf(uint256 tokenId) external view returns (address user, uint64 expires);

    function setUser(uint256 tokenId, address user, uint64 expires) external;
}
