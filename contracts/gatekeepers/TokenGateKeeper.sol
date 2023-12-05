// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IGateKeeper } from "./IGateKeeper.sol";
import { ContributionRouter } from "../crowdfund/ContributionRouter.sol";

interface IERC20orERC721 {
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC1155 {
    function balanceOf(address owner, uint256 id) external view returns (uint256);
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
        address token;
        uint256 tokenId;
        uint256 minimumBalance;
    }

    event TokenGateCreated(address token, uint256 tokenId, uint256 minimumBalance);

    /// @notice Get the information for a gate identified by it's `id`.
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

        if (_gate.tokenId == 0) {
            return IERC20orERC721(_gate.token).balanceOf(participant) >= _gate.minimumBalance;
        } else {
            return
                IERC1155(_gate.token).balanceOf(participant, _gate.tokenId) >= _gate.minimumBalance;
        }
    }

    /// @notice Creates a gate that requires a minimum balance of an ERC721 or ERC20 token.
    /// @param  token The token address (e.g. ERC20 or ERC721).
    /// @param  minimumBalance The minimum balance allowed for participation.
    /// @return id The ID of the new gate.
    function createGate(address token, uint256 minimumBalance) external returns (bytes12 id) {
        return createGate(token, 0, minimumBalance);
    }

    /// @notice Creates a gate that requires a minimum balance of an ERC1155 token.
    /// @param  token The token address (ERC1155).
    /// @param  tokenId The token ID.
    /// @param  minimumBalance The minimum balance allowed for participation.
    /// @return id The ID of the new gate.
    function createGate(
        address token,
        uint256 tokenId,
        uint256 minimumBalance
    ) public returns (bytes12 id) {
        uint96 id_ = ++_lastId;
        id = bytes12(id_);

        TokenGate memory gate = TokenGate({
            token: token,
            tokenId: tokenId,
            minimumBalance: minimumBalance
        });
        gateInfo[id_] = gate;

        emit TokenGateCreated(token, tokenId, minimumBalance);
    }
}
