// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title The interface on-chain font contracts must implement to be added to the registry.
///
/// Uploading fonts to chain is open ended and up to the dev (SSTORE2 or hardcoded string or etc).
///
/// As long as the font contract implements this interface and has immutable font data, it can be added
/// to the registry.
///
/// @author @0x_beans
interface IFont {
    /// @notice Address that uploaded font for credits
    function fontUploader() external returns (address);

    /// @notice Format type of font (eg. ttf, woff, otf, etc). Must be lowercase.
    ///         This info is necessary so projects know how to properly render the fonts.
    function fontFormatType() external returns (string memory);

    /// @notice Font name (ie. 'space-grotesk'). Must be lowercase.
    function fontName() external returns (string memory);

    /// @notice Weight used by the font (eg. bold, medium, light, etc). Must be lowercase.
    ///         Necessary to differentiate uploaded fonts that are the same but different weights.
    function fontWeight() external returns (string memory);

    /// @notice Style used by the font (eg. lowercase normal, italic, oblique, etc). Must be lowercase.
    //          Necessary to differentiate uploaded fonts that are the same but different style.
    function fontStyle() external returns (string memory);

    /// @notice The full base64 encoded font with data URI scheme prefix
    ///         (eg. 'data:font/ttf;charset=utf-8;base64,').
    function getFont() external view returns (string memory);
}
