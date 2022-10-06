// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "solmate/utils/SSTORE2.sol";
import "./IFont.sol";

// TODO: Move font to its own private repo
contract PixeldroidConsoleFont is IFont {
    error OnlyOwnerError(address caller, address owner);

    /// @inheritdoc IFont
    address public constant fontUploader = address(0);

    /// @inheritdoc IFont
    string public constant fontName = "pixeldroidConsole";

    /// @inheritdoc IFont
    string public constant fontFormatType = "ttf";

    /// @inheritdoc IFont
    string public constant fontWeight = "regular";

    /// @inheritdoc IFont
    string public constant fontStyle = "normal";

    /// @notice Address that can upload/update the font file. Will be `address(0)` when finalized.
    address public owner;

    /// @notice Addresses where font file chunks are stored.
    mapping(uint256 => address) public files;

    modifier onlyOwner() {
        address owner_ = owner;
        if (msg.sender != owner_) revert OnlyOwnerError(msg.sender, owner_);
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    /// @inheritdoc IFont
    function getFont() external view returns (string memory) {
        return string(abi.encodePacked(SSTORE2.read(files[0]), SSTORE2.read(files[1])));
    }

    function saveFile(uint256 index, string calldata fileContent) external onlyOwner {
        files[index] = SSTORE2.write(bytes(fileContent));

        // After uploading the last font file chunks, remove access from owner and finalize font.
        if (index == 1) {
            delete owner;
        }
    }
}
