// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

interface IERC4906 {
    event MetadataUpdate(uint256 _tokenId);

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}
