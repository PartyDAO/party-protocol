// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../contracts/distribution/ITokenDistributorParty.sol";

contract DummyTokenDistributorParty is ITokenDistributorParty {
    mapping(uint256 => address) private _owners;
    mapping(uint256 => uint256) private _shares; // token id -> share amount

    function setOwner(address owner, uint256 tokenId) public {
        _owners[tokenId] = owner;
    }

    function setShare(uint256 tokenId, uint256 shareAmount) public {
        _shares[tokenId] = shareAmount;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address foundOwner = _owners[tokenId];
        if (foundOwner == address(0)) {
            revert();
        }
        return foundOwner;
    }

    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return _shares[tokenId];
    }
}
