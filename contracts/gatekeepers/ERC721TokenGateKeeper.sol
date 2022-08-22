// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import {IGateKeeper} from "./IGateKeeper.sol";
import {IERC721} from "../tokens/IERC721.sol";

/**
 * @notice a contract that implements an ERC721 gatekeeper
 */
contract ERC721TokenGateKeeper is IGateKeeper {
    // last gate id
    uint96 private _lastId;

    struct TokenGate {
        IERC721 token;
        uint256 minimumBalance;
    }

    event ERC721TokenGateCreated(IERC721 token, uint256 minimumBalance);

    // id -> TokenGate
    mapping(uint96 => TokenGate) public gateInfo;

    /**
     * @notice defines whether or not a user can access party
     * @param  participant contributor address
     * @param  id to identify the specific strategy
     * @return bool true of false depending if the user has enough balance
     * of a particular token
     */
    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory /* userData */
    ) external view returns (bool) {
        TokenGate memory _gate = gateInfo[uint96(id)];
        return IERC721(_gate.token).balanceOf(participant) >= _gate.minimumBalance;
    }

    /**
     * @notice creates a gateway and returns id
     * @param  token ERC-721 token address
     * @param  minimumBalance minimum balance allowed for participation
     * @return id gate id
     */
    function createGate(IERC721 token, uint256 minimumBalance)
        external
        returns (bytes12 id)
    {
        uint96 id_ = ++_lastId;
        id = bytes12(id_);
        gateInfo[id_].token = token;
        gateInfo[id_].minimumBalance = minimumBalance;
        emit ERC721TokenGateCreated(token, minimumBalance);
    }
}