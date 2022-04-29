// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyBuy is IPartyBuyV1, Implementation, PartyCrowdfund {
    struct Split {
        address recipient;
        uint16 splitBps;
    }

    struct PartyBuyOptions {
        uint256 tokenId;
        IERC721 nftContract;
        uint128 maxPrice;
        uint32 duratiomInSeconds;
        address splitRecipient;
        uint32 splitBps; // TODO: needed? propagate to party?
        string name;
        string symbol;
        bytes32 partyOptionsHash;
    }

    // ...

    constructor(IGlobals globals) PartyCrowdfund(globals) { }

    function initialize(bytes calldata rawInitOpts, address deployer)
        external
        override
        onlyDelegateCall
    {
        PartyBuyOptions memory opts = abi.decode(rawInitOpts, (PartyBuyOptions));
        PartyCrowdfund._initialize(opts.name, opts.symbol, opts.partyOptionsHash);
        // ...
        // If the deployer passed in some ETH during deployment, credit them.
        uint256 initialBalance = address(this).balance;
        if (initialBalance > 0) {
            _addContribution(deployer, initialBalance);
        }
    }

    function _transferSharedAssetsTo(address recipient) internal override {
        nftContract.transfer(recipient, boughtTokenId);
    }

    function _getPartyLifecycle() internal override view returns (PartyLifecycle) {
        // Note: cannot rely on ownerOf because it might be transferred to Party
        // if `createParty()` was called.
        if (boughtTokenId == tokenId) {
            return PartyLifecycle.Won;
        }
        // ...
    }

    function _getFinalContribution(address contributor)
        internal
        override
        view
        returns (uint256 ethUsed, uint256 ethOwed)
    {
        // Loop throough `contributor`'s contributions and return
        // how much was actually used and how much was not.
    }

    // Rest of PartyBuyV1 functions...
}
