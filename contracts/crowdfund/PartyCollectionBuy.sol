// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./PartyBuyBase.sol";

// PartyBuy but allows any token ID to be bought.
contract PartyCollectionBuy is PartyBuyBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;

    error OnlyPartyHostError();

    struct PartyCollectionBuyOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // The ERC721 contract of the NFT being bought.
        IERC721 nftContract;
        // How long this crowdfund has to bid on the NFT, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for the NFT.
        // If zero, no maximum.
        uint96 maximumPrice;
        // An address that receieves a portion of the final voting power
        // when the party transitions into governance.
        address payable splitRecipient;
        // What percentage (in bps) of the final total voting power `splitRecipient`
        // receives.
        uint16 splitBps;
        // If ETH is attached during deployment, it will be interpreted
        // as a contribution. This is who gets credit for that contribution.
        address initialContributor;
        // If there is an initial contribution, this is who they will delegate their
        // voting power to when the crowdfund transitions to governance.
        address initialDelegate;
        // The gatekeeper contract to use (if non-null) to restrict who can
        // contribute to this crowdfund.
        IGateKeeper gateKeeper;
        // The gate ID within the gateKeeper contract to use.
        bytes12 gateKeeperId;
        // Governance options.
        FixedGovernanceOpts governanceOpts;
    }

    /// @notice The NFT contract to buy.
    IERC721 public nftContract;

    modifier onlyHost(address[] memory hosts) {
        bool isHost;
        for (uint256 i; i < hosts.length; i++) {
            if (hosts[i] == msg.sender) {
                isHost = true;
                break;
            }
        }

        if (!isHost) {
            revert OnlyPartyHostError();
        }

        _;
    }

    constructor(IGlobals globals) PartyBuyBase(globals) {}

    /// @notice intializer to be delegatecalled by Proxy constructor.
    function initialize(PartyCollectionBuyOptions memory opts)
        external
        payable
        onlyConstructor
    {
        PartyBuyBase._initialize(PartyBuyBaseOptions({
            name: opts.name,
            symbol: opts.symbol,
            duration: opts.duration,
            maximumPrice: opts.maximumPrice,
            splitRecipient: opts.splitRecipient,
            splitBps: opts.splitBps,
            initialContributor: opts.initialContributor,
            initialDelegate: opts.initialDelegate,
            gateKeeper: opts.gateKeeper,
            gateKeeperId: opts.gateKeeperId,
            governanceOpts: opts.governanceOpts
        }));
        nftContract = opts.nftContract;
    }

    /// @notice Execute arbitrary calldata to perform a buy, creating a party
    ///         if it successfully buys the NFT.
    function buy(
        uint256 tokenId,
        address payable callTarget,
        uint96 callValue,
        bytes calldata callData,
        FixedGovernanceOpts memory governanceOpts
    )
        external
        onlyHost(governanceOpts.hosts)
        returns (Party party_)
    {
        return _buy(
            nftContract,
            tokenId,
            callTarget,
            callValue,
            callData,
            governanceOpts
        );
    }
}
