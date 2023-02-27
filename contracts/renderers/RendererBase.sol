// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "contracts/party/Party.sol";
import "../globals/IGlobals.sol";
import "./fonts/IFont.sol";
import "./IERC721Renderer.sol";
import "./RendererStorage.sol";

abstract contract RendererBase is IERC721Renderer {
    using Strings for uint256;
    using Strings for string;

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

    IGlobals immutable _GLOBALS;
    RendererStorage immutable _storage;
    IFont immutable _font;

    constructor(IGlobals globals, RendererStorage rendererStorage, IFont font) {
        _GLOBALS = globals;
        _storage = rendererStorage;
        _font = font;
    }

    function contractURI() external view virtual returns (string memory);

    function getCollectionImageAndBanner(
        Color color,
        bool isDarkMode
    ) internal pure returns (string memory image, string memory banner) {
        if (isDarkMode) {
            if (color == Color.GREEN) {
                image = "QmdcjXrxj7EimjuNTLQp1uKM2zYhuF1WVkVjF6TpfNNXrf";
                banner = "QmR3vqAV17SJiwksiCHV1cLQuf9TKZuar8NQu8GmKkHRXM";
            } else if (color == Color.CYAN) {
                image = "QmS678DTkTTzFQEDiqj3AsW6wt6bi4bNhWbKcBM29HBhhB";
                banner = "QmYSbXyPh9Lx2wmv6Z7SK8iFD9kyADxtaohV1gv6ZVKFj4";
            } else if (color == Color.BLUE) {
                image = "QmX2k8beAjyVhPk1ZrK6KrwbqLk3fRNPPmknRti7zEtGQa";
                banner = "QmaXN8MbcrjkHPt97Z7xeuTCx6wPkJ9xZN7ExZZwMabspy";
            } else if (color == Color.PURPLE) {
                image = "Qmf8SrxKH3QZQCEzcMbA3UoJGZ1j2coTLaQFptWhZZvqhg";
                banner = "QmWhpo9kN2Nf8ioWb7BKwqsCQKt3M2TduHPNqMqXz9jUK4";
            } else if (color == Color.PINK) {
                image = "QmV5eT9DWvU5BJa4LVSemkoDKyjJBC56adk2JLWMXYEQfn";
                banner = "QmP2NTyvMQ5yN1RY4nH1HfoTX2r6Ug6WZfN9GFf9toak8M";
            } else if (color == Color.ORANGE) {
                image = "QmPirB7VFaao2ZUxLtM5WTCwZhE7c9Uy2heyNZF5t9PgsS";
                banner = "QmUMgkjhrxedcLUvWt8VKrZdvrCGmjxWDSDXfm2M96nKUx";
            } else if (color == Color.RED) {
                image = "QmNRZ3syuEiiAkWYRFs9BpQ5M38wv8tEu17J2sYwmMdeta";
                banner = "QmQV1EjzwQsXdgi6C6ubfopZrprk6Ab9LVnggZBgJDg5C2";
            } else {
                image = "QmNwGtGyYwDfS6ghQbDw5a9buv7auFXz63W3rDhzmxjVhw";
                banner = "QmYUujTBgH6RTswZSiSzuy2GUojE6H9edaXeoSwwvh2T7o";
            }
        } else {
            if (color == Color.GREEN) {
                image = "QmR7t2g2hrkMYyzhUMEANzEGX74FQcbg3c7eTvCcQucMst";
                banner = "Qmc3zRfT6nC2G1KgoWpCvLDVjNi7x7KFgwButecj3sq9qg";
            } else if (color == Color.CYAN) {
                image = "QmeiBRb9muNXej3dn4usjjdtbUpgYASfA5jmWqJRshivGH";
                banner = "QmcsvMB2xiBKKMyKsBkC51TjWnyk42nNJnsudoGFsvvXCt";
            } else if (color == Color.BLUE) {
                image = "QmaErgGsanUTo73RMgvizMg3c7x1d1X4t76Tti22Pc1xan";
                banner = "QmSjhHF994xBd7wavV4mhj7GpZmw5euQUBxpiPbbmxExqp";
            } else if (color == Color.PURPLE) {
                image = "QmeVJTcUpKQFSz5aBsVpQk8quoXEEZBNPAAMo3wHvdRzHa";
                banner = "QmYx6aHYGitr6p8dHUa7n4nyew3pWy1Mfdn8fpFLejmhHC";
            } else if (color == Color.PINK) {
                image = "QmY4JJkBEeHVYHdfCCXPd7bWkAhNRxuKTWdf9MssGxSmCG";
                banner = "QmQH5CFf3qXG2oymGzwTDgUmPFBsaTw2Qbfhjk58VHcABd";
            } else if (color == Color.ORANGE) {
                image = "QmYhB3vjBLPwPTC5SBidNbZhB5oBMBMpKy4g6ejTxmGLkK";
                banner = "QmRP8cVjJyPRV7wXs5ApwbCFyTBpHXmHsDexbcN4o7aomd";
            } else if (color == Color.RED) {
                image = "QmfG8HPMEsKwKJ8xX3i2JhJtCskuiUjZLe8NhvXFdYyFR2";
                banner = "QmazXbqfFtQexkwFDbYkyvLF4xRSDrmEVQS4PSAs2ZtxDn";
            } else {
                image = "QmZKE4XkPvU7Z8CdgK2Cn7gLQ4t8CDkkfnR1j5bZ2AfRJu";
                banner = "QmTKCqLUQJt3VxGuUqLMj1jcCRRsaZwY4k757Wb7YPzmH2";
            }
        }

        image = string.concat("ipfs://", image);
        banner = string.concat("ipfs://", banner);
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

    function generateColorHex(
        Color color,
        ColorType colorType
    ) internal pure returns (string memory colorHex) {
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

    function formatAsDecimalString(
        uint256 n,
        uint256 decimals,
        uint256 maxChars
    ) internal pure returns (string memory) {
        string memory str = n.toString();
        uint256 oneUnit = 10 ** decimals;
        if (n < 10 ** (decimals - 2)) {
            return "&lt;0.01";
        } else if (n < oneUnit) {
            // Preserve leading zeros for decimals.
            // (eg. if 0.01, `n` will "1" so we need to prepend a "0").
            return
                string.concat("0.", prependNumWithZeros(str, decimals).substring(0, maxChars - 1));
        } else if (n >= 1000 * oneUnit) {
            return str.substring(0, maxChars);
        } else {
            uint256 i = bytes((n / oneUnit).toString()).length;
            return string.concat(str.substring(0, i), ".", str.substring(i, maxChars));
        }
    }

    function prependNumWithZeros(
        string memory numStr,
        uint256 expectedLength
    ) internal pure returns (string memory) {
        uint256 length = bytes(numStr).length;
        if (length < expectedLength) {
            for (uint256 i; i < expectedLength - length; ++i) {
                numStr = string.concat("0", numStr);
            }
        }

        return numStr;
    }
}
