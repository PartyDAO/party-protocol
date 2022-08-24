// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/ReadOnlyDelegateCall.sol";
import "../utils/LibSafeCast.sol";
import "../utils/IERC2981.sol";
import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";
import "../vendor/solmate/ERC721.sol";
import "./PartyGovernance.sol";

/// @notice ERC721 functionality built on top of PartyGovernance.
contract PartyGovernanceNFT is
    PartyGovernance,
    ERC721,
    IERC2981
{
    using LibSafeCast for uint256;

    error OnlyMintAuthorityError(address actual, address expected);

    IGlobals private immutable _GLOBALS;

    // Who can call mint()
    address public mintAuthority;

    uint256 public tokenCount;
    // tokenId -> voting power
    mapping (uint256 => uint256) public votingPowerByTokenId;

    modifier onlyMinter() {
        if (msg.sender != mintAuthority) {
            revert OnlyMintAuthorityError(msg.sender, mintAuthority);
        }
        _;
    }

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
        override(PartyGovernance, ERC721)
        returns (bool)
    {
        return PartyGovernance.supportsInterface(interfaceId) ||
            ERC721.supportsInterface(interfaceId) ||
            // EIP-2981: NFT Royalty Standard
            interfaceId == 0x2a55205a;
    }

    function tokenURI(uint256) public override view returns (string memory) {
        return _delegateToRenderer();
    }

    function contractURI() external view returns (string memory) {
        return _delegateToRenderer();
    }

    function royaltyInfo(
        uint256,
        uint256 _salePrice
    ) external view returns (
        address receiver,
        uint256 royaltyAmount
    ) {
        receiver = _GLOBALS.getAddress(LibGlobals.GLOBAL_ROYALTY_RECEIVER);
        royaltyAmount = _salePrice * _GLOBALS.getUint256(LibGlobals.GLOBAL_ROYALTY_BPS) / 1e4;
    }

    /// @notice Get the distribution % of a tokenId, scaled by 1e18.
    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return votingPowerByTokenId[tokenId] * 1e18 / _getTotalVotingPower();
    }

    /// @notice Mint a governance NFT for `owner` with `votingPower` and
    /// immediately delegate voting power to `delegate.`
    function mint(
        address owner,
        uint256 votingPower,
        address delegate
    )
        external
        onlyMinter
        onlyDelegateCall
    {
        uint256 tokenId = ++tokenCount;
        votingPowerByTokenId[tokenId] = votingPower;
        _adjustVotingPower(owner, votingPower.safeCastUint256ToInt192(), delegate);
        _mint(owner, tokenId);
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

    function safeTransferFrom(address owner, address to, uint256 tokenId)
        public
        override
        onlyDelegateCall
    {
        // Transfer voting along with token.
        _transferVotingPower(owner, to, votingPowerByTokenId[tokenId]);
        super.safeTransferFrom(owner, to, tokenId);
    }

    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes calldata data)
        public
        override
        onlyDelegateCall
    {
        // Transfer voting along with token.
        _transferVotingPower(owner, to, votingPowerByTokenId[tokenId]);
        super.safeTransferFrom(owner, to, tokenId, data);
    }

    function _delegateToRenderer() private view returns (string memory) {
        _readOnlyDelegateCall(
            // Instance of IERC721Renderer.
            _GLOBALS.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL),
            msg.data
        );
        assert(false); // Will not be reached.
        return "";
    }
}
