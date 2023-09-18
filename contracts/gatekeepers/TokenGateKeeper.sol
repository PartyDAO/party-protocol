// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IGateKeeper } from "./IGateKeeper.sol";
import { ContributionRouter } from "../crowdfund/ContributionRouter.sol";

/**
 * @notice Compatible with both ER20s and ERC721s.
 */
interface Token {
    function balanceOf(address owner) external view returns (uint256);
}

/**
 * @notice a contract that implements an token gatekeeper
 */
contract TokenGateKeeper is IGateKeeper {
    /// @notice The address of the canonical contribution router.
    address public immutable CONTRIBUTION_ROUTER;
    // last gate id
    uint96 private _lastId;

    constructor(address contributionRouter) {
        CONTRIBUTION_ROUTER = contributionRouter;
    }

    struct TokenGate {
        Token token;
        uint256 minimumBalance;
    }

    event TokenGateCreated(Token token, uint256 minimumBalance);

    /// @notice Get the information for a gate identifyied by it's `id`.
    mapping(uint96 => TokenGate) public gateInfo;

    /// @inheritdoc IGateKeeper
    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory /* userData */
    ) external view returns (bool) {
        if (participant == CONTRIBUTION_ROUTER) {
            participant = ContributionRouter(payable(CONTRIBUTION_ROUTER)).caller();
        }
        TokenGate memory _gate = gateInfo[uint96(id)];
        return _gate.token.balanceOf(participant) >= _gate.minimumBalance;
    }

    /// @notice Creates a gate that requires a minimum balance of a token.
    /// @param  token The token address (e.g. ERC20 or ERC721).
    /// @param  minimumBalance The minimum balance allowed for participation.
    /// @return id The ID of the new gate.
    function createGate(Token token, uint256 minimumBalance) external returns (bytes12 id) {
        uint96 id_ = ++_lastId;
        id = bytes12(id_);
        gateInfo[id_].token = token;
        gateInfo[id_].minimumBalance = minimumBalance;
        emit TokenGateCreated(token, minimumBalance);
    }
}
