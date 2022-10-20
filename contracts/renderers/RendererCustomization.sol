// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "contracts/party/Party.sol";
import "./RendererStorage.sol";

abstract contract RendererCustomization {
    enum Color {
        DEFAULT,
        GREEN,
        CYAN,
        BLUE,
        PURPLE,
        PINK,
        ORANGE,
        RED
    }

    enum ColorType {
        PRIMARY,
        SECONDARY,
        LIGHT,
        DARK
    }

    RendererStorage private immutable _storage;

    constructor(RendererStorage rendererStorage) {
        _storage = rendererStorage;
    }

    function getCustomizationChoices() internal view returns (bool isDarkMode, Color color) {
        // Get the customization preset ID chosen by the crowdfund or party instance.
        uint256 presetId = _storage.getPresetFor(address(this));
        if (presetId == 0) {
            // Preset ID 0 is reserved. It is used to indicates to party instances
            // to use the same customization preset as the crowdfund.
            try Party(payable(address(this))).mintAuthority() returns (address crowdfund) {
                // Should return the crowdfund used to create the party, if the
                // party was created conventionally. Use the customization
                // preset chosen during crowdfund initialization.
                presetId = _storage.getPresetFor(crowdfund);
                // If the preset ID is still 0 (this shouldn't happen), fallback
                // to the default customization options.
                if (presetId == 0) return (false, Color.DEFAULT);
            } catch {
                // Fallback to the default customization options. May happen if
                // called from a non-party contract (eg. a crowdfund contract,
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

    function generateColorHex(Color color, ColorType colorType) internal pure returns (string memory colorHex) {
        if (color == Color.DEFAULT) {
            if (colorType == ColorType.PRIMARY) {
                return "#A7B8CF";
            } else if (colorType == ColorType.SECONDARY) {
                return "#DCE5F0";
            } else if (colorType == ColorType.LIGHT) {
                return "#91A6C3";
            } else if (colorType == ColorType.DARK) {
                return "#50586D";
            }
        } else if (color == Color.GREEN) {
            if (colorType == ColorType.PRIMARY) {
                return "#10B173";
            } else if (colorType == ColorType.SECONDARY) {
                return "#93DCB7";
            } else if (colorType == ColorType.LIGHT) {
                return "#00A25A";
            } else if (colorType == ColorType.DARK) {
                return "#005E3B";
            }
        } else if (color == Color.CYAN) {
            if (colorType == ColorType.PRIMARY) {
                return "#00C1FA";
            } else if (colorType == ColorType.SECONDARY) {
                return "#B1EFFD";
            } else if (colorType == ColorType.LIGHT) {
                return "#00B4EA";
            } else if (colorType == ColorType.DARK) {
                return "#005669";
            }
        } else if (color == Color.BLUE) {
            if (colorType == ColorType.PRIMARY) {
                return "#2C78F3";
            } else if (colorType == ColorType.SECONDARY) {
                return "#B3D4FF";
            } else if (colorType == ColorType.LIGHT) {
                return "#0E70E0";
            } else if (colorType == ColorType.DARK) {
                return "#00286A";
            }
        } else if (color == Color.PURPLE) {
            if (colorType == ColorType.PRIMARY) {
                return "#9B45DF";
            } else if (colorType == ColorType.SECONDARY) {
                return "#D2ACF2";
            } else if (colorType == ColorType.LIGHT) {
                return "#832EC9";
            } else if (colorType == ColorType.DARK) {
                return "#47196B";
            }
        } else if (color == Color.PINK) {
            if (colorType == ColorType.PRIMARY) {
                return "#FF6BF3";
            } else if (colorType == ColorType.SECONDARY) {
                return "#FFC8FB";
            } else if (colorType == ColorType.LIGHT) {
                return "#E652E2";
            } else if (colorType == ColorType.DARK) {
                return "#911A96";
            }
        } else if (color == Color.ORANGE) {
            if (colorType == ColorType.PRIMARY) {
                return "#FF8946";
            } else if (colorType == ColorType.SECONDARY) {
                return "#FFE38B";
            } else if (colorType == ColorType.LIGHT) {
                return "#E47B2F";
            } else if (colorType == ColorType.DARK) {
                return "#732700";
            }
        } else if (color == Color.RED) {
            if (colorType == ColorType.PRIMARY) {
                return "#EC0000";
            } else if (colorType == ColorType.SECONDARY) {
                return "#FFA6A6";
            } else if (colorType == ColorType.LIGHT) {
                return "#D70000";
            } else if (colorType == ColorType.DARK) {
                return "#6F0000";
            }
        }
    }
}