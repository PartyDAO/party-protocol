// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyBid is Implementation, PartyCrowdfund {
    struct PartyBidOptions {
        string name;
        string symbol;
        uint256 auctionId;
        IMarketWrapper market;
        IERC721 nftContract;
        uint256 nftTokenId;
        uint40 durationInSeconds;
        address payable splitRecipient;
        uint16 splitBps;
        Party.PartyOptions partyOptions;
        address initialDelegate;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    uint256 public nftTokenId;
    IERC721 public nftContract;
    uint40 public expiry;
    IGateKeeper public gateKeeper;
    bytes12 public gatkeeperId;
    IMarketWrapper public market;
    uint256 public highestBid;

    constructor(IGlobals globals) PartyCrowdfund(globals) {}

    function initialize(bytes calldata rawInitOpts)
        external
        override
        onlyDelegateCall
    {
        PartyBidOptions memory opts = abi.decode(rawInitOpts, (PartyBidOptions));
        PartyCrowdfund.initialize(CrowdfundInitOptions({
            name: opts.name,
            symbol: opts.symbol,
            partyOptions: opts.partyOptions,
            splitRecipient: opts.splitRecipient,
            splitBps: opts.splitBps,
            initialDelegate: opts.initialDelegate
        }));
        nftContract = opts.nftContract;
        nftTokenId = opts.nftTokenId;
        market = opts.market;
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
        expiry = uint40(opts.durationInSeconds + block.timestamp);
    }

    function contribute(address contributor, address delegate, bytes gateData)
        public
        override
        payable
    {
        if (gateKeeper != IGateKeeper(address(0))) {
            require(gateKeeper.isAllowed(contributor, gateKeeperId, gateData), 'NOT_ALLOWED');
        }
        PartyCrowdfund.contribute(contributor, delegate);
    }

    // Delegatecall into `market` to perform a bid.
    function bid() external {
        // ...
        highestBid = ...;
    }

    // Claim NFT and create a party if won or rescind bid if lost/expired.
    function finalize(Party.PartyOptions calldata partyOptions) external {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc == CrowdfundLifecycle.Won) {
            _createParty(partyOptions);
        } else if (lc == CrowdfundLifecycle.Lost) {
            // Rescind bid...
        }
        revert WrongLifecycleError(lc);
    }

    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // Note: cannot rely on ownerOf because it might be transferred to Party
        // if `createParty()` was called.
        // ...
    }

    function _transferSharedAssetsTo(address recipient) internal override {
        nftContract.transfer(recipient, nftTokenId);
    }

    function _getFinalPrice()
        internal
        override
        view
        returns (uint256 price)
    {
        return highestBid;
    }
}
