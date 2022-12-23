// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./BuyCrowdfundBase.sol";

/// @notice A crowdfund that purchases any NFT from a collection (i.e., any
///         token ID) from a collection for a known price. Like `BuyCrowdfund`
///         but allows any token ID to be bought.
contract CollectionBuyCrowdfund is BuyCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    struct CollectionBuyCrowdfundOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // Customization preset ID to use for the crowdfund and governance NFTs.
        uint256 customizationPresetId;
        // The ERC721 contract of the NFT being bought.
        IERC721 nftContract;
        // How long this crowdfund has to buy the NFT, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for the NFT.
        uint96 maximumPrice;
        // An address that receives a portion of the final voting power
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
        // Minimum amount of ETH that can be contributed to this crowdfund per address.
        uint96 minContribution;
        // Maximum amount of ETH that can be contributed to this crowdfund per address.
        uint96 maxContribution;
        // The gatekeeper contract to use (if non-null) to restrict who can
        // contribute to this crowdfund.
        IGateKeeper gateKeeper;
        // The gate ID within the gateKeeper contract to use.
        bytes12 gateKeeperId;
        // Fixed governance options (i.e. cannot be changed) that the governance
        // `Party` will be created with if the crowdfund succeeds.
        FixedGovernanceOpts governanceOpts;
    }

    /// @notice The NFT contract to buy.
    IERC721 public nftContract;

    // Set the `Globals` contract.
    constructor(IGlobals globals) BuyCrowdfundBase(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function initialize(
        CollectionBuyCrowdfundOptions memory opts
    ) external payable onlyConstructor {
        if (opts.governanceOpts.hosts.length == 0) {
            revert MissingHostsError();
        }
        BuyCrowdfundBase._initialize(
            BuyCrowdfundBaseOptions({
                name: opts.name,
                symbol: opts.symbol,
                customizationPresetId: opts.customizationPresetId,
                duration: opts.duration,
                maximumPrice: opts.maximumPrice,
                splitRecipient: opts.splitRecipient,
                splitBps: opts.splitBps,
                initialContributor: opts.initialContributor,
                initialDelegate: opts.initialDelegate,
                minContribution: opts.minContribution,
                maxContribution: opts.maxContribution,
                gateKeeper: opts.gateKeeper,
                gateKeeperId: opts.gateKeeperId,
                governanceOpts: opts.governanceOpts
            })
        );
        nftContract = opts.nftContract;
    }

    /// @notice Execute arbitrary calldata to perform a buy, creating a party
    ///         if it successfully buys the NFT. Only a host may call this.
    /// @param tokenId The token ID of the NFT in the collection to buy.
    /// @param callTarget The target contract to call to buy the NFT.
    /// @param callValue The amount of ETH to send with the call.
    /// @param callData The calldata to execute.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the buy was successful.
    /// @param hostIndex This is the index of the caller in the `governanceOpts.hosts` array.
    /// @return party_ Address of the `Party` instance created after its bought.
    function buy(
        uint256 tokenId,
        address payable callTarget,
        uint96 callValue,
        bytes memory callData,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) external onlyDelegateCall returns (Party party_) {
        // This function is always restricted to hosts.
        _assertIsHost(msg.sender, governanceOpts, hostIndex);

        {
            // Ensure that the crowdfund is still active.
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Active) {
                revert WrongLifecycleError(lc);
            }
        }

        // Temporarily set to non-zero as a reentrancy guard.
        settledPrice = type(uint96).max;

        // Buy the NFT and check NFT is owned by the crowdfund.
        (bool success, bytes memory revertData) = _buy(
            nftContract,
            tokenId,
            callTarget,
            callValue,
            callData
        );

        if (!success) {
            if (revertData.length > 0) {
                revertData.rawRevert();
            } else {
                revert FailedToBuyNFTError(nftContract, tokenId);
            }
        }

        return
            _finalize(
                nftContract,
                tokenId,
                callValue,
                governanceOpts,
                // If `_assertIsHost()` succeeded, the governance opts were validated.
                true
            );
    }
}
