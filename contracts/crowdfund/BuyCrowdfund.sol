// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./BuyCrowdfundBase.sol";

/// @notice A crowdfund that purchases a specific NFT (i.e., with a known token
///         ID) listing for a known price.
contract BuyCrowdfund is BuyCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;

    struct BuyCrowdfundOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // Customization preset ID to use for the crowdfund and governance NFTs.
        uint256 customizationPresetId;
        // The ERC721 contract of the NFT being bought.
        IERC721 nftContract;
        // ID of the NFT being bought.
        uint256 nftTokenId;
        // How long this crowdfund has to bid on the NFT, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for the NFT.
        // If zero, no maximum.
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
        // contribute to this crowdfund. If used, only contributors or hosts can
        // call `buy()`.
        IGateKeeper gateKeeper;
        // The gate ID within the gateKeeper contract to use.
        bytes12 gateKeeperId;
        // Whether the party is only allowing a host to call `buy()`.
        bool onlyHostCanBuy;
        // Fixed governance options (i.e. cannot be changed) that the governance
        // `Party` will be created with if the crowdfund succeeds.
        FixedGovernanceOpts governanceOpts;
    }

    /// @notice The NFT token ID to buy.
    uint256 public nftTokenId;
    /// @notice The NFT contract to buy.
    IERC721 public nftContract;
    /// @notice Whether the party is only allowing a host to call `buy()`.
    bool public onlyHostCanBuy;

    // Set the `Globals` contract.
    constructor(IGlobals globals) BuyCrowdfundBase(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function initialize(BuyCrowdfundOptions memory opts)
        external
        payable
        onlyConstructor
    {
        if (opts.onlyHostCanBuy && opts.governanceOpts.hosts.length == 0) {
            revert MissingHostsError();
        }
        BuyCrowdfundBase._initialize(BuyCrowdfundBaseOptions({
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
        }));
        onlyHostCanBuy = opts.onlyHostCanBuy;
        nftTokenId = opts.nftTokenId;
        nftContract = opts.nftContract;
    }

    /// @notice Execute arbitrary calldata to perform a buy, creating a party
    ///         if it successfully buys the NFT.
    /// @param callTarget The target contract to call to buy the NFT.
    /// @param callValue The amount of ETH to send with the call.
    /// @param callData The calldata to execute.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the buy was successful.
    /// @param hostIndex If the caller is a host, this is the index of the caller in the
    ///                  `governanceOpts.hosts` array.
    /// @return party_ Address of the `Party` instance created after its bought.
    function buy(
        address payable callTarget,
        uint96 callValue,
        bytes calldata callData,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    )
        external
        returns (Party party_)
    {
        // This function can be optionally restricted in different ways.
        bool isValidatedGovernanceOpts;
        if (onlyHostCanBuy) {
            if (address(gateKeeper) != address(0)) {
                // `onlyHostCanBuy` is true and we are using a gatekeeper. Either
                // the host or a contributor can call this function.
                isValidatedGovernanceOpts =
                    _assertIsHostOrContributor(msg.sender, governanceOpts, hostIndex);
            } else {
                // `onlyHostCanBuy` is true and we are NOT using a gatekeeper.
                // Only a host can call this function.
                isValidatedGovernanceOpts =
                    _assertIsHost(msg.sender, governanceOpts, hostIndex);
            }
        } else if (address(gateKeeper) != address(0)) {
            // `onlyHostCanBuy` is false and we are using a gatekeeper.
            // Only a contributor can call this function.
            _assertIsContributor(msg.sender);
        }

        return _buy(
            nftContract,
            nftTokenId,
            callTarget,
            callValue,
            callData,
            governanceOpts,
            isValidatedGovernanceOpts
        );
    }
}
