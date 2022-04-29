// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// ERC721 functionality built on top of PartyGovernance.
contract PartyGovernanceNFT is
    IWeighedERC721,
    PartyGovernance,
    ReadOnlyDelegateCall
{
    address private immutable GLOBALS;
    IPartyFactory private immutable FACTORY;

    constructor() {
        FACTORY = IPartyFactory(msg.sender);
        GLOBALS = FACTORY.GLOBALS();
    }

    // Initialize storage for proxy contracts.
    function initialize(
        string name_,
        string symbol_,
        PartyGovernance.GovernanceOpts governanceOpts
    )
        public
        override
    {
        PartyGovernance.initialize(governanceOpts);
        string = string_;
        symbol = symbol_;
    }

    // Mint a governance NFT for `owner` with `votingPower` and
    // immediately delegate voting power to `delegate.`
    function mint(address owner, uint256 votingPower, address delegate) external
    {
        require(msg.sender == FACTORY); // Only factory can mint.
        uint256 tokenId = _tokenCounter++;
        ownerOf[tokenId] = owner;
        _mintVotingPower(owner, votingPower, delegate);
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
        // An instance of IERC721Renderer
        _readOnlyDelegateCall(
            GLOBALS.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL),
            msg.data
        );
    }

    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return getVotingPowerAt(tokenId, block.timstamp) * 1e18
            / governanceOpts.totalGovernanceSupply;
    }

    // other 721 fns...
}
