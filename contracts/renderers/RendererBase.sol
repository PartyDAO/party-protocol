// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Strings } from "../utils/vendor/Strings.sol";
import { Color } from "../utils/LibRenderer.sol";
import { Party } from "contracts/party/Party.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { IFont } from "./fonts/IFont.sol";
import { IERC721Renderer } from "./IERC721Renderer.sol";
import { RendererStorage } from "./RendererStorage.sol";

abstract contract RendererBase is IERC721Renderer {
    using Strings for uint256;
    using Strings for string;

    IGlobals immutable _GLOBALS;
    RendererStorage immutable _storage;
    IFont immutable _font;

    constructor(IGlobals globals, RendererStorage rendererStorage, IFont font) {
        _GLOBALS = globals;
        _storage = rendererStorage;
        _font = font;
    }

    function contractURI() external view virtual returns (string memory);

    function getCustomizationChoices() internal view returns (bool isDarkMode, Color color) {
        // Get the customization preset ID chosen by the crowdfund or party instance.
        uint256 presetId = _storage.getPresetFor(address(this));

        if (presetId == 0) {
            // Preset ID 0 is reserved. It is used to indicate to party instances
            // to use the same customization preset as the crowdfund.
            (bool success, bytes memory result) = address(this).staticcall(
                // Call mintAuthority
                abi.encodeWithSignature("mintAuthority()")
            );

            if (success && result.length == 32) {
                address crowdfund = abi.decode(result, (address));
                // Should return the crowdfund used to create the party, if the
                // party was created conventionally. Use the customization
                // preset chosen during crowdfund initialization.
                presetId = _storage.getPresetFor(crowdfund);
                // If the preset ID is still 0 (this shouldn't happen), fallback
                // to the default customization options.
                if (presetId == 0) return (false, Color.DEFAULT);
            } else {
                // Fallback to the default customization options. May happen if
                // called from a non-party contract (e.g. a crowdfund contract,
                // although this shouldn't happen).
                return (false, Color.DEFAULT);
            }
        }

        // Get the customization data for the preset chosen.
        bytes memory customizationData = _storage.customizationPresets(presetId);
        if (customizationData.length == 0) {
            // If the customization preset doesn't exist, fallback to the
            // default customization options.
            return (false, Color.DEFAULT);
        }

        // Check version number. Fallback to default if using different version.
        if (abi.decode(customizationData, (uint8)) == 1) {
            (, isDarkMode, color) = abi.decode(customizationData, (uint8, bool, Color));
        } else {
            // Fallback to the default customization options.
            return (false, Color.DEFAULT);
        }
    }
}
