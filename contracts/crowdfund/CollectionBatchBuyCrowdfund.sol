// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "solmate/utils/MerkleProofLib.sol";

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./BuyCrowdfundBase.sol";

contract CollectionBatchBuyCrowdfund is BuyCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;

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
        // The merkle root of the token IDs that can be bought. If null, allow any
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
        // The gatekeeper contract to use (if non-null) to restrict who can
        // contribute to this crowdfund.
        IGateKeeper gateKeeper;
        // The gate ID within the gateKeeper contract to use.
        bytes12 gateKeeperId;
        // Fixed governance options (i.e. cannot be changed) that the governance
        // `Party` will be created with if the crowdfund succeeds.
        FixedGovernanceOpts governanceOpts;
    }

    error NothingBoughtError();
    error InvalidTokenIdError();

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
    /// @param tokenIds The token IDs of the NFTs in the collection to buy.
    /// @param callTargets The target contracts to call to buy the NFTs.
    /// @param callValues The amount of ETH to send with each call.
    /// @param callDatas The calldata to execute for each call.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the buy was successful.
    /// @param hostIndex This is the index of the caller in the `governanceOpts.hosts` array.
    /// @return party_ Address of the `Party` instance created after its bought.
    function batchBuy(
        uint256[] memory tokenIds,
        address payable[] memory callTargets,
        uint96[] memory callValues,
        bytes[] memory callDatas,
        bytes32[][] calldata proofs,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) external onlyDelegateCall returns (Party party_) {
        // This function is restricted to hosts.
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

        IERC721 nftContract_ = nftContract;
        // Records total amount of ETH used to buy all NFTs.
        uint96 totalEthUsed;
        // This is needed because `_createParty()` requires an array of tokens.
        IERC721[] memory tokens = new IERC721[](tokenIds.length);
        bytes32 root = nftTokenIdsMerkleRoot;
        for (uint256 i; i < tokenIds.length; ++i) {
            // Verify the token ID is in the merkle tree.
            if (root != bytes32(0)) {
                _verifyTokenId(tokenIds[i], root, proofs[i]);
            }

            // Execute the call to buy the NFT.
            _buy(nftContract_, tokenIds[i], callTargets[i], callValues[i], callDatas[i]);

            tokens[i] = nftContract_;
            totalEthUsed += callValues[i];
        }

        // This is to prevent this crowdfund from finalizing a loss if nothing
        // was attempted to be bought (ie. `tokenIds` is empty) or all NFTs were
        // bought for free.
        if (totalEthUsed == 0) revert NothingBoughtError();

        return
            _finalize(
                tokens,
                tokenIds,
                totalEthUsed,
                governanceOpts,
                // If `_assertIsHost()` succeeded, the governance opts were validated.
                true
            );
    }

    function _verifyTokenId(uint256 tokenId, bytes32 root, bytes32[] calldata proof) private pure {
        bytes32 leaf;
        assembly {
            mstore(0x00, tokenId)
            leaf := keccak256(0x00, 0x20)
        }

        if (!MerkleProofLib.verify(proof, root, leaf)) revert InvalidTokenIdError();
    }
}
