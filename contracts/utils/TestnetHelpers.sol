// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../party/Party.sol";
import "../tokens/ERC721Receiver.sol";

interface IWriteableToken is IERC721 {
  function lastTokenId() external returns (uint256); 
  function mintTo(address mintToAddress, string memory text) external;
}

contract TestnetHelpers is ERC721Receiver {
  function setupParty(
    IPartyFactory partyFactory,
    IWriteableToken writeableToken,
    Party.PartyOptions memory opts,
    address[] memory addresses,
    uint256[] memory amounts,
    string memory nftText
  ) public {
    require(addresses.length == amounts.length, "mismatched lengths");
    writeableToken.mintTo(address(this), nftText);
    uint256 tokenId = writeableToken.lastTokenId();

    IERC721[] memory erc721s = new IERC721[](1);
    erc721s[0] = writeableToken;

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    Party party = partyFactory.createParty(address(this), opts, erc721s, tokenIds);

    writeableToken.safeTransferFrom(address(this), address(party), tokenId);

    for (uint i=0; i<addresses.length; ++i) {
      partyFactory.mint(party, addresses[i], amounts[i], addresses[i]);
    }
  }
}
