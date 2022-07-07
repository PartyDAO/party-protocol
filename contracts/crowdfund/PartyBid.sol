// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./IMarketWrapper.sol";
import "./PartyCrowdfund.sol";

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
        address initialContributor;
        address initialDelegate;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    uint256 public nftTokenId;
    IERC721 public nftContract;
    uint40 public expiry;
    IGateKeeper public gateKeeper;
    bytes12 public gateKeeperId;
    IMarketWrapper public market;
    uint256 public highestBid;

    constructor(IGlobals globals) PartyCrowdfund(globals) {}

    function initialize(PartyBidOptions memory initOpts)
        external
        onlyDelegateCall
    {
        PartyCrowdfund._initialize(CrowdfundInitOptions({
            name: initOpts.name,
            symbol: initOpts.symbol,
            partyOptions: initOpts.partyOptions,
            splitRecipient: initOpts.splitRecipient,
            splitBps: initOpts.splitBps,
            initialContributor: initOpts.initialContributor,
            initialDelegate: initOpts.initialDelegate
        }));
        nftContract = initOpts.nftContract;
        nftTokenId = initOpts.nftTokenId;
        market = initOpts.market;
        gateKeeper = initOpts.gateKeeper;
        gateKeeperId = initOpts.gateKeeperId;
        expiry = uint40(initOpts.durationInSeconds + block.timestamp);
    }

    function contribute(address contributor, address delegate, bytes memory gateData)
        public
        payable
    {
        if (gateKeeper != IGateKeeper(address(0))) {
            require(gateKeeper.isAllowed(contributor, gateKeeperId, gateData), 'NOT_ALLOWED');
        }
        PartyCrowdfund.contribute(contributor, delegate);
    }

    // Delegatecall into `market` to perform a bid.
    function bid() external pure {
        // ...
        // highestBid = ...;
        revert('not implemented');
    }

    // Claim NFT and create a party if won or rescind bid if lost/expired.
    function finalize(Party.PartyOptions calldata partyOptions) external {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc == CrowdfundLifecycle.Won) {
            _createParty(partyOptions, nftContract, nftTokenId);
        } else if (lc == CrowdfundLifecycle.Lost) {
            // Rescind bid...
        }
        revert WrongLifecycleError(lc);
    }

    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // Note: cannot rely on ownerOf because it might be transferred to Party
        // if `createParty()` was called.
        // ...
        revert('not implemented');
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
