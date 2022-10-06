// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "solmate/utils/SSTORE2.sol";

contract RendererStorage {
    error AlreadySet();
    error OnlyOwnerError(address caller, address owner);

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

    struct CardCustomization {
        bool hasBeenSet;
        bool isDarkMode;
        Color color;
    }

    address immutable _owner;

    /// @notice Customization options for rendering cards by crowdfund/party address.
    mapping(address => CardCustomization) public customizations;
    /// @notice Addresses where URI data chunks are stored by index.
    mapping(uint256 => address) public files;

    constructor(address owner) {
        _owner = owner;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OnlyOwnerError(msg.sender, _owner);
        _;
    }

    function customizeCard(address instance, bool isDarkMode, Color color) external {
        CardCustomization storage card = customizations[instance];

        if (card.hasBeenSet) revert AlreadySet();

        card.hasBeenSet = true;
        card.isDarkMode = isDarkMode;
        card.color = color;
    }

    function saveFile(uint256 index, string calldata fileContent) external onlyOwner {
        files[index] = SSTORE2.write(bytes(fileContent));
    }

    function readFile(uint256 index) external view returns (string memory) {
        return string(SSTORE2.read(files[index]));
    }
}