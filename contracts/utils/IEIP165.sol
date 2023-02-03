// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

interface IEIP165 {
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}