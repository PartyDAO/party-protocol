// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "solmate/utils/SSTORE2.sol";

contract RendererStorage {
    error OnlyOwnerError(address caller, address owner);

    address immutable _owner;

    /// @notice Addresses where URI data chunks are stored.
    mapping(uint256 => address) public files;

    constructor(address owner) {
        _owner = owner;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OnlyOwnerError(msg.sender, _owner);
        _;
    }

    function saveFile(uint256 index, string calldata fileContent) external onlyOwner {
        files[index] = SSTORE2.write(bytes(fileContent));
    }

    function readFile(uint256 index) external view returns (string memory) {
        return string(SSTORE2.read(files[index]));
    }
}
