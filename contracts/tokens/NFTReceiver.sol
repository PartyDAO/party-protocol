// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC721TokenReceiver } from "../vendor/solmate/ERC721.sol";
import { ERC1155TokenReceiverBase } from "../vendor/solmate/ERC1155.sol";
import { EIP165 } from "../utils/EIP165.sol";

/// @dev the override issues mentioned in  ./ERC721Receiver may have something to do with
///      importing: your modified solmate ERC721 
///      (which contains ERC721, ERC721TokenReciever which is implemented, IERC721, and EIP165 which is overriden), another EIP165. and your IERC721Reciever
///      — that's 2 imports w/ overlapping different functions

contract NFTReceiver is EIP165, ERC721TokenReceiver, ERC1155TokenReceiverBase {

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return
            EIP165.supportsInterface(interfaceId) ||
            interfaceId == type(ERC721TokenReceiver).interfaceId ||
            interfaceId == type(ERC1155TokenReceiverBase).interfaceId;
    }

}