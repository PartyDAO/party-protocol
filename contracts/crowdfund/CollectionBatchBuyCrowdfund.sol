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

    struct BatchBuyArgs {
        uint256[] tokenIds;
        address payable[] callTargets;
        uint96[] callValues;
        bytes[] callDatas;
        bytes32[][] proofs;
        uint256 minTokensBought;
        uint256 minTotalEthUsed;
        FixedGovernanceOpts governanceOpts;
        uint256 hostIndex;
    }

    error NothingBoughtError();
    error InvalidMinTokensBoughtError(uint256 minTokensBought);
    error InvalidTokenIdError();
    error ContributionsSpentForFailedBuyError();
    error NotEnoughTokensBoughtError(uint256 tokensBought, uint256 minTokensBought);
    error NotEnoughEthUsedError(uint256 ethUsed, uint256 minTotalEthUsed);
    error MismatchedCallArgLengthsError();

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

        // Check length of all arg arrays.
        if (
            args.tokenIds.length != args.callTargets.length ||
            args.tokenIds.length != args.callValues.length ||
            args.tokenIds.length != args.callDatas.length ||
            args.tokenIds.length != args.proofs.length
        ) {
            revert MismatchedCallArgLengthsError();
        }

        // Temporarily set to non-zero as a reentrancy guard.
        settledPrice = type(uint96).max;

        uint96 totalEthUsed;
        uint256 tokensBought;
        IERC721[] memory tokens = new IERC721[](args.tokenIds.length);
        IERC721 token = nftContract;
        bytes32 root = nftTokenIdsMerkleRoot;
        for (uint256 i; i < args.tokenIds.length; ++i) {
            if (root != bytes32(0)) {
                // Verify the token ID is in the merkle tree.
                _verifyTokenId(args.tokenIds[i], root, args.proofs[i]);
            }

            // Used to ensure no ETH is spent if the call fails.
            uint256 balanceBefore = address(this).balance;

            // Execute the call to buy the NFT.
            (bool success, bytes memory revertData) = _buy(
                token,
                args.tokenIds[i],
                args.callTargets[i],
                args.callValues[i],
                args.callDatas[i]
            );

            if (!success) {
                if (args.minTokensBought >= args.tokenIds.length) {
                    // If the call failed with revert data, revert with that data.
                    if (revertData.length > 0) {
                        revertData.rawRevert();
                    } else {
                        revert FailedToBuyNFTError(token, args.tokenIds[i]);
                    }
                } else {
                    // If the call failed, ensure no ETH was spent and skip this NFT.
                    if (address(this).balance != balanceBefore) {
                        revert ContributionsSpentForFailedBuyError();
                    }

                    continue;
                }
            }

            totalEthUsed += args.callValues[i];

            ++tokensBought;
            tokens[tokensBought - 1] = token;
            args.tokenIds[tokensBought - 1] = args.tokenIds[i];
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
            mstore(0x1A0, tokensBought)
        }

        return
            _finalize(
                tokens,
                args.tokenIds,
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
