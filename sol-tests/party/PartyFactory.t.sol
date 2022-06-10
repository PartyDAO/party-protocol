// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/globals/Globals.sol";
import "../TestUtils.sol";

contract DummyPartyImpl is Implementation {
    event DummyPartyImplInitializeCalled(Party.PartyInitData initData);
    event DummyPartyImplMintCalled(address owner, uint256 amount, address delegate);

    function initialize(Party.PartyInitData memory initData) external onlyDelegateCall {
        emit DummyPartyImplInitializeCalled(initData);
    }

    function mint(address owner, uint256 amount, address delegate) external {
        emit DummyPartyImplMintCalled(owner, amount, delegate);
    }
}

contract PartyFactoryTest is Test, TestUtils {
    event DummyPartyImplInitializeCalled(Party.PartyInitData initData);
    event DummyPartyImplMintCalled(address owner, uint256 amount, address delegate);

    Globals globals = new Globals(address(this));
    DummyPartyImpl partyImpl = new DummyPartyImpl();
    PartyFactory factory = new PartyFactory(globals);
    Party.PartyOptions defaultPartyOptions;

    constructor() {
        defaultPartyOptions.name = 'PARTY';
        defaultPartyOptions.symbol = 'PR-T';
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.voteDuration = 1 days;
        defaultPartyOptions.governance.executionDelay = 8 hours;
        defaultPartyOptions.governance.passThresholdBps = 0.51e4;
        defaultPartyOptions.governance.totalVotingPower = 100e18;
        globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));
    }

    function _createPreciouses(uint256 count)
        private
        view
        returns (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds)
    {
        preciousTokens = new IERC721[](count);
        preciousTokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            preciousTokens[i] = IERC721(_randomAddress());
            preciousTokenIds[i] = _randomUint256();
        }
    }

    function testcreateParty_works() external {
        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        vm.expectEmit(false, false, false, true);
        emit DummyPartyImplInitializeCalled(Party.PartyInitData({
            mintAuthority: address(factory),
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            options: defaultPartyOptions
        }));
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        assertEq(factory.partyAuthorities(party), authority);
    }

    function testMint_works() external {
        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        {
            address owner = _randomAddress();
            address delegate = _randomAddress();
            uint256 amount = _randomUint256();
            vm.expectEmit(false, false, false, true);
            emit DummyPartyImplMintCalled(owner, amount, delegate);
            vm.prank(authority);
            factory.mint(party, owner, amount, delegate);
        }
    }

    function testMint_onlyAuthorityCanCall() external {
        address authority = _randomAddress();
        address notAuthority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        {
            address owner = _randomAddress();
            address delegate = _randomAddress();
            uint256 amount = _randomUint256();
            vm.expectRevert(abi.encodeWithSelector(
                PartyFactory.OnlyAuthorityError.selector
            ));
            vm.prank(notAuthority);
            factory.mint(party, owner, amount, delegate);
        }
    }

    function testAbdicate_works() external {
        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        assertEq(factory.partyAuthorities(party), authority);
        vm.prank(authority);
        factory.abdicate(party);
        assertEq(factory.partyAuthorities(party), address(0));
    }
}
