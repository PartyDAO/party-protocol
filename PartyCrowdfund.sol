// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base contract for PartyBid/PartyBuy.
// Holds post-win/loss logic. E.g., burning contribution NFTs and creating a
// party after winning.
abstract contract PartyCrowdfund is PartyCrowdfundNFT {
    using LibRawResult for bytes;

    enum PartyLifecycle {
        Invalid,
        Active,
        Lost,
        Won
    }

    IGlobals public immutable GLOBALS;

    // The party instance created by `createParty()`, if any.
    Party public party;
    // Hash of PartyOptions passed into initialize().
    // The PartyOptions passed into `createParty()` must match.
    bytes32 public partyOptionsHash;
    mapping (address => address) delegationsByContributor;

    constructor(IGlobals globals) PartyCrowdfundNFT(globals) {
        GLOBALS = globals;
    }

    // Must be called once by freshly deployed PartyProxy instances.
    function initialize(string name, string symbol, bytes32 partyOptionsHash_)
        public
        override
    {
        PartyCrowdfundNFT.initialize(name, symbol);
        partyOptionsHash = partyOptionsHash_;
    }

    // Can be called after a party has won.
    // Deploys and initializes a a `Party` instance via the `PartyFactory`
    // and transfers the bought NFT to it.
    // After calling this, anyone can burn CF tokens on a contributor's behalf
    // with the `burn()` function.
    function createParty(Party.PartyOptions opts) external returns (Party party_) {
        require(_getPartyLifecycle() == PartyLifecycle.Won);
        require(party == Party(address(0)));
        require(_hashPartyOptions(opts) == partyOptionsHash);
        party = party_ =
            PartyFactory(GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY))
                .createParty(address(this), opts);
        _transferSharedAssetsTo(address(party_));
        emit PartyCreated(party_);
    }

    // Burns CF tokens owned by `owner` AFTER the CF has ended.
    // If the party has won, someone needs to call `createParty()` first. After
    // which, `burn()` will refund unused ETH and mint governance tokens for the
    // given `contributor`.
    // If the party has lost, this will only refund unused ETH (all of it) for
    // the given `contributor`.
    function burn(address contributor) public returns (uint256 ethRefunded) {
        Party party_ = _assertCanBurnAndReturnParty();
        return _burn(contributor);
    }

    // `burn()` in batch form.
    function batchBurn(address[] calldata contributors)
        external
        returns (uint256[] memory ethRefunded)
    {
        Party party_ = _assertCanBurnAndReturnParty();
        ethRefunded = new uint256[](contributors.length);
        for (uint256 i = 0; i < contributors.length; ++i) {
            ethRefunded[i] = burn(contributors[i]);
        }
    }

    function _getFinalContribution(address contributor)
        internal
        abstract
        returns (uint256 ethUsed, uint256 ethOwed);
    function _getPartyLifecycle() internal abstract view returns (PartyLifecycle);
    function _transferSharedAssetsTo(address recipient) internal abstract;

    function _burn(address payable contributor, Party party_)
        private
        returns (uint256 ethRefunded)
    {
        PartyCrowdfundNFT._burn(contributor);
        (uint256 ethUsed, uint256 ethOwed) = _getFinalContribution(contributor);
        if (party_ && ethUsed > 0) {
            party_.mint(
                party_,
                contributor,
                ethUsed,
                delegationsByContributor[contributor]
            );
        }
        _transferEth(contributor, ethOwed);
        ethRefunded = ethOwed;
    }

    // Assert that we are in a state that allows for burning CF tokens.
    function _assertCanBurnAndReturnParty() private view returns (Party party_) {
        PartyLifecycle lc = _getPartyLifecycle();
        require(uint8(lc) > uint8(PartyLifecycle.Active));
        party_ = party;
        require(lc == PartyLifecycle.Lost || party_);
    }

    function _transferEth(address payable to, uint256 amount)
        private
    {
        (bool s, bytes memory r) = to.call{ value: amount }(amount);
        if (!s) {
            r.rawRevert();
        }
    }
}
