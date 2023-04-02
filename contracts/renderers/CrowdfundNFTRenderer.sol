// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./RendererBase.sol";
import "../crowdfund/Crowdfund.sol";

contract CrowdfundNFTRenderer is RendererBase {
    using LibSafeCast for uint256;
    using Strings for uint256;
    using Strings for address;

    error InvalidTokenIdError();

    enum CrowdfundStatus {
        LIVE,
        WON,
        LOST
    }

    uint256 constant CROWDFUND_CARD_DATA = 0;

    constructor(
        IGlobals globals,
        RendererStorage rendererStorage,
        IFont font
    ) RendererBase(globals, rendererStorage, font) {}

    function contractURI() external view override returns (string memory) {
        (bool isDarkMode, Color color) = getCustomizationChoices();
        (string memory image, string memory banner) = getCollectionImageAndBanner(
            color,
            isDarkMode
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"',
                        generateCollectionName(),
                        '", "description":"',
                        generateCollectionDescription(),
                        '", "external_url":"',
                        generateExternalURL(),
                        '", "image":"',
                        image,
                        '", "banner":"',
                        banner,
                        '"}'
                    )
                )
            );
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address owner = Crowdfund(address(this)).ownerOf(tokenId);
        if (owner == address(0)) {
            revert InvalidTokenIdError();
        }

        // Get the customization data for this crowdfund.
        (bool isDarkMode, Color color) = getCustomizationChoices();

        // Construct metadata.
        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"',
                        generateName(owner),
                        '", "description":"',
                        generateDescription(Crowdfund(address(this)).name(), owner),
                        '", "external_url":"',
                        generateExternalURL(),
                        '", "image":"',
                        generateSVG(
                            Crowdfund(address(this)).name(),
                            getContribution(owner),
                            getCrowdfundStatus(),
                            color,
                            isDarkMode
                        ),
                        '"}'
                    )
                )
            );
    }

    function generateName(address owner) private view returns (string memory) {
        return string.concat(getContribution(owner), " ETH Contribution");
    }

    function generateExternalURL() private view returns (string memory) {
        return string.concat("https://partybid.app/join/", address(this).toHexString());
    }

    function generateDescription(
        string memory partyName,
        address owner
    ) private view returns (string memory) {
        CrowdfundStatus status = getCrowdfundStatus();
        string memory externalURL = generateExternalURL();
        string memory contribution = getContribution(owner);

        if (status == CrowdfundStatus.WON) {
            return
                string.concat(
                    partyName,
                    " has won! You can use this Party Card to activate your membership in the Party. Head to ",
                    externalURL,
                    " to activate."
                );
        } else if (status == CrowdfundStatus.LOST) {
            return
                string.concat(
                    partyName,
                    " has lost. You can use this Party Card to claim your ETH back from the Party. Head to ",
                    externalURL,
                    " to claim."
                );
        } else {
            return
                string.concat(
                    "This Party Card represents your contribution of ",
                    contribution,
                    " ETH to the ",
                    partyName,
                    " crowdfund. When the crowdfund concludes, you can use this Party Card to claim your ETH or activate your membership in the Party. During the crowdfund, Party Cards are non-transferable. Head to ",
                    externalURL,
                    " to see more."
                );
        }
    }

    function generateCollectionName() internal view returns (string memory) {
        return string.concat("Party Contributions: ", Crowdfund(address(this)).name());
    }

    function generateCollectionDescription() internal view returns (string memory) {
        return
            string.concat(
                "Party Cards in this collection represent contributions to the ",
                Crowdfund(address(this)).name(),
                " crowdfund. When the crowdfund concludes, Party Cards can be used to claim ETH or activate membership in the Party. During the crowdfund, Party Cards are non-transferable. Head to ",
                generateExternalURL(),
                " to learn more about this Party."
            );
    }

    function generateSVG(
        string memory partyName,
        string memory contributionAmount,
        CrowdfundStatus status,
        Color color,
        bool isDarkMode
    ) public view returns (string memory) {
        return
            string.concat(
                "data:image/svg+xml;base64,",
                Base64.encode(
                    abi.encodePacked(
                        // Split to avoid stack too deep errors
                        generateSVG1(color, isDarkMode),
                        generateSVG2(partyName, color),
                        generateSVG3(contributionAmount, color),
                        generateSVG4(status, color),
                        generateSVG5(partyName)
                    )
                )
            );
    }

    function generateSVG1(Color color, bool isDarkMode) private pure returns (string memory) {
        return
            string.concat(
                '<svg width="540" height="540" viewBox="0 -10 360 560" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><linearGradient id="d" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
                isDarkMode ? "#2e3847" : "#ffffff",
                '"/><stop offset="1" stop-color="',
                isDarkMode ? "#000000" : "#e6edf5",
                '"/></linearGradient><linearGradient id="e" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
                isDarkMode ? "#8091a8" : "#e6edf6",
                '"/><stop offset="1" stop-color="',
                isDarkMode ? "#2e3848" : "#bccbdd",
                '"/></linearGradient><linearGradient id="f" x1="0" x2="0" y1="1" y2="0"><stop offset="0" stop-color="',
                generateColorHex(color, ColorType.SECONDARY),
                '"/><stop offset="1" stop-color="',
                generateColorHex(color, ColorType.PRIMARY),
                '"/></linearGradient><linearGradient id="f2" x1="0" x2="0" y1="-.5" y2="1"><stop offset="0" stop-color="',
                generateColorHex(color, ColorType.SECONDARY),
                '"/><stop offset="1" stop-color="',
                generateColorHex(color, ColorType.PRIMARY),
                '"/></linearGradient><linearGradient id="h" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
                isDarkMode ? "#ffffff" : "#3f485f",
                '"/><stop offset=".5"  stop-color="',
                isDarkMode ? "#a7b8cf" : "#000000",
                '"/></linearGradient><radialGradient cx="1" cy="-.5" id="i" r="2"><stop offset="0" stop-color="#dce5f0"/><stop offset=".5" stop-color="#dce5f0" stop-opacity="0"/></radialGradient><symbol id="a" viewBox="0 0 300.15 300"><path class="s" d="M6.08 0v300M3.07 0v300M.08 0v300m9-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300"/></symbol>'
            );
    }

    function generateSVG2(
        string memory partyName,
        Color color
    ) private view returns (string memory) {
        (
            uint256 duration,
            uint256 steps,
            uint256 delay,
            uint256 translateX
        ) = calcAnimationVariables(partyName);
        return
            string.concat(
                '<symbol id="b" viewBox="0 0 300 21.15"><path class="s" d="M0 21.08h300m-300-3h300m-300-3h300m-300-3h300m-300-3h300m-300-3h300m-300-3h300M0 .08h300"/></symbol><style>.z{animation:x ',
                duration.toString(),
                "s steps(",
                steps.toString(),
                ") infinite;}.y{animation-delay:",
                delay.toString(),
                "s}@keyframes x{to{transform:translateX(-",
                translateX.toString(),
                "px)}}.o,.p{fill:",
                generateColorHex(color, ColorType.DARK),
                ";font-family:pixeldroidConsoleRegular,Console;font-size:48px}.w{animation:W 1s steps(1, jump-end) infinite;}@keyframes W{50%{fill:",
                generateColorHex(color, ColorType.LIGHT),
                "}}.s{fill:none;stroke:",
                generateColorHex(color, ColorType.PRIMARY),
                ";stroke-width:.15px}@font-face{font-family:pixeldroidConsoleRegular;src:url(",
                _font.getFont(),
                ");}</style></defs>"
            );
    }

    function generateSVG3(
        string memory contributionAmount,
        Color color
    ) private pure returns (string memory) {
        return
            string.concat(
                '<rect height="539" rx="29.5" ry="29.5" style="fill:url(#d);stroke:url(#e);" width="359" x=".5" y=".5"/><path d="M30 525.5c-8.55 0-15.5-6.95-15.5-15.5v-98c0-8.55 6.95-15.5 15.5-15.5h113.81a30.5 30.5 0 0 1 19.97 7.45l28.09 24.34a29.48 29.48 0 0 0 19.32 7.21H330c8.55 0 15.5 6.95 15.5 15.5v59c0 8.55-6.95 15.5-15.5 15.5H30Z" style="fill:',
                generateColorHex(color, ColorType.PRIMARY),
                ';stroke:url(#f)"/><path d="M330 444H30v27h300v-27Zm-219-27.5v15H36v-15h75Z" fill="',
                generateColorHex(color, ColorType.LIGHT),
                '"/><text class="p" x="33" y="431.5">',
                contributionAmount,
                "</text>"
            );
    }

    function generateSVG4(
        CrowdfundStatus status,
        Color color
    ) private pure returns (string memory) {
        string memory activeColorHex = generateColorHex(color, ColorType.DARK);
        string memory inactiveColorHex = generateColorHex(color, ColorType.LIGHT);
        return
            string.concat(
                '<use height="21.15" transform="matrix(.3 0 0 1 30 413.42)" width="300" xlink:href="#b"/><use height="21.15" transform="matrix(0 -.05 1 0 32.92 431.5)" width="300" xlink:href="#b"/><use height="21.15" transform="matrix(0 -.05 1 0 56.92 431.5)" width="300" xlink:href="#b"/><use height="21.15" transform="matrix(0 -.05 1 0 80.92 431.5)" width="300" xlink:href="#b"/><use height="21.15" transform="matrix(0 -.05 1 0 104.92 431.5)" width="300" xlink:href="#b"/><clipPath id="C1"><path d="M115 480H35a5 5 0 0 0-5 5v20a5 5 0 0 0 5 5h80a5 5 0 0 0 5-5v-20a5 5 0 0 0-5-5Zm-50.74 21.5h-8.4v-13h2.65v10.45h5.75v2.55Zm5.17 0h-2.65v-13h2.65v13Zm9.76 0h-3.35l-4.42-13h2.89l3.2 9.93 3.3-9.93h2.82l-4.44 13Zm14.96 0h-8.53v-13h8.41v2.5h-5.81v2.7h5.41v2.5h-5.41v2.8h5.93v2.5Z" /></clipPath><g clip-path="url(#C1)"><rect class="w" x="30" y="480" width="300" height="35" fill="',
                status == CrowdfundStatus.LIVE ? activeColorHex : inactiveColorHex,
                '"/></g><clipPath id="C2"><path d="M220 480h-80a5 5 0 0 0-5 5v20a5 5 0 0 0 5 5h80a5 5 0 0 0 5-5v-20a5 5 0 0 0-5-5Zm-48.84 21.5h-3.09l-2.28-9.89-2.24 9.89h-3.09l-3.23-13h2.84l2.06 9.52 2.26-9.52h2.92l2.21 9.52 2.12-9.52h2.75l-3.23 13Zm10.8.24c-3.77 0-6.46-2.8-6.46-6.73s2.69-6.75 6.46-6.75 6.41 2.8 6.41 6.75-2.67 6.73-6.41 6.73Zm19.72-.24h-3.55l-4.9-9.91v9.91h-2.53v-13h3.57l4.9 9.91v-9.91h2.52v13Zm-16.08-6.49c0 2.55-1.39 4.18-3.64 4.18s-3.69-1.63-3.69-4.18 1.41-4.2 3.69-4.2 3.64 1.63 3.64 4.2Z" /></clipPath><g clip-path="url(#C2)"><rect class="w" x="30" y="480" width="300" height="35" fill="',
                status == CrowdfundStatus.WON ? activeColorHex : inactiveColorHex,
                '"/></g><clipPath id="C3"><path d="M282.74 495.01c0 2.55-1.39 4.18-3.64 4.18s-3.69-1.63-3.69-4.18 1.41-4.2 3.69-4.2 3.64 1.63 3.64 4.2ZM330 485v20a5 5 0 0 1-5 5h-80a5 5 0 0 1-5-5v-20a5 5 0 0 1 5-5h80a5 5 0 0 1 5 5Zm-58.84 13.95h-5.75V488.5h-2.65v13h8.4v-2.55Zm14.35-3.94c0-3.94-2.67-6.75-6.41-6.75s-6.46 2.8-6.46 6.75 2.69 6.73 6.46 6.73 6.41-2.8 6.41-6.73Zm10.73 2.62c0-2.01-.95-3.11-3.16-3.72l-1.6-.48c-.94-.25-1.39-.63-1.41-1.36 0-.87.78-1.29 1.9-1.29 1.21 0 2.43.31 3.59 1.02v-2.74c-1-.54-2.26-.8-3.54-.8-2.87 0-4.69 1.5-4.69 3.86 0 1.99 1.05 3.18 3.21 3.76l1.45.41c1.02.29 1.5.61 1.5 1.44 0 .95-.71 1.5-2.04 1.5s-2.74-.48-3.94-1.38v2.8a7.38 7.38 0 0 0 4.1 1.09c2.79 0 4.64-1.56 4.64-4.11ZM308 488.5h-10.2v2.55h3.76v10.45h2.67v-10.45H308v-2.55Z" /></clipPath><g clip-path="url(#C3)"><rect class="w" x="30" y="480" width="300" height="35" fill="',
                status == CrowdfundStatus.LOST ? activeColorHex : inactiveColorHex,
                '"/></g><path d="M307.54 128.19c2.23 2.13 9.81 23.93-1.54 56.42a184.3 184.3 0 0 0-8.52-9.01c6.58-14.64 11.75-31.59 10.05-47.41Zm-59.07-68.13c19.25 52.08-33.89 116.63-48.05 132.17 2.04 5.7 3.73 10.51 5.25 15.07 28.45-30.16 75.83-100.73 42.79-147.24Zm-59.24 175.15a229.14 229.14 0 0 1-40 25.97l17.58 6.07a206.25 206.25 0 0 0 39.03-26.6 322.04 322.04 0 0 1-16.61-5.44Zm81.35 21.49a266.02 266.02 0 0 1-41.9 35.94c4.21 3.38 8.21 6.37 11.97 8.91 1.37-.91 2.72-1.83 4.07-2.78a259.48 259.48 0 0 0 35.1-32.86c-2.81-2.86-5.9-5.94-9.22-9.2Zm-133.69.23c14.84-6.44 29.13-15.2 42.38-25.55a361.48 361.48 0 0 1-14.65-6.41 205.7 205.7 0 0 1-34.06 21.06 189.9 189.9 0 0 1-10.6 5.07l16.91 5.83ZM326.25 150.6c-.06 15.08-5.71 30.79-12.03 44.27 2.35 3.22 4.47 6.41 6.3 9.55 10.53-28.27 12.04-43.96 5.71-53.81Zm-65.4-80.13c35.47 46.42-30.24 125.73-51.91 147.16 1.47 4.85 2.92 10 4.56 16.16 19.74-19.48 98.57-111.61 47.34-163.31Zm18.4 88.96c3.12 2.48 6.16 5.01 9.07 7.59 11.63-33.33 2.97-52.2.87-53.67 1.24 15.44-3.65 31.81-9.94 46.07Zm-15.09 91.04c-1.97-6.65-4.46-16.9-4.46-16.9a256.46 256.46 0 0 1-54.28 47.06 269.45 269.45 0 0 1 16.46 6.38 229.93 229.93 0 0 0 42.28-36.54Zm-6.52-29.51-3.15-19.36c-24.69 30.64-47.69 52.28-76.91 69.38l17.48 6.05c23.83-14.19 45.49-34.09 62.59-56.07Zm-78.37 93.2c8.68 5.69 25.08 8.22 36.42 2.39 11.69-7.45-1.16-16.17-15.52-19.14-19-3.93-32.58 2.36-25.98 12.03a18 18 0 0 0 5.07 4.72m-3.57.77c-6.91-4.6-13.12-13.96-.44-19.54 20.17-6.65 55.01 6.2 48.43 17.86-1.14 2.01-2.82 3.1-4.61 4.25h-.02v.02h-.03v.02h-.03v.02h-.03v.02h-.03v.02h-.02c-13.64 7.05-33.06 4.1-43.22-2.65m10.63-7.48c.48.36 4.83 3.44 9.81.96l2.61-1.44-9.07-4.62c-.95.52-1.9 1.03-2.86 1.53-.74.42-2.97 1.71-.49 3.56m-3.29 1.14c-4.56-3.05-1.5-5.06-.04-6.03 2.12-1.1 4.23-2.23 6.36-3.43 13.46 7.1 13.99 7.38 25.56 11.95l-2.67 1.58c-3.74-1.52-8.75-3.52-12.43-5.19 1.67 2.71 3.86 6.34 5.62 8.99-1.08.58-2.17 1.15-3.25 1.69-1.45-2.48-3.42-5.79-4.78-8.32-6.18 3.99-13.55-.7-14.37-1.25" style="fill:url(#f2)"/><path d="M309.28 103.41C279.02 48.51 232.39 31 201.68 31c-23.1 0-50.31 11.2-71.38 25.52 18.48 8.49 42.36 30.93 42.66 31.21-15.38-5.9-34.54-13.03-64.39-15.25a260.56 260.56 0 0 0-38.3 39.5c1.48 14.84 5.58 30.39 5.58 30.39-12.16-9.2-21.36-8.93-34.87 18.31-10.45 24.52-13.43 46.98-9.01 64.29 0 0 9.14 51.93 70.2 77.64-2.52-8.93-3.06-19.21-1.81-30.48a169.77 169.77 0 0 1-30.28-19.12c1.54-12.81 5.41-26.79 11.62-41.39 8.56-20.65 8.42-29.35 8.42-29.43.06.13 10.63 24.09 25.1 42.78 8.2-17.13 18.33-31.15 26.5-42.29l-7.3-13.08a279.8 279.8 0 0 1 35.24-36.34c3.96 2.08 9.28 4.78 13.24 6.94 16.83-14.09 37.29-27.21 59.21-35.44-13.57-22.26-31.04-37.34-31.04-37.34s53.67 5.31 81.42 30.4c6.31 1 11.89 2.89 16.76 5.59ZM56.32 210.27a136.81 136.81 0 0 0-5.31 24.25 108.25 108.25 0 0 1-11.99-17.13c.9-7.48 2.62-15.33 5.14-23.44 3.43-10.28 6.49-11.46 11.35-4.33v-.09c4.14 5.95 3.52 11.9.81 20.74Zm64.16-68.44-.09.09c-6.76-14.43-9.1-19.66-15.05-35.08l.27-.27c15.95 5.32 20.63 7.04 35.95 13.52a283.5 283.5 0 0 0-21.09 21.73Zm106.25-91.81a134.04 134.04 0 0 0-26.5 7.21 126.2 126.2 0 0 0-15.14-10.28 128.66 128.66 0 0 1 25.23-6.85c2.97-.36 12.07-1.54 20.01 4.69v-.09c4.77 3.69.27 4.6-3.6 5.32Z" style="fill:url(#h)"/>'
            );
    }

    function generateSVG5(string memory partyName) private view returns (string memory) {
        return
            string.concat(
                '<clipPath id="clip"><path d="M330 444H30v27h300"/></clipPath><g clip-path="url(#clip)"><g class="z"><text class="p" x="327" y="465">',
                partyName,
                '</text></g><g class="z y"><text class="p" x="327" y="465">',
                partyName,
                "</text></g></g>",
                _storage.readFile(CROWDFUND_CARD_DATA)
            );
    }

    function getContribution(address owner) private view returns (string memory amount) {
        (uint256 ethContributed, , , ) = Crowdfund(address(this)).getContributorInfo(owner);
        return formatAsDecimalString(ethContributed, 18, 4);
    }

    function getCrowdfundStatus() private view returns (CrowdfundStatus) {
        Crowdfund.CrowdfundLifecycle lifecycle = Crowdfund(payable(address(this)))
            .getCrowdfundLifecycle();

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

    function calcAnimationVariables(
        string memory partyName
    ) private pure returns (uint256 duration, uint256 steps, uint256 delay, uint256 translateX) {
        translateX = bytes(partyName).length * 30 + 300;
        duration = translateX / 56;
        if (duration % 2 != 0) {
            // Make duration even so that the animation delay is always exactly
            // half of the duration
            duration += 1;
        }
        delay = duration / 2;
        steps = translateX / 6;
    }
}
