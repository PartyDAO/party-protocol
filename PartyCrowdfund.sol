// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base contract for PartyBid/PartyBuy.
// Holds post-win/loss logic. E.g., burning contribution NFTs and creating a
// party after winning.
abstract contract PartyCrowdfund is PartyCrowdfundNFT {
    enum PartyLifecycle {
        Invalid,
        Active,
        Lost,
        Won
    }

    address private immutable GLOBALS;
    Party public party;
    bytes32 public partyOptionsHash;
    mapping (address => address) delegationsByContributor;

    constructor(IGlobals globals) PartyCrowdfundNFT(globals) {
        GLOBALS = globals;
    }

    function createParty(Party.PartyOptions opts) external returns (Party party_) {
        require(_getPartyLifecycle() == PartyLifecycle.Won);
        require(party == Party(address(0)));
        require(_hashPartyOptions(opts) == partyOptionsHash);
        party = party_ = PartyFactory(GLOBALS.getAddress(PARTY_FACTORY_IMPL))
            .createParty(address(this), opts);
        _transferSharedAssetsTo(address(party));
        emit PartyCreated(party);
    }
    // Burns CF tokens owned by `owner` AFTER the CF has ended.
    // If the party has won, this will also mint governance tokens in the Party
    // contract.
    function burn(address contributor) external returns (uint256 ethRedeemed) {
        require(ownerOf[contributor] != address(0));
        PartyLifecycle lc = _getPartyLifecycle();
        require(uint8(lc) > uint8(PartyLifecycle.Active));
        Party party_ = party;
        require(lc == PartyLifecycle.Lost || party_);
        _burn(contributor); // Burn NFT
        (uint256 ethUsed, uint256 ethOwed) = _getFinalContribution(contributor);
        if (party_ && ethUsed > 0) {
            party_.mint(party, contributor, ethUsed, delegationsByContributor[contributor]);
        }
        _transferEth(contributor, ethOwed);
        ethRedeemed = ethOwed;
    }
    function batchBurn(address[] calldata contributors) external returns (uint256[] memory ethRedeemed);

    function _initialize(string name, string symbol, bytes32 partyOptionsHash_) internal {
        PartyCrowdfundNFT._initialize(name, symbol);
        partyOptionsHash = partyOptionsHash_;
    }
    function _getFinalContribution(address contributor) internal abstract returns (uint256);
    function _getPartyLifecycle() internal abstract view returns (PartyLifecycle);
    function _transferSharedAssetsTo(address recipient) internal abstract;
}