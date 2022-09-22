// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity ^0.8;

import "../utils/ReadOnlyDelegateCall.sol";
import "../utils/LibSafeCast.sol";
import "openzeppelin/contracts/interfaces/IERC2981.sol";
import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";
import "../vendor/solmate/ERC721.sol";
import "./PartyGovernance.sol";

/// @notice ERC721 functionality built on top of `PartyGovernance`.
contract PartyGovernanceNFT is
    PartyGovernance,
    ERC721,
    IERC2981
{
    using LibSafeCast for uint256;

    error OnlyMintAuthorityError(address actual, address expected);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice Who can call `mint()`. Usually this will be the crowdfund contract that
    /// created the party.
    address public mintAuthority;

    /// @notice The number of tokens that have been minted.
    uint256 public tokenCount;
    /// @notice The voting power of `tokenId`.
    mapping (uint256 => uint256) public votingPowerByTokenId;

    modifier onlyMinter() {
        if (msg.sender != mintAuthority) {
            revert OnlyMintAuthorityError(msg.sender, mintAuthority);
        }
        _;
    }

    // Set the `Globals` contract. The name of symbol of ERC721 does not matter;
    // it will be set in `_initialize()`.
    constructor(IGlobals globals) PartyGovernance(globals) ERC721('', '') {
        _GLOBALS = globals;
    }

    // Initialize storage for proxy contracts.
    function _initialize(
        string memory name_,
        string memory symbol_,
        PartyGovernance.GovernanceOpts memory governanceOpts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        address mintAuthority_
    )
        internal
    {
        PartyGovernance._initialize(governanceOpts, preciousTokens, preciousTokenIds);
        name = name_;
        symbol = symbol_;
        mintAuthority = mintAuthority_;
    }

    /// @inheritdoc ERC721
    function ownerOf(uint256 tokenId)
        public
        view
        override(ERC721, ITokenDistributorParty)
        returns (address owner)
    {
        return ERC721.ownerOf(tokenId);
    }

    /// @inheritdoc EIP165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(PartyGovernance, ERC721, IERC165)
        returns (bool)
    {
        return PartyGovernance.supportsInterface(interfaceId) ||
            ERC721.supportsInterface(interfaceId) ||
            interfaceId == type(IERC2981).interfaceId;
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256) public override view returns (string memory) {
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
    function royaltyInfo(uint256, uint256)
        external
        view
        returns (address, uint256)
    {
        _delegateToRenderer();
        return (address(0), 0); // Just to make the compiler happy.
    }

    /// @inheritdoc ITokenDistributorParty
    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return votingPowerByTokenId[tokenId] * 1e18 / _getTotalVotingPower();
    }

    /// @notice Mint a governance NFT for `owner` with `votingPower` and
    /// immediately delegate voting power to `delegate.`
    /// @param owner The owner of the NFT.
    /// @param votingPower The voting power of the NFT.
    /// @param delegate The address to delegate voting power to.
    function mint(
        address owner,
        uint256 votingPower,
        address delegate
    )
        external
        onlyMinter
        onlyDelegateCall
        returns (uint256 tokenId)
    {
        tokenId = ++tokenCount;
        votingPowerByTokenId[tokenId] = votingPower;
        _adjustVotingPower(owner, votingPower.safeCastUint256ToInt192(), delegate);
        _safeMint(owner, tokenId);
    }

    /// @inheritdoc ERC721
    function transferFrom(address owner, address to, uint256 tokenId)
        public
        override
        onlyDelegateCall
    {
        // Transfer voting along with token.
        _transferVotingPower(owner, to, votingPowerByTokenId[tokenId]);
        super.transferFrom(owner, to, tokenId);
    }

    /// @inheritdoc ERC721
    function safeTransferFrom(address owner, address to, uint256 tokenId)
        public
        override
        onlyDelegateCall
    {
        // Transfer voting along with token.
        _transferVotingPower(owner, to, votingPowerByTokenId[tokenId]);
        super.safeTransferFrom(owner, to, tokenId);
    }

    /// @inheritdoc ERC721
    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes calldata data)
        public
        override
        onlyDelegateCall
    {
        // Transfer voting along with token.
        _transferVotingPower(owner, to, votingPowerByTokenId[tokenId]);
        super.safeTransferFrom(owner, to, tokenId, data);
    }

    /// @notice Relinquish the ability to call `mint()` by an authority.
    function abdicate() external onlyMinter onlyDelegateCall {
        delete mintAuthority;
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
