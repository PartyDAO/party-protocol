// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyBuy is Implementation, PartyCrowdfund {
    struct PartyBuyOptions {
        string name;
        string symbol;
        uint256 nftTokenId;
        IERC721 nftContract;
        uint256 price;
        uint40 durationInSeconds;
        address payable splitRecipient;
        uint16 splitBps;
        bytes32 partyOptionsHash;
        address initialDelegate;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperData;
    }

    uint256 public nftTokenId;
    IERC721 public nftContract;
    uint40 public expiry;
    uint256 public price;
    IGateKeeper public gateKeeper;
    bytes12 public gateKeeperData;

    constructor(IGlobals globals) PartyCrowdfund(globals) {}

    function initialize(bytes calldata rawInitOpts)
        external
        override
        onlyDelegateCall
    {
        PartyBuyOptions memory opts = abi.decode(rawInitOpts, (PartyBuyOptions));
        PartyCrowdfund.initialize(CrowdfundInitOptions({
            name: opts.name,
            symbol: opts.symbol,
            partyOptionsHash: opts.partyOptionsHash,
            splitRecipient: opts.splitRecipient,
            splitBps: opts.splitBps,
            initialDelegate: opts.initialDelegate
        }));
        price = opts.price;
        nftContract = opts.nftContract;
        nftTokenId = opts.nftTokenId;
        gateKeeper = opts.gateKeeper;
        gateKeeperData = opts.gateKeeperData;
        expiry = uint40(opts.durationInSeconds + block.timestamp);
    }

    function contribute(address contributor, address delegate)
        public
        override
        payable
    {
        if (gateKeeper != IGateKeeper(address(0))) {
            require(gateKeeper.isAllowed(contributor, gateKeeperData), 'NOT_ALLOWED');
        }
        PartyCrowdfund.contribute(contributor, delegate);
    }

    // execute calldata to perform a buy.
    function buy(
        address payable calltarget,
        uint256 callvalue,
        bytes calldata calldata,
        Party.PartyOptions calldata partyOptions
    )
        external
    {
        // ...
        finalize(partyOptions);
    }

    // Create a party if the party has won or somehow managed to acquire the
    // NFT.
    function finalize(Party.PartyOptions memory partyOptions) public {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Won) {
            revert WrongLifecycleError(lc);
        }
        _createParty(partyOptions); // Will revert if already created.
    }

    // TODO: Can we avoid needing these functions/steps?
    // function expire() ...

    // TODO: War-game losing then someone transferring the NFT in after
    // some people have already burned their tokens. Might need explicit state
    // tracking.
    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // If there's a party, we will no longer hold the NFT, but it means we
        // did at one point.
        if (_getParty() != Party(address(0))) {
            return CrowdfundLifecycle.Won;
        }
        try
            nftContract.ownerOf(nftTokenId) returns (address owner)
        {
            // We hold the token so we must have won.
            if (owner == address(this)) {
                return CrowdfundLifecycle.Won;
            }
        } catch {}
        if (expiry <= uint40(block.timestamp)) {
            return CrowdfundLifecycle.Lost;
        }
        return CrowdfundLifecycle.Active;
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
        return price;
    }
}
