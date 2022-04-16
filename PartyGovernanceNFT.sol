// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// ERC721 functionality built on top of PartyGovernance.
contract PartyGovernanceNFT is IERC721, PartyGovernance {
    address private immutable GLOBALS;
    IPartyFactory private immutable FACTORY;

    mapping (address => uint256) votingPowerByToken;

    constructor() {
        FACTORY = IPartyFactory(msg.sender);
        GLOBALS = FACTORY.GLOBALS();
    }

    function mint(address owner, uint256 amount, address delegate) external
    {
        require(msg.sender == FACTORY); // Only factory can mint.
        uint256 tokenId = _tokenCounter++;
        ownerOf[tokenId] = owner;
        votingPowerByToken[tokenId] = amount;
        _mintVotingPower(owner, amount, delegate);
        Transfer(address(0), owner, tokenId);
    }

    function transferFrom(address owner, address to, uint256 tokenId)
        public
    {
        // ...
        if (to != owner) {
            ownerOf[tokenId] = to;
            _transferVotingPower(owner, to);
            Transfer(owner, to, tokenId);
        }
    }

    function tokenURI(uint256 tokenId) external external /* view */ returns (string)
    {
        // TODO: force revert?
        (GLOBALS.getAddress(PARTY_NFT_RENDER_IMPL)).delegatecall(msg.data);
    }

    function _initialize(
        string name_,
        string symbol_,
        PartyGovernance.GovernanceOpts governanceOpts,
        uint128 totalVotingSupply
    )
        internal
    {
        string = string_;
        symbol = symbol_;
        PartyGovernance._initialize(governanceOpts, totalVotingSupply);
    }

    // ...
}