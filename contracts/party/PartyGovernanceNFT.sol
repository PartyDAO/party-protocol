// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/ReadOnlyDelegateCall.sol";
import "../utils/LibSafeCast.sol";
import "../globals/IGlobals.sol";
import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC721Receiver.sol";

import "./PartyGovernance.sol";

// ERC721 functionality built on top of PartyGovernance.
contract PartyGovernanceNFT is
    PartyGovernance,
    IERC721
{
    using LibSafeCast for uint256;

    struct TokenInfo {
        address owner;
        address operator;
        uint256 votingPower;
    }

    error InvalidTokenError(uint256 tokenId);
    error InvalidTokenRecipientError();
    error NotTokenOwnerError(address notOWner, address owner, uint256 tokenId);
    error NotApprovedError(address notOperator, address operator, uint256 tokenId);
    error InvalidERC721ReceiverResultError(address receiver);
    error OnlyMintAuthorityError(address actual, address expected);

    IGlobals private immutable _GLOBALS;

    string public name;
    string public symbol;
    // Who can call mint()
    address public mintAuthority;
    // owner -> numTokensHeldyOwner
    mapping (address => uint256) public balanceOf;

    uint256 private _tokenCounter;
    // owner -> operator -> isApproved
    mapping (address => mapping (address => bool)) public isApprovedForAll;
    // tokenId -> TokenInfo
    mapping (uint256 => TokenInfo) private _tokens;

    modifier mustOwnToken(uint256 tokenId, address whom) {
        {
            address owner = _tokens[tokenId].owner;
            if (owner == address(0)) {
                revert InvalidTokenError(tokenId);
            }
            if (owner != whom) {
                revert NotTokenOwnerError(whom, owner, tokenId);
            }
        }
        _;
    }

    modifier onlyMinter() {
        if (msg.sender != mintAuthority) {
            revert OnlyMintAuthorityError(msg.sender, mintAuthority);
        }
        _;
    }

    constructor(IGlobals globals) PartyGovernance(globals) {
        _GLOBALS = globals;
    }

    // Initialize storage for proxy contracts.
    function _initialize(
        string memory name_,
        string memory symbol_,
        PartyGovernance.GovernanceOpts memory governanceOpts,
        IERC721 preciousToken,
        uint256 preciousTokenId,
        address mintAuthority_
    )
        internal
    {
        PartyGovernance._initialize(governanceOpts, preciousToken, preciousTokenId);
        name = name_;
        symbol = symbol_;
        mintAuthority = mintAuthority_;
    }

    // Mint a governance NFT for `owner` with `votingPower` and
    // immediately delegate voting power to `delegate.`
    function mint(
        address owner,
        uint256 votingPower,
        address delegate
    )
        onlyMinter
        external
    {
        uint256 tokenId = ++_tokenCounter;
        _tokens[tokenId] = TokenInfo({
            owner: owner,
            votingPower: votingPower,
            operator: address(0)
        });
        ++balanceOf[owner];
        _adjustVotingPower(owner, votingPower.safeCastUint256ToInt128(), delegate);
        emit Transfer(address(0), owner, tokenId);
    }

    function approve(address operator, uint256 tokenId)
        external
        mustOwnToken(tokenId, msg.sender)
    {
        _tokens[tokenId].operator = operator;
        emit Approval(msg.sender, operator, tokenId);
    }

    function setApprovalForAll(address operator, bool approved)
        external
    {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address owner, address to, uint256 tokenId)
        public
        mustOwnToken(tokenId, owner)
    {
        if (to == owner) {
            return;
        }
        _transferFrom(owner, to, tokenId);
    }

    function safeTransferFrom(address owner, address to, uint256 tokenId)
        external
    {
        safeTransferFrom(owner, to, tokenId, "");
    }

    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes memory data)
        public
        mustOwnToken(tokenId, owner)
    {
        if (to == owner) {
            return;
        }
        _transferFrom(owner, to, tokenId);
        {
            uint256 cs;
            assembly { cs := extcodesize(to) }
            if (cs > 0) {
                bytes4 r = IERC721Receiver(to)
                    .onERC721Received(msg.sender, owner, tokenId, data);
                if (r != IERC721Receiver.onERC721Received.selector) {
                    revert InvalidERC721ReceiverResultError(to);
                }
            }
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(PartyGovernance, IERC721)
        returns (bool)
    {
        // IERC721
        if (interfaceId == 0x80ac58cd) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    function getApproved(uint256 tokenId)
        external
        view
        returns (address)
    {
        return _tokens[tokenId].operator;
    }

    function ownerOf(uint256 tokenId)
        external
        view
        override(IERC721, ITokenDistributorParty)
        returns (address owner)
    {
        owner = _tokens[tokenId].owner;
        if (owner == address(0)) {
            revert InvalidTokenError(tokenId);
        }
    }

    function getVotingPowerOfToken(uint256 tokenId) external view returns (uint256) {
        return _tokens[tokenId].votingPower;
    }

    function tokenURI(uint256) external /* view */ returns (string memory)
    {
        // An instance of IERC721Renderer
        _readOnlyDelegateCall(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL),
            msg.data
        );
    }

    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return _tokens[tokenId].votingPower * 1e18 / _getTotalVotingPower();
    }

    function _transferFrom(address owner, address to, uint256 tokenId)
        private
    {
        if (to == address(0)) {
            revert InvalidTokenRecipientError();
        }
        _consumeApproval(owner, msg.sender, tokenId);
        _tokens[tokenId].owner = to;
        _tokens[tokenId].operator = address(0); // Don't persist individual approvals.
        --balanceOf[owner];
        ++balanceOf[to];
        _transferVotingPower(owner, to, _tokens[tokenId].votingPower);
        emit Transfer(owner, to, tokenId);
    }

    function _consumeApproval(address owner, address operator, uint256 tokenId)
        private
    {
        if (operator != owner) {
            if (isApprovedForAll[owner][operator]) {
                return;
            }
            address approvedOperator = _tokens[tokenId].operator;
            if (approvedOperator != operator) {
                revert NotApprovedError(operator, approvedOperator, tokenId);
            }
        }
    }
}
