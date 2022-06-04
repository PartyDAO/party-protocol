// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/Proxy.sol";

import "./Party.sol";
import "./IPartyFactory.sol";

// Creates generic Party instances.
contract PartyFactory is IPartyFactory {

    error InvalidAuthorityError(address authority);

    IGlobals public immutable GLOBALS;

    IGlobals public immutable GLOBALS;
    mapping (Party => address) public partyAuthorities;

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    modifier onlyAuthority(Party party) {
        if (partyAuthorities[party] != msg.sender) {
            revert OnlyAuthorityError();
        }
        _;
    }

    // Deploy a new party instance. Afterwards, governance NFTs can be minted
    // for party members using the `PartyFactory.mint()` function.
    // `authority` is the address that can call `mint()`.
    function createParty(
        address authority,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party)
    {
        if (authority == address(0)) {
            revert InvalidAuthorityError(authority);
        }
        Party.PartyInitData memory initData = Party.PartyInitData({
            options: opts,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            // authority must call mint() through this contract
            mintAuthority: address(this)
        });
        party = Party(payable(
            new Proxy(
                GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_IMPL),
                abi.encodeCall(Party.initialize, (initData))
            )
        ));
        partyAuthorities[party] = authority;
        emit PartyCreated(party, msg.sender);
    }

    // Relinquish the ability to call `mint()`` by an authority.
    function abdicate(Party party) external onlyAuthority(party) {
        partyAuthorities[party] = address(0);
    }

    // Mint governance tokens on a party created through this factory.
    // Only the authortiy set in `createParty()` can call this function.
    function mint(
        Party party,
        address owner,
        uint256 amount,
        address delegate
    )
        external
        onlyAuthority(party)
    {
        party.mint(owner, amount, delegate);
    }
}
