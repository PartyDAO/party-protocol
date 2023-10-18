// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../utils/LibSafeCast.sol";
import "../utils/LibAddress.sol";
import "openzeppelin/contracts/interfaces/IERC2981.sol";
import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";
import "../vendor/solmate/ERC721.sol";
import "./PartyGovernance.sol";
import "../renderers/RendererStorage.sol";

/// @notice ERC721 functionality built on top of `PartyGovernance`.
contract PartyGovernanceNFT is PartyGovernance, ERC721, IERC2981 {
    using LibSafeCast for uint256;
    using LibSafeCast for uint96;
    using LibERC20Compat for IERC20;
    using LibAddress for address payable;

    error FixedRageQuitTimestampError(uint40 rageQuitTimestamp);
    error CannotRageQuitError(uint40 rageQuitTimestamp);
    error CannotDisableRageQuitAfterInitializationError();
    error InvalidTokenOrderError();
    error BelowMinWithdrawAmountError(uint256 amount, uint256 minAmount);
    error NothingToBurnError();

    event AuthorityAdded(address indexed authority);
    event AuthorityRemoved(address indexed authority);
    event RageQuitSet(uint40 oldRageQuitTimestamp, uint40 newRageQuitTimestamp);
    event Burn(address caller, uint256 tokenId, uint256 votingPower);
    event RageQuit(address caller, uint256[] tokenIds, IERC20[] withdrawTokens, address receiver);
    event PartyCardIntrinsicVotingPowerSet(uint256 indexed tokenId, uint256 intrinsicVotingPower);

    uint40 private constant ENABLE_RAGEQUIT_PERMANENTLY = 0x6b5b567bfe; // uint40(uint256(keccak256("ENABLE_RAGEQUIT_PERMANENTLY")))
    uint40 private constant DISABLE_RAGEQUIT_PERMANENTLY = 0xab2cb21860; // uint40(uint256(keccak256("DISABLE_RAGEQUIT_PERMANENTLY")))

    // Token address used to indicate ETH.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and its address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice The number of tokens that have been minted.
    uint96 public tokenCount;
    /// @notice The total minted voting power.
    ///         Capped to `_governanceValues.totalVotingPower` unless minting
    ///         party cards for initial crowdfund.
    uint96 public mintedVotingPower;
    /// @notice The timestamp until which ragequit is enabled. Can be set to the
    ///         `ENABLE_RAGEQUIT_PERMANENTLY`/`DISABLE_RAGEQUIT_PERMANENTLY`
    ///         values to enable/disable ragequit permanently.
    ///         `DISABLE_RAGEQUIT_PERMANENTLY` can only be set during
    ///         initialization.
    uint40 public rageQuitTimestamp;
    /// @notice The voting power of `tokenId`.
    mapping(uint256 => uint256) public votingPowerByTokenId;
    /// @notice Address with authority to mint cards and update voting power for the party.
    mapping(address => bool) public isAuthority;

    function _assertAuthority() internal view {
        if (!isAuthority[msg.sender]) {
            revert NotAuthorized();
        }
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert NotAuthorized();
        }
        _;
    }

    // Set the `Globals` contract. The name or symbol of ERC721 does not matter;
    // it will be set in `_initialize()`.
    constructor(IGlobals globals) payable PartyGovernance(globals) ERC721("", "") {
        _GLOBALS = globals;
    }

    // Initialize storage for proxy contracts.
    function _initialize(
        string memory name_,
        string memory symbol_,
        uint256 customizationPresetId,
        PartyGovernance.GovernanceOpts memory governanceOpts,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        address[] memory authorities,
        uint40 rageQuitTimestamp_
    ) internal {
        PartyGovernance._initialize(
            governanceOpts,
            proposalEngineOpts,
            preciousTokens,
            preciousTokenIds
        );
        name = name_;
        symbol = symbol_;
        rageQuitTimestamp = rageQuitTimestamp_;
        unchecked {
            for (uint256 i; i < authorities.length; ++i) {
                isAuthority[authorities[i]] = true;
            }
        }
        if (customizationPresetId != 0) {
            RendererStorage(_GLOBALS.getAddress(LibGlobals.GLOBAL_RENDERER_STORAGE))
                .useCustomizationPreset(customizationPresetId);
        }
    }

    /// @inheritdoc EIP165
    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(PartyGovernance, ERC721, IERC165) returns (bool) {
        return
            PartyGovernance.supportsInterface(interfaceId) ||
            ERC721.supportsInterface(interfaceId) ||
            interfaceId == type(IERC2981).interfaceId;
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256) public view override returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    /// @notice Returns a URI for the storefront-level metadata for your contract.
    function contractURI() external view returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    function royaltyInfo(uint256, uint256) external view returns (address, uint256) {
        _delegateToRenderer();
        return (address(0), 0); // Just to make the compiler happy.
    }

    /// @notice Return the distribution share amount of a token. Included as an alias
    ///         for `votePowerByTokenId` for backwards compatibility with old
    ///         `TokenDistributor` implementations.
    /// @param tokenId The token ID to query.
    /// @return share The distribution shares of `tokenId`.
    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return votingPowerByTokenId[tokenId];
    }

    /// @notice Return the voting power share of a token. Denominated
    ///         fractions of 1e18. I.e., 1e18 = 100%.
    /// @param tokenId The token ID to query.
    /// @return share The voting power percentage of `tokenId`.
    function getVotingPowerShareOf(uint256 tokenId) public view returns (uint256) {
        uint256 totalVotingPower = _getSharedProposalStorage().governanceValues.totalVotingPower;
        return
            totalVotingPower == 0 ? 0 : (votingPowerByTokenId[tokenId] * 1e18) / totalVotingPower;
    }

    /// @notice Mint a governance NFT for `owner` with `votingPower` and
    ///         immediately delegate voting power to `delegate.` Only callable
    ///         by an authority.
    /// @param owner The owner of the NFT.
    /// @param votingPower The voting power of the NFT.
    /// @param delegate The address to delegate voting power to.
    function mint(
        address owner,
        uint256 votingPower,
        address delegate
    ) external returns (uint256 tokenId) {
        _assertAuthority();
        uint96 mintedVotingPower_ = mintedVotingPower;
        uint96 totalVotingPower = _getSharedProposalStorage().governanceValues.totalVotingPower;

        // Cap voting power to remaining unminted voting power supply.
        uint96 votingPower_ = votingPower.safeCastUint256ToUint96();
        // Allow minting past total voting power if minting party cards for
        // initial crowdfund when there is no total voting power.
        if (totalVotingPower != 0 && totalVotingPower - mintedVotingPower_ < votingPower_) {
            unchecked {
                votingPower_ = totalVotingPower - mintedVotingPower_;
            }
        }

        // Update state.
        unchecked {
            tokenId = ++tokenCount;
        }
        mintedVotingPower += votingPower_;
        votingPowerByTokenId[tokenId] = votingPower_;

        emit PartyCardIntrinsicVotingPowerSet(tokenId, votingPower_);

        // Use delegate from party over the one set during crowdfund.
        address delegate_ = delegationsByVoter[owner];
        if (delegate_ != address(0)) {
            delegate = delegate_;
        }

        _adjustVotingPower(owner, votingPower_.safeCastUint96ToInt192(), delegate);
        _safeMint(owner, tokenId);
    }

    /// @notice Add voting power to an existing NFT. Only callable by an
    ///         authority.
    /// @param tokenId The ID of the NFT to add voting power to.
    /// @param votingPower The amount of voting power to add.
    function increaseVotingPower(uint256 tokenId, uint96 votingPower) external {
        _assertAuthority();
        uint96 mintedVotingPower_ = mintedVotingPower;
        uint96 totalVotingPower = _getSharedProposalStorage().governanceValues.totalVotingPower;

        // Cap voting power to remaining unminted voting power supply. Allow
        // minting past total voting power if minting party cards for initial
        // crowdfund when there is no total voting power.
        if (totalVotingPower != 0 && totalVotingPower - mintedVotingPower_ < votingPower) {
            unchecked {
                votingPower = totalVotingPower - mintedVotingPower_;
            }
        }

        // Update state.
        mintedVotingPower += votingPower;
        uint256 newIntrinsicVotingPower = votingPowerByTokenId[tokenId] + votingPower;
        votingPowerByTokenId[tokenId] = newIntrinsicVotingPower;

        emit PartyCardIntrinsicVotingPowerSet(tokenId, newIntrinsicVotingPower);

        _adjustVotingPower(ownerOf(tokenId), votingPower.safeCastUint96ToInt192(), address(0));
    }

    /// @notice Remove voting power from an existing NFT. Only callable by an
    ///         authority.
    /// @param tokenId The ID of the NFT to remove voting power from.
    /// @param votingPower The amount of voting power to remove.
    function decreaseVotingPower(uint256 tokenId, uint96 votingPower) external {
        _assertAuthority();
        mintedVotingPower -= votingPower;
        votingPowerByTokenId[tokenId] -= votingPower;

        _adjustVotingPower(ownerOf(tokenId), -votingPower.safeCastUint96ToInt192(), address(0));
    }

    /// @notice Increase the total voting power of the party. Only callable by
    ///         an authority.
    /// @param votingPower The new total voting power to add.
    function increaseTotalVotingPower(uint96 votingPower) external {
        _assertAuthority();
        _getSharedProposalStorage().governanceValues.totalVotingPower += votingPower;
    }

    /// @notice Decrease the total voting power of the party. Only callable by
    ///         an authority.
    /// @param votingPower The new total voting power to add.
    function decreaseTotalVotingPower(uint96 votingPower) external {
        _assertAuthority();
        _getSharedProposalStorage().governanceValues.totalVotingPower -= votingPower;
    }

    /// @notice Burn governance NFTs and remove their voting power. Can only
    ///         be called by an authority before the party has started.
    /// @param tokenIds The IDs of the governance NFTs to burn.
    function burn(uint256[] memory tokenIds) public {
        _assertAuthority();
        _burnAndUpdateVotingPower(tokenIds, false);
    }

    function _burnAndUpdateVotingPower(
        uint256[] memory tokenIds,
        bool checkIfAuthorizedToBurn
    ) private returns (uint96 totalVotingPowerBurned) {
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            address owner = ownerOf(tokenId);

            // Check if caller is authorized to burn the token.
            if (checkIfAuthorizedToBurn) {
                if (
                    msg.sender != owner &&
                    getApproved[tokenId] != msg.sender &&
                    !isApprovedForAll[owner][msg.sender]
                ) {
                    revert NotAuthorized();
                }
            }

            // Must be retrieved before updating voting power for token to be burned.
            uint96 votingPower = votingPowerByTokenId[tokenId].safeCastUint256ToUint96();

            totalVotingPowerBurned += votingPower;

            // Update voting power for token to be burned.
            delete votingPowerByTokenId[tokenId];
            emit PartyCardIntrinsicVotingPowerSet(tokenId, 0);
            _adjustVotingPower(owner, -votingPower.safeCastUint96ToInt192(), address(0));

            // Burn token.
            _burn(tokenId);

            emit Burn(msg.sender, tokenId, votingPower);
        }

        // Update minted voting power.
        mintedVotingPower -= totalVotingPowerBurned;
    }

    /// @notice Burn governance NFT and remove its voting power. Can only be
    ///         called by an authority before the party has started.
    /// @param tokenId The ID of the governance NFTs to burn.
    function burn(uint256 tokenId) external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        burn(tokenIds);
    }

    /// @notice Set the timestamp until which ragequit is enabled.
    /// @param newRageQuitTimestamp The new ragequit timestamp.
    function setRageQuit(uint40 newRageQuitTimestamp) external {
        _assertHost();
        // Prevent disabling ragequit after initialization.
        if (newRageQuitTimestamp == DISABLE_RAGEQUIT_PERMANENTLY) {
            revert CannotDisableRageQuitAfterInitializationError();
        }

        uint40 oldRageQuitTimestamp = rageQuitTimestamp;

        // Prevent setting timestamp if it is permanently enabled/disabled.
        if (
            oldRageQuitTimestamp == ENABLE_RAGEQUIT_PERMANENTLY ||
            oldRageQuitTimestamp == DISABLE_RAGEQUIT_PERMANENTLY
        ) {
            revert FixedRageQuitTimestampError(oldRageQuitTimestamp);
        }

        emit RageQuitSet(oldRageQuitTimestamp, rageQuitTimestamp = newRageQuitTimestamp);
    }

    /// @notice Burn a governance NFT and withdraw a fair share of fungible tokens from the party.
    /// @param tokenIds The IDs of the governance NFTs to burn.
    /// @param withdrawTokens The fungible tokens to withdraw. Specify the
    ///                       `ETH_ADDRESS` value to withdraw ETH.
    /// @param minWithdrawAmounts The minimum amount of to withdraw for each token.
    /// @param receiver The address to receive the withdrawn tokens.
    function rageQuit(
        uint256[] calldata tokenIds,
        IERC20[] calldata withdrawTokens,
        uint256[] calldata minWithdrawAmounts,
        address receiver
    ) external {
        if (tokenIds.length == 0) revert NothingToBurnError();

        // Check if called by an authority.
        bool isAuthority_ = isAuthority[msg.sender];

        // Check if ragequit is allowed.
        uint40 currentRageQuitTimestamp = rageQuitTimestamp;
        if (!isAuthority_) {
            if (currentRageQuitTimestamp != ENABLE_RAGEQUIT_PERMANENTLY) {
                if (
                    currentRageQuitTimestamp == DISABLE_RAGEQUIT_PERMANENTLY ||
                    currentRageQuitTimestamp < block.timestamp
                ) {
                    revert CannotRageQuitError(currentRageQuitTimestamp);
                }
            }
        }

        // Used as a reentrancy guard. Will be updated back after ragequit.
        rageQuitTimestamp = DISABLE_RAGEQUIT_PERMANENTLY;

        // Update last rage quit timestamp.
        lastRageQuitTimestamp = uint40(block.timestamp);

        // Sum up total amount of each token to withdraw.
        uint256[] memory withdrawAmounts = new uint256[](withdrawTokens.length);
        {
            IERC20 prevToken;
            for (uint256 i; i < withdrawTokens.length; ++i) {
                // Check if order of tokens to transfer is valid.
                // Prevent null and duplicate transfers.
                if (prevToken >= withdrawTokens[i]) revert InvalidTokenOrderError();

                prevToken = withdrawTokens[i];

                // Check token's balance.
                uint256 balance = address(withdrawTokens[i]) == ETH_ADDRESS
                    ? address(this).balance
                    : withdrawTokens[i].balanceOf(address(this));

                // Add fair share of tokens from the party to total.
                for (uint256 j; j < tokenIds.length; ++j) {
                    // Must be retrieved before burning the token.
                    withdrawAmounts[i] += (balance * getVotingPowerShareOf(tokenIds[j])) / 1e18;
                }
            }
        }
        {
            // Burn caller's party cards. This will revert if caller is not the
            // the owner or approved for any of the card they are attempting to
            // burn, not an authority, or if there are duplicate token IDs.
            uint96 totalVotingPowerBurned = _burnAndUpdateVotingPower(tokenIds, !isAuthority_);

            // Update total voting power of party.
            _getSharedProposalStorage().governanceValues.totalVotingPower -= totalVotingPowerBurned;
        }
        {
            uint16 feeBps_ = feeBps;
            for (uint256 i; i < withdrawTokens.length; ++i) {
                IERC20 token = withdrawTokens[i];
                uint256 amount = withdrawAmounts[i];

                // Take fee from amount.
                uint256 fee = (amount * feeBps_) / 1e4;

                if (fee > 0) {
                    amount -= fee;

                    // Transfer fee to fee recipient.
                    if (address(token) == ETH_ADDRESS) {
                        payable(feeRecipient).transferEth(fee);
                    } else {
                        token.compatTransfer(feeRecipient, fee);
                    }
                }

                if (amount > 0) {
                    uint256 minAmount = minWithdrawAmounts[i];

                    // Check amount is at least minimum.
                    if (amount < minAmount) {
                        revert BelowMinWithdrawAmountError(amount, minAmount);
                    }

                    // Transfer token from party to recipient.
                    if (address(token) == ETH_ADDRESS) {
                        payable(receiver).transferEth(amount);
                    } else {
                        token.compatTransfer(receiver, amount);
                    }
                }
            }
        }

        // Update ragequit timestamp back to before.
        rageQuitTimestamp = currentRageQuitTimestamp;

        emit RageQuit(msg.sender, tokenIds, withdrawTokens, receiver);
    }

    /// @inheritdoc ERC721
    function transferFrom(address owner, address to, uint256 tokenId) public override {
        // Transfer voting along with token.
        _transferVotingPower(owner, to, votingPowerByTokenId[tokenId]);
        super.transferFrom(owner, to, tokenId);
    }

    /// @inheritdoc ERC721
    function safeTransferFrom(address owner, address to, uint256 tokenId) public override {
        // super.safeTransferFrom() will call transferFrom() first which will
        // transfer voting power.
        super.safeTransferFrom(owner, to, tokenId);
    }

    /// @inheritdoc ERC721
    function safeTransferFrom(
        address owner,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) public override {
        // super.safeTransferFrom() will call transferFrom() first which will
        // transfer voting power.
        super.safeTransferFrom(owner, to, tokenId, data);
    }

    /// @notice Add a new authority.
    /// @dev Used in `AddAuthorityProposal`. Only the party itself can add
    ///      authorities to prevent it from being used anywhere else.
    function addAuthority(address authority) external onlySelf {
        isAuthority[authority] = true;

        emit AuthorityAdded(authority);
    }

    /// @notice Relinquish the authority role.
    function abdicateAuthority() external {
        _assertAuthority();
        delete isAuthority[msg.sender];

        emit AuthorityRemoved(msg.sender);
    }

    function _delegateToRenderer() private view {
        _readOnlyDelegateCall(
            // Instance of IERC721Renderer.
            _GLOBALS.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL),
            msg.data
        );
        assert(false); // Will not be reached.
    }
}
