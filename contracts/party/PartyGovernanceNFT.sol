// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../utils/ReadOnlyDelegateCall.sol";
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
    error Uint256ToInt128CastOutOfRangeError(uint256 u256);

    address private immutable _GLOBALS;
    IPartyFactory private immutable _FACTORY;

    string public name;
    string public symbol;

    uint256 private _tokenCounter;
    // owner -> operator -> isApproved
    mapping (address => mapping (address => bool)) public isApprovedForAll;
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

    constructor() {
        _FACTORY = IPartyFactory(msg.sender);
        _GLOBALS = _FACTORY._GLOBALS();
    }

    // Initialize storage for proxy contracts.
    function _initialize(
        string calldata name_,
        string calldata symbol_,
        PartyGovernance.GovernanceOpts memory governanceOpts,
        IERC721 preciousToken,
        uint256 preciousTokenId
    )
        internal
    {
        PartyGovernance._initialize(governanceOpts, preciousToken, preciousTokenId);
        name = name_;
        symbol = symbol_;
    }

    // Mint a governance NFT for `owner` with `votingPower` and
    // immediately delegate voting power to `delegate.`
    function mint(address owner, uint256 votingPower, address delegate) external
    {
        require(msg.sender == address(_FACTORY)); // Only factory can mint.
        uint256 tokenId = ++_tokenCounter;
        _tokens[tokenId] = TokenInfo({
            owner: owner,
            votingPower: votingPower,
            operator: address(0)
        });
        _adjustVotingPower(owner, _safeCastToInt128(votingPower), delegate);
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

    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes calldata data)
        external
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

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        if (interfaceId == 0x01ffc9a7) {
            return true;
        }
        if (interfaceId == 0xffffffff) {
            return false;
        }
        return interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    function getApproved(uint256 tokenId)
        external
        view
        returns (address)
    {
        return _tokens[tokenId].operator;
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        owner = _tokens[tokenId].owner;
        if (owner == address(0)) {
            revert InvalidTokenError(tokenId);
        }
    }

    function getVotingPowerOfToken(uint256 tokenId) external view returns (uint256) {
        return _tokens[tokenId].votingPower;
    }

    function tokenURI(uint256 tokenId) external /* view */ returns (string memory)
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
        _transferVotingPower(owner, to, _tokens[tokenId].votingPower);
        Transfer(owner, to, tokenId);
    }

    function _consumeApproval(address owner, address operator, uint256 tokenId)
        private
    {
        // Always consume individual approvals.
        address approvedOperator = _tokens[tokenId].operator;
        _tokens[tokenId].operator = address(0);
        if (operator != owner) {
            if (isApprovedForAll[owner][operator]) {
                return;
            }
            if (approvedOperator != operator) {
                revert NotApprovedError(operator, approvedOperator, tokenId);
            }
        }
    }

    function _safeCastToInt128(uint256 x)
        private
        pure
        returns (int128)
    {
        if (x > type(int128).max) {
            revert Uint256ToInt128CastOutOfRangeError(x);
        }
        return int128(int256(x));
    }
}
