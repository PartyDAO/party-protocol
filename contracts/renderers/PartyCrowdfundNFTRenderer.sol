// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "../utils/Strings.sol";
import "../utils/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../crowdfund/PartyBid.sol";
import "../crowdfund/PartyBuy.sol";
import "../crowdfund/PartyCollectionBuy.sol";
import "../crowdfund/PartyCrowdfund.sol";
import "../utils/PartyHelpers.sol";

contract PartyCrowdfundNFTRenderer is IERC721Renderer {
    using LibSafeCast for uint256;

    error InvalidTokenIdError();

    IGlobals immutable _GLOBALS;

    string constant baseStyle = 'base';
    address constant partyHelpersAddress = address(0xB9529177b37f4729aA7189261F3BA5BCd50EeB48);

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function getCrowdfundType() internal view returns (PartyHelpers.CrowdfundType) {
        PartyHelpers ph = PartyHelpers(partyHelpersAddress);
        return ph.getCrowdfundType(address(_GLOBALS), address(this));
    }

    function getCrowdfundNftName() internal view returns (string memory name) {
        PartyHelpers.CrowdfundType cft = getCrowdfundType();
        if (cft == PartyHelpers.CrowdfundType.Bid) {
            name = PartyBid(payable(address(this))).name();
        } else if (cft == PartyHelpers.CrowdfundType.Buy) {
            name = PartyBuy(payable(address(this))).name();
        } else if (cft == PartyHelpers.CrowdfundType.CollectionBuy) {
            name = PartyCollectionBuy(payable(address(this))).name();
        }
    }

    function getCrowdfundNftSymbol() internal view returns(string memory symbol) {
        PartyHelpers.CrowdfundType cft = getCrowdfundType();
        if (cft == PartyHelpers.CrowdfundType.Bid) {
            symbol = PartyBid(payable(address(this))).symbol();
        } else if (cft == PartyHelpers.CrowdfundType.Buy) {
            symbol = PartyBuy(payable(address(this))).symbol();
        } else if (cft == PartyHelpers.CrowdfundType.CollectionBuy) {
            symbol = PartyCollectionBuy(payable(address(this))).symbol();
        }
    }

    function getCrowdfundNftOwnerOf(uint256 tokenId) internal view returns(address owner) {
        PartyHelpers.CrowdfundType cft = getCrowdfundType();
        if (cft == PartyHelpers.CrowdfundType.Bid) {
            owner = PartyBid(payable(address(this))).ownerOf(tokenId);
        } else if (cft == PartyHelpers.CrowdfundType.Buy) {
            owner = PartyBuy(payable(address(this))).ownerOf(tokenId);
        } else if (cft == PartyHelpers.CrowdfundType.CollectionBuy) {
            owner = PartyCollectionBuy(payable(address(this))).ownerOf(tokenId);
        }
    }

    function getCrowdfundLifecycle() internal view returns (PartyCrowdfund.CrowdfundLifecycle cflc) {
        PartyHelpers.CrowdfundType cft = getCrowdfundType();
        if (cft == PartyHelpers.CrowdfundType.Bid) {
            cflc = PartyBid(payable(address(this))).getCrowdfundLifecycle();
        } else if (cft == PartyHelpers.CrowdfundType.Buy) {
            cflc = PartyBuy(payable(address(this))).getCrowdfundLifecycle();
        } else if (cft == PartyHelpers.CrowdfundType.CollectionBuy) {
            cflc = PartyCollectionBuy(payable(address(this))).getCrowdfundLifecycle();
        }
    }

    function textLine(string memory text, uint256 xPos, uint256 yPos) internal pure returns (string memory) {
        string[3] memory parts;

        parts[0] = string(abi.encodePacked(
            '<text x="',
            Strings.toString(xPos),
            '" y="',
            Strings.toString(yPos),
            '" class="',
            // TODO: Parameterize
            baseStyle,
            '">'
        ));
        parts[1] = text;
        parts[2] = '</text>';

        return string(abi.encodePacked(
            parts[0],
            parts[1],
            parts[2]
        ));
    }

    function renderTokenName(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(
            getCrowdfundNftName(),
            " #",
            Strings.toString(tokenId)
        ));
    }

    function renderTokenId(uint256 tokenId) internal pure returns (string memory) {
        return string(abi.encodePacked('#', Strings.toString(tokenId)));
    }

    function renderOwnerAddress(uint256 tokenId) internal view returns (string memory) {
        address owner = getCrowdfundNftOwnerOf(tokenId);

        return string(abi.encodePacked('Owner: ', Strings.toHexString(owner)));
    }

    function renderCrowdfundState() internal view returns (string memory crowdfundState) {
      PartyCrowdfund.CrowdfundLifecycle cfl = getCrowdfundLifecycle();
      if (cfl == PartyCrowdfund.CrowdfundLifecycle.Invalid) {
          crowdfundState = "Invalid";
      } else if (cfl == PartyCrowdfund.CrowdfundLifecycle.Active) {
          crowdfundState = "Active";
      } else if (cfl == PartyCrowdfund.CrowdfundLifecycle.Expired) {
          crowdfundState = "Expired";
      } else if (cfl == PartyCrowdfund.CrowdfundLifecycle.Busy) {
          crowdfundState = "Busy";
      } else if (cfl == PartyCrowdfund.CrowdfundLifecycle.Lost) {
          crowdfundState = "Lost";
      } else if (cfl == PartyCrowdfund.CrowdfundLifecycle.Won) {
          crowdfundState = "Won";
      } else {
          crowdfundState = "Unknown";
      }
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if(getCrowdfundNftOwnerOf(tokenId) == address(0)) {
            revert InvalidTokenIdError();
        }

        string[7] memory svgParts;

        svgParts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>text { fill: white; font-family: -apple-system, BlinkMacSystemFont, sans-serif; } .base { font-size: 11px; } .detail {font-size: 10px;}</style><rect width="100%" height="100%" fill="black" />';

        svgParts[1] = textLine(getCrowdfundNftName(), 10, 20);
        svgParts[3] = textLine(renderTokenId(tokenId), 300, 20);

        svgParts[2] = textLine(getCrowdfundNftSymbol(), 10, 60);

        svgParts[4] = textLine(renderOwnerAddress(tokenId), 10, 120);

        svgParts[5] = textLine(renderCrowdfundState(), 10, 80);

        svgParts[6] = '</svg>';

        string memory output = string(
            abi.encodePacked(
                svgParts[0], svgParts[1], svgParts[2],
                svgParts[3], svgParts[4], svgParts[5],
                svgParts[6]
            )
        );

        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    renderTokenName(tokenId),
                    '", "description": "PartyBid Crowdfund NFT", "image": "data:image/svg+xml;base64,',
                    Base64.encode(bytes(output)),
                    '"}'
                )
            )
        ));

        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }
}
