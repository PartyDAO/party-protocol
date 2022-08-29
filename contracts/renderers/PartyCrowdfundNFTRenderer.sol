// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../crowdfund/PartyCrowdfund.sol";

contract PartyCrowdfundNFTRenderer is IERC721Renderer {
    using LibSafeCast for uint256;

    error InvalidTokenIdError();

    IGlobals immutable _GLOBALS;

    string constant baseStyle = 'base';

    constructor(IGlobals globals) {
        _GLOBALS = globals;
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

    function renderNFTName() internal view returns (string memory) {
        return string.concat(PartyCrowdfund(payable(address(this))).name(), " Crowdfund Party");
    }

    function renderTokenName(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(
            PartyCrowdfund(payable(address(this))).name(),
            " #",
            Strings.toString(tokenId)
        ));
    }

    function renderTokenId(uint256 tokenId) internal pure returns (string memory) {
        return string(abi.encodePacked('#', Strings.toString(tokenId)));
    }

    function renderOwnerAddress(uint256 tokenId) internal view returns (string memory) {
        address owner = PartyCrowdfund(payable(address(this))).ownerOf(tokenId);

        return string(abi.encodePacked('Owner: ', Strings.toHexString(owner)));
    }

    function renderCrowdfundState() internal view returns (string memory crowdfundState) {
      PartyCrowdfund.CrowdfundLifecycle cfl = PartyCrowdfund(payable(address(this))).getCrowdfundLifecycle();
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

    function renderEthContributed(address contributor) internal view returns (string memory) {
        (uint256 ethContributed,,,) =
            PartyCrowdfund(payable(address(this))).getContributorInfo(contributor);
        return string(abi.encodePacked('ETH contributed: ', Strings.toString(ethContributed)));
    }

    function renderEthUsed(address contributor) internal view returns (string memory) {
        (,uint256 ethUsed,,) =
            PartyCrowdfund(payable(address(this))).getContributorInfo(contributor);
        return string(abi.encodePacked('ETH used: ', Strings.toString(ethUsed)));
    }

    function renderEthOwed(address contributor) internal view returns (string memory) {
        (,,uint256 ethOwed,) =
            PartyCrowdfund(payable(address(this))).getContributorInfo(contributor);
        return string(abi.encodePacked('ETH owed: ', Strings.toString(ethOwed)));
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (PartyCrowdfund(payable(address(this))).ownerOf(tokenId) == address(0)) {
            revert InvalidTokenIdError();
        }

        string[10] memory svgParts;

        svgParts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>text { fill: white; font-family: -apple-system, BlinkMacSystemFont, sans-serif; } .base { font-size: 11px; } .detail {font-size: 10px;}</style><rect width="100%" height="100%" fill="black" />';

        svgParts[1] = textLine(PartyCrowdfund(payable(address(this))).name(), 10, 20);
        svgParts[3] = textLine(renderTokenId(tokenId), 10, 40);

        svgParts[2] = textLine(PartyCrowdfund(payable(address(this))).symbol(), 10, 80);

        svgParts[4] = textLine(renderOwnerAddress(tokenId), 10, 140);

        svgParts[5] = textLine(renderCrowdfundState(), 10, 100);

        svgParts[6] = textLine(renderEthContributed(address(uint160(tokenId))), 10, 160);
        if (PartyCrowdfund(payable(address(this))).getCrowdfundLifecycle() == PartyCrowdfund.CrowdfundLifecycle.Won) {
            svgParts[7] = textLine(renderEthUsed(address(uint160(tokenId))), 10, 170);
            // svgParts[8] = textLine(renderEthOwed(address(uint160(tokenId))), 10, 180);
        }

        svgParts[9] = '</svg>';

        string memory output = string(
            abi.encodePacked(
                svgParts[0], svgParts[1], svgParts[2],
                svgParts[3], svgParts[4], svgParts[5],
                svgParts[6], svgParts[7], /* svgParts[8], */
                svgParts[9]
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

    function contractURI() external view returns (string memory) {
        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    renderNFTName(),
                    '", "description":"',
                    // TODO: Add better description?
                    "PartyBid Crowdfund NFTs represent your spot in a PartyBid party.",
                    '"}'
                    // TODO: Add SVG image
                    // '", "image": "data:image/svg+xml;base64,',
                    // Base64.encode(bytes(output)),
                    // '"}'
                )
            )
        ));

        return string(abi.encodePacked('data:application/json;base64,', json));
    }
}
