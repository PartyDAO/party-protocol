// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../tokens/IERC721.sol";
import "../utils/Proxy.sol";

import "./Party.sol";
import "./IPartyFactory.sol";

/// @notice Factory used to deploy new proxified `Party` instances.
contract PartyFactory is IPartyFactory {
    error NoAuthorityError();

    /// @inheritdoc IPartyFactory
    function createParty(
        Party partyImpl,
        address[] memory authorities,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp
    ) external returns (Party party) {
        // Ensure an authority is set to mint governance NFTs.
        if (authorities.length == 0) {
            revert NoAuthorityError();
        }
        // Deploy a new proxified `Party` instance.
        Party.PartyInitData memory initData = Party.PartyInitData({
            options: opts,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            authorities: authorities,
            rageQuitTimestamp: rageQuitTimestamp
        });
        party = Party(
            payable(
                new Proxy(
                    Implementation(address(partyImpl)),
                    abi.encodeCall(Party.initialize, (initData))
                )
            )
        );
        emit PartyCreated(party, opts, preciousTokens, preciousTokenIds, msg.sender);
    }
}
