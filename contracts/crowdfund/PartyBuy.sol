// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./IMarketWrapper.sol";
import "./PartyCrowdfund.sol";

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
        Party.PartyOptions partyOptions;
        address initialContributor;
        address initialDelegate;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    uint256 public nftTokenId;
    IERC721 public nftContract;
    uint40 public expiry;
    uint256 public price;
    uint256 public settledPrice;
    IGateKeeper public gateKeeper;
    bytes12 public gateKeeperId;

    constructor(IGlobals globals) PartyCrowdfund(globals) {}

    function initialize(PartyBuyOptions memory initOpts)
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
        price = initOpts.price;
        nftContract = initOpts.nftContract;
        nftTokenId = initOpts.nftTokenId;
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

    // execute calldata to perform a buy.
    function buy(
        address payable callTarget,
        uint256 callValue,
        bytes calldata callData,
        Party.PartyOptions calldata partyOptions
    )
        external
    {
        require(getCrowdfundLifecycle() == CrowdfundLifecycle.Active);
        settledPrice = callValue;
        // Do we even care whether it succeeds?
        callTarget.call{ value: callValue }(callData);
        finalize(partyOptions);
    }

    // Create a party if the party has won or somehow managed to acquire the
    // NFT.
    // TODO: Figure out what to do if the NFT
    // is manually transferred instead of being bought (no ETH was spent).
    // Should we just set the price to the total contributions?
    function finalize(Party.PartyOptions memory partyOptions) public {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Won) {
            revert WrongLifecycleError(lc);
        }
        _createParty(partyOptions, nftContract, nftTokenId); // Will revert if already created.
    }

    // TODO: Can we avoid needing these functions/steps?
    // function expire() ...

    // TODO: War-game losing then someone transferring the NFT in after
    // some people have already burned their tokens. Might need explicit state
    // tracking.
    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // If there is a settled price then we tried to buy the NFT.
        if (settledPrice != 0) {
            // If there's a party, we will no longer hold the NFT, but it means we
            // did at one point.
            if (_getParty() != Party(payable(address(0)))) {
                return CrowdfundLifecycle.Won;
            }
            // Otherwise check if we hold the NFT now.
            try
                nftContract.ownerOf(nftTokenId) returns (address owner)
            {
                // We hold the token so we must have won.
                if (owner == address(this)) {
                    return CrowdfundLifecycle.Won;
                }
            } catch {}
            // We can get here if the arbitrary call in buy() fails
            // to acquire the NFT, then it calls finalize().
            // This is an invalid state so we want to revert the buy().
            revert();
        }
        if (expiry <= uint40(block.timestamp)) {
            return CrowdfundLifecycle.Lost;
        }
        return CrowdfundLifecycle.Active;
    }

    function _getFinalPrice()
        internal
        override
        view
        returns (uint256)
    {
        return settledPrice;
    }
}
