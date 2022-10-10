// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../crowdfund/Crowdfund.sol";
import "./RendererStorage.sol";
import "./fonts/IFont.sol";

contract CrowdfundNFTRenderer is IERC721Renderer {
    using LibSafeCast for uint256;
    using Strings for uint256;
    using Strings for address;

    error InvalidTokenIdError();

    enum CrowdfundStatus {
        LIVE,
        WON,
        LOST
    }

    IGlobals immutable _GLOBALS;
    RendererStorage immutable _storage;
    IFont immutable _font;

    constructor(IGlobals globals, RendererStorage rendererStorage, IFont font) {
        _GLOBALS = globals;
        _storage = rendererStorage;
        _font = font;
    }

    // The renderer is called via delegateCall, so we need to declare the storage layout.
    // Run `yarn layout Crowdfund.sol/Crowdfund` to generate the current layout.
    string name;
    string symbol;
    mapping(uint256 => address) _owners;
    Party party;
    uint96 totalContributions;
    IGateKeeper gateKeeper;
    bytes12 gateKeeperId;
    address payable splitRecipient;
    uint16 splitBps;
    bool _splitRecipientHasBurned;
    bytes32 governanceOptsHash;
    mapping(address => address) delegationsByContributor;
    mapping(address => Crowdfund.Contribution[]) _contributionsByContributor;
    mapping(address => Crowdfund.Claim) claims;

    // TODO: Implement contract URI
    function contractURI() external view returns (string memory) {
        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    name,
                    '", "description":"',
                    "AuctionCrowdfund Crowdfund NFTs represent your spot in a AuctionCrowdfund party.",
                    '"}'
                    // '", "image": "data:image/svg+xml;base64,',
                    // Base64.encode(bytes(output)),
                    // '"}'
                )
            )
        ));

        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address owner = _owners[tokenId];
        if (owner == address(0)) {
            revert InvalidTokenIdError();
        }

        string memory partyName = name;
        string memory contribution = getContribution(owner);
        CrowdfundStatus status = getCrowdfundStatus();

        return string.concat(
            'data:application/json;base64,',
            Base64.encode(abi.encodePacked(
                '{"name":"',
                generateName(contribution),
                '", "description":"',
                generateDescription(partyName, status, contribution),
                '", "image": "data:image/svg+xml;base64,',
                Base64.encode(abi.encodePacked(
                    // Split to avoid stack too deep errors
                    generateSVG1(),
                    generateSVG2(status),
                    generateSVG3(partyName)
                )),
                '"}'
            ))
        );
    }

    function generateName(string memory contribution) private pure returns (string memory) {
        return string.concat('Contribution - ', contribution, ' ETH');
    }

    function generateDescription(
        string memory partyName,
        CrowdfundStatus status,
        string memory contribution
    ) private view returns (string memory) {
        if (status == CrowdfundStatus.WON) {
            return string.concat(
                partyName,
                ' has won! You can use this item to activate your membership in the party. Head to partybid.app/join/',
                address(this).toHexString(),
                ' to activate.'
            );
        } else if (status == CrowdfundStatus.LOST) {
            return string.concat(
                partyName,
                ' has lost. You can use this item to claim your ETH back from the party. Head to partybid.app/join/',
                address(this).toHexString(),
                ' to claim.'
            );
        } else {
            return string.concat(
                'This item represents your contribution of ',
                contribution,
                ' ETH to the ',
                partyName,
                ' crowdfund. When the crowdfund concludes, you can use this card to claim your ETH or membership in the party. Head to partybid.app/join/',
                address(this).toHexString(),
                ' to see more.'
            );
        }
    }

    function generateSVG1() private view returns (string memory) {
        uint256 animationDuration = calcAnimationDuration();
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="362" height="542" fill="none"><style>.scrolling-text{animation: move ',
            toDecimalString(animationDuration),
            's linear infinite;animation-timing-function:steps(120, end);}.delay{animation-delay:',
            toDecimalString(animationDuration / 2),
            's;}@keyframes move{to{transform:translateX(-',
            toDecimalString(calcTranslateX()),
            '%);}}@font-face{font-family:&quot;Console&quot;;src:url(',
            _font.getFont()
        );
    }

    function generateSVG2(CrowdfundStatus status) private view returns (string memory) {
        return string.concat(
            _storage.readFile(RendererFileKey.CROWDFUND_CARD_DATA_1),
            status == CrowdfundStatus.LIVE ? '#50586D' : '#91A6C3',
            _storage.readFile(RendererFileKey.CROWDFUND_CARD_DATA_2),
            status == CrowdfundStatus.WON ? '#50586D' : '#91A6C3',
            '"/><g fill="#a7b8cf"><path d="M159.65 490.49h2.41l1.62 7.09a11.48 11.48 0 0 1 .27 1.53l.09 1.53h.18l.07-1.53c.05-.36.14-.83.31-1.53l1.55-7.09h2.7l1.57 7.09.29 1.53c.05.45.07.77.07 1.53h.2l.07-1.53a12.07 12.07 0 0 1 .27-1.53l1.64-7.09h2.39l-3.01 12.01h-2.9l-1.55-6.95a10.83 10.83 0 0 1-.23-1.55l-.07-1.22h-.18c-.04 1.15-.11 1.98-.29 2.77l-1.55 6.95h-2.9l-3.02-12.01z"/><use xlink:href="#I"/><path d="M190.32 502.5v-12.01h3.33l3.35 6.82c.36.72.61 1.4.79 2.07.09.32.14.52.23 1.03h.16c-.23-1.21-.32-2.2-.32-3.17v-6.75h2.3v12.01h-2.88l-3.73-7.54c-.32-.67-.56-1.21-.68-1.64-.09-.31-.14-.54-.22-1.08h-.16l.11 1.12c.04.43.04.9.04 1.76v7.38h-2.32z"/></g><path d="M241 486v20a5 5 0 0 0 5 5h80a5 5 0 0 0 5-5v-20a5 5 0 0 0-5-5h-80a5 5 0 0 0-5 5z" fill="',
            status == CrowdfundStatus.LOST ? '#50586D' : '#91A6C3',
            '"/><g fill="#a7b8cf"><path d="M267.75 502.5v-12.01h2.36v9.83h4.29v2.18h-6.65z"/><use xlink:href="#I" x="97.509"/><path d="M294.66 494.17c-.86-1.17-1.91-1.75-3.13-1.75-1.15 0-1.91.58-1.91 1.5a1.26 1.26 0 0 0 .58 1.06c.32.2.58.31 1.69.67 1.19.4 1.62.59 2.16 1.06.7.59 1.08 1.42 1.08 2.38 0 2.18-1.67 3.76-3.98 3.76a4.97 4.97 0 0 1-2.7-.81c-.25-.16-.38-.25-.68-.52v-2.49c.85 1.26 1.93 1.91 3.22 1.91 1.15 0 1.98-.65 1.98-1.57 0-.4-.2-.78-.5-1.03-.36-.29-.74-.45-1.84-.83-1.21-.4-1.66-.61-2.18-1.06-.7-.58-1.08-1.46-1.08-2.48 0-2.18 1.67-3.73 4.03-3.73.97 0 1.85.27 2.65.81.22.14.34.23.61.5v2.62zm1.15-1.45v-2.23h9.04v2.23h-3.33v9.78h-2.32v-9.78h-3.39z"/></g><clipPath id="A"><path fill="#91a6c3" d="M31 445h299v27H31z"/></clipPath><g clip-path="url(#A)"><text class="scrolling-text" fill="#50586d" xml:space="preserve" style="white-space:pre" font-family="Console" font-size="48"><tspan x="329" y="465.984">'
        );
    }

    function generateSVG3(string memory partyName) private pure returns (string memory) {
        return string.concat(
            partyName,
            '</tspan></text><text class="scrolling-text delay" fill="#50586d" xml:space="preserve" style="white-space:pre" font-family="Console" font-size="48"><tspan x="329" y="465.984">',
            partyName,
            '</tspan></text></g><rect x="16" y="436" width="330" height="90" rx="15" fill="url(#G)"/><defs><linearGradient id="B" x1="181" y1="61.24" x2="181" y2="2531.36" xlink:href="#J"><stop stop-color="#fbfcfd"/><stop offset=".5" stop-color="#a7b8cf"/></linearGradient><linearGradient id="C" x1="181" y1=".5" x2="181" y2="541.5" xlink:href="#J"><stop stop-color="#e7ecf2"/><stop offset=".69" stop-color="#a7b8cf"/><stop offset="1" stop-color="#8d9eb5"/></linearGradient><linearGradient id="D" x1="225.98" y1="21.68" x2="225.98" y2="306.98" xlink:href="#J"><stop stop-color="#fff"/><stop offset=".5" stop-color="#a7b8cf"/></linearGradient><linearGradient id="E" x1="207.042" y1="2.896" x2="-4.565" y2="857.625" xlink:href="#J"><stop stop-color="#50586d"/><stop offset=".5"/></linearGradient><linearGradient id="F" x1="0" y1="527" x2="181" y2="435" xlink:href="#J"><stop stop-color="#dce5f0"/><stop offset=".5" stop-color="#a7b8cf"/><stop offset="1" stop-color="#91a6c3"/></linearGradient><linearGradient id="J" gradientUnits="userSpaceOnUse"/><path id="H" d="M263.56 407.05c0-2.27 1.45-3.81 3.6-3.81 2 0 3.05 1.58 2.33 3.92h-4.46c0 1.1.82 1.68 2.05 1.68.8 0 1.45-.2 2.1-.59l-.31 1.46c-.56.32-1.3.44-2.04.44-2.06 0-3.26-1.19-3.26-3.11l-.01.01zm4.7-1.07c.12-.86-.31-1.46-1.22-1.46s-1.57.61-1.82 1.46h3.05-.01z"/><path id="I" d="M177.131 496.22c0-2.05.4-3.46 1.21-4.43.86-1.01 2.3-1.6 3.98-1.6s3.12.59 3.98 1.6c.81.95 1.21 2.4 1.21 4.39 0 4.2-1.93 6.66-5.19 6.66s-5.01-2.21-5.17-6.23c-.02-.12-.02-.27-.02-.4v.01zm2.23.45c0 2.72 1.1 4.2 2.95 4.2s2.95-1.57 2.95-4.45c0-2.56-1.01-3.87-2.97-3.87-1.21 0-2.16.61-2.59 1.66-.22.56-.34 1.31-.34 2.27v.2-.01z"/><radialGradient id="G" cx="0" cy="0" r="1" gradientTransform="matrix(489.45 0 0 140.451 320.32 416.087)" xlink:href="#J"><stop stop-color="#fff" stop-opacity=".46"/><stop offset=".633" stop-color="#fff" stop-opacity="0"/></radialGradient></defs></svg>'
        );
    }

    function getContribution(address owner) private view returns (string memory) {
        (uint256 ethContributed, , ,) = Crowdfund(address(this)).getContributorInfo(owner);
        return toDecimalString(ethContributed);
    }

    function getCrowdfundStatus() private view returns (CrowdfundStatus) {
        Crowdfund.CrowdfundLifecycle lifecycle =
            Crowdfund(payable(address(this))).getCrowdfundLifecycle();

        if (lifecycle == Crowdfund.CrowdfundLifecycle.Won) {
            return CrowdfundStatus.WON;
        } else if (
            lifecycle == Crowdfund.CrowdfundLifecycle.Lost ||
            lifecycle == Crowdfund.CrowdfundLifecycle.Expired
        ) {
            return CrowdfundStatus.LOST;
        } else {
            return CrowdfundStatus.LIVE;
        }
    }

    function calcAnimationDuration() private view returns (uint256) {
        return 0.26272e18 * bytes(name).length + 11.97633e18;
    }

    function calcTranslateX() private view returns (uint256) {
        return 7.42012e18 * bytes(name).length + 88.52071e18;
    }

    // Convert 18 decimals number to stringified 2 decimal number
    function toDecimalString(uint256 value) private pure returns (string memory) {
        if (value < 0.01e18) {
            return "<0.01";
        } else {
            return string.concat(
                // Integer part
                (value / 1e18).toString(),
                ".",
                // Last 2 decimals
                (value / 1e16 % 1e2).toString()
            );
        }
    }
}
