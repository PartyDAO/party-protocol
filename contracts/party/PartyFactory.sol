// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Creates generic Party instances.
contract PartyFactory {
    event PartyCreated(Party party, address creator);

    IGlobals public immutable GLOBALS;

    mapping (Party => address) public partyAuthorities;

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    modifier onlyAuthority(Party party) {
        require(partyAuthorities[party] == msg.sender);
        _;
    }

    // Deploy a new party instance. Afterwards, governance NFTs can be minted
    // for party members using the `PartyFactory.mint()` function.
    // `authority` is the address that can call `mint()`.
    function createParty(
        address authority,
        Party.PartyOptions calldata opts,
        IERC721 preciousToken,
        uint256 preciousTokenId
    )
        external
        returns (Party party)
    {
        require(authority != address(0));
        Party.PartyInitData memory initData = new Party.PartyInitData({
            options: opts,
            preciousToken: preciousToken,
            preciousTokenId: preciousTokenId
        });
        party = Party(address(new PartyProxy(abi.encode(initData))));
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
        IParty party,
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
