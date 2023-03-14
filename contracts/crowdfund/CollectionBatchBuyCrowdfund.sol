// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";
import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./BuyCrowdfundBase.sol";

contract CollectionBatchBuyCrowdfund is BuyCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    struct CollectionBatchBuyCrowdfundOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // Customization preset ID to use for the crowdfund and governance NFTs.
        uint256 customizationPresetId;
        // The ERC721 contract of the NFTs being bought.
        IERC721 nftContract;
        // The merkle root of the token IDs that can be bought. If null, any
        // token ID in the collection can be bought.
        bytes32 nftTokenIdsMerkleRoot;
        // How long this crowdfund has to buy the NFTs, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for an NFT.
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

    struct TokenToBuy {
        // The token ID of the NFT to buy.
        uint256 tokenId;
        // The price of the token. This cannot be greater than `maximumPrice`.
        uint96 price;
        // The proof needed to verify that the token ID is included in the
        // `nftTokenIdsMerkleRoot` (if it is not null).
        bytes32[] proof;
    }

    struct BuyCall {
        // The contract to call to buy the NFTs in `tokensToBuy`.
        address payable target;
        // The calldata to call `target` with to buy the NFTs in `tokensToBuy`.
        bytes data;
        // The tokens to try buying with this call.
        TokenToBuy[] tokensToBuy;
    }

    struct BatchBuyArgs {
        // The calls made to buy the NFTs. Each call has a target, data, and
        // the tokens to buy in that call.
        BuyCall[] calls;
        // The total number of tokens that can be bought in this batch buy. This
        // should be equal to the sum of the each `tokensToBuy` in `calls`.
        uint256 numOfTokens;
        // Minimum number of tokens that must be purchased. If this limit is
        // not reached, the batch buy will fail.
        uint256 minTokensBought;
        // Minimum amount of ETH that must be used to buy the tokens. If this
        // amount is not reached, the batch buy will fail.
        uint256 minTotalEthUsed;
        // These are the governance options that will be used to create the
        // governance `Party` if the crowdfund is successful. Additionally, they
        // are used to verify that the caller is a host.
        FixedGovernanceOpts governanceOpts;
        // The index of the host in `governanceOpts.hosts` that is making this
        // batch buy. This is used to verify that the caller is a host.
        uint256 hostIndex;
    }

    error NothingBoughtError();
    error InvalidMinTokensBoughtError(uint256 minTokensBought);
    error InvalidTokenIdError();
    error EthUsedForFailedBuyError(uint256 expectedEthUsed, uint256 actualEthUsed);
    error NotEnoughTokensBoughtError(uint256 tokensBought, uint256 minTokensBought);
    error NotEnoughEthUsedError(uint256 ethUsed, uint256 minTotalEthUsed);
    error NumOfTokensCannotBeLessThanMin(uint256 numOfTokens, uint256 min);

    /// @notice The contract of NFTs to buy.
    IERC721 public nftContract;
    /// @notice The merkle root of the token IDs that can be bought. If null,
    ///         allow any token ID in the collection can be bought.
    bytes32 public nftTokenIdsMerkleRoot;

    // Set the `Globals` contract.
    constructor(IGlobals globals) BuyCrowdfundBase(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function initialize(
        CollectionBatchBuyCrowdfundOptions memory opts
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
        nftTokenIdsMerkleRoot = opts.nftTokenIdsMerkleRoot;
    }

    /// @notice Execute arbitrary calldata to perform a batch buy, creating a party
    ///         if it successfully buys the NFT. Only a host may call this.
    /// @param args Arguments for the batch buy.
    /// @return party_ Address of the `Party` instance created after its bought.
    function batchBuy(BatchBuyArgs memory args) external onlyDelegateCall returns (Party party_) {
        // This function is restricted to hosts.
        _assertIsHost(msg.sender, args.governanceOpts, args.hostIndex);

        {
            // Ensure that the crowdfund is still active.
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Active) {
                revert WrongLifecycleError(lc);
            }
        }

        if (args.minTokensBought == 0) {
            // Must buy at least one token.
            revert InvalidMinTokensBoughtError(0);
        }

        if (args.numOfTokens < args.minTokensBought) {
            // The number of tokens to buy must be greater than or equal to the
            // minimum number of tokens to buy.
            revert NumOfTokensCannotBeLessThanMin(args.numOfTokens, args.minTokensBought);
        }

        // Temporarily set to non-zero as a reentrancy guard.
        settledPrice = type(uint96).max;

        // Lengths of arrays are updated at the end.
        IERC721[] memory tokens = new IERC721[](args.numOfTokens);
        uint256[] memory tokenIds = new uint256[](args.numOfTokens);

        IERC721 token = nftContract;
        bytes32 root = nftTokenIdsMerkleRoot;
        uint96 maxPrice = maximumPrice;
        uint96 totalEthUsed;
        uint256 tokensBought;
        for (uint256 i; i < args.calls.length; ++i) {
            BuyCall memory call = args.calls[i];

            uint96 callValue;
            for (uint256 j; j < call.tokensToBuy.length; ++j) {
                TokenToBuy memory tokenToBuy = call.tokensToBuy[j];

                if (root != bytes32(0)) {
                    // Verify the token ID is in the merkle tree.
                    _verifyTokenId(tokenToBuy.tokenId, root, tokenToBuy.proof);
                }

                // Check that the call value is under the maximum price.
                uint96 price = tokenToBuy.price;
                if (price > maxPrice) {
                    revert MaximumPriceError(price, maxPrice);
                }

                // Add the price to the total value used for the call.
                callValue += price;
            }

            uint256 balanceBefore = address(this).balance;
            {
                // Execute the call to buy the NFT.
                (bool success, ) = _buy(token, call.target, callValue, call.data);

                if (!success) continue;
            }

            {
                uint96 ethUsed;
                for (uint256 j; j < call.tokensToBuy.length; ++j) {
                    uint256 tokenId = call.tokensToBuy[j].tokenId;
                    uint96 price = call.tokensToBuy[j].price;

                    // Check whether the NFT was successfully bought.
                    if (token.safeOwnerOf(tokenId) == address(this)) {
                        ethUsed += price;
                        ++tokensBought;

                        // Add the token to the list of tokens to finalize.
                        tokens[tokensBought - 1] = token;
                        tokenIds[tokensBought - 1] = tokenId;
                    }
                }

                // Check ETH spent for call is what was expected.
                uint256 actualEthUsed = balanceBefore - address(this).balance;
                if (ethUsed != actualEthUsed) {
                    revert EthUsedForFailedBuyError(ethUsed, actualEthUsed);
                }

                totalEthUsed += ethUsed;
            }
        }

        // This is to prevent this crowdfund from finalizing a loss if nothing
        // was attempted to be bought (ie. `tokenIds` is empty) or all NFTs were
        // bought for free.
        if (totalEthUsed == 0) revert NothingBoughtError();

        // Check number of tokens bought is not less than the minimum.
        if (tokensBought < args.minTokensBought) {
            revert NotEnoughTokensBoughtError(tokensBought, args.minTokensBought);
        }

        // Check total ETH used is not less than the minimum.
        if (totalEthUsed < args.minTotalEthUsed) {
            revert NotEnoughEthUsedError(totalEthUsed, args.minTotalEthUsed);
        }

        assembly {
            // Update length of `tokens`
            mstore(tokens, tokensBought)
            // Update length of `tokenIds`
            mstore(tokenIds, tokensBought)
        }

        return
            _finalize(
                tokens,
                tokenIds,
                totalEthUsed,
                args.governanceOpts,
                // If `_assertIsHost()` succeeded, the governance opts were validated.
                true
            );
    }

    function _verifyTokenId(uint256 tokenId, bytes32 root, bytes32[] memory proof) private pure {
        bytes32 leaf;
        assembly {
            mstore(0x00, tokenId)
            leaf := keccak256(0x00, 0x20)
        }

        if (!MerkleProof.verify(proof, root, leaf)) revert InvalidTokenIdError();
    }
}
