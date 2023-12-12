// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Globals } from "../../contracts/globals/Globals.sol";
import { Party } from "../../contracts/party/Party.sol";
import { PartyFactory } from "../../contracts/party/PartyFactory.sol";
import { BondingCurveAuthority } from "../../contracts/authorities/BondingCurveAuthority.sol";
import "../TestUtils.sol";

contract BondingCurveAuthorityTest is TestUtils {
    event TreasuryFeeUpdated(uint16 previousTreasuryFee, uint16 newTreasuryFee);
    event PartyDaoFeeUpdated(uint16 previousPartyDaoFee, uint16 newPartyDaoFee);
    event PartyCardsBought(
        Party indexed party,
        address indexed buyer,
        uint256[] tokenIds,
        uint256 totalPrice,
        uint256 partyDaoFee,
        uint256 treasuryFee,
        uint256 creatorFee
    );
    event PartyCardsSold(
        Party indexed party,
        address indexed seller,
        uint256[] tokenIds,
        uint256 sellerProceeds,
        uint256 partyDaoFee,
        uint256 treasuryFee,
        uint256 creatorFee
    );

    Globals globals;
    MockBondingCurveAuthority authority;
    Party partyImpl;
    PartyFactory factory;

    Party.PartyOptions opts;

    address payable PARTY_DAO;
    uint16 TREASURY_FEE_BPS = 0.1e4; // 10%
    uint16 PARTY_DAO_FEE_BPS = 0.025e4; // 2.5%
    uint16 CREATOR_FEE_BPS = 0.025e4; // 2.5%

    function setUp() public {
        PARTY_DAO = _randomAddress();

        globals = new Globals(PARTY_DAO);
        authority = new MockBondingCurveAuthority(PARTY_DAO, 100, 100);
        partyImpl = new Party(globals);
        factory = new PartyFactory(globals);

        address[] memory hosts = new address[](1);
        hosts[0] = _randomAddress();
        opts.name = "PARTY";
        opts.symbol = "PRT";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = 1 hours;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 301;

        // Set a default treasury fee
        vm.prank(PARTY_DAO);
        authority.setTreasuryFee(TREASURY_FEE_BPS);

        // Set a default Party DAO fee
        vm.prank(PARTY_DAO);
        authority.setPartyDaoFee(PARTY_DAO_FEE_BPS);
    }

    function _createParty(
        uint16 creatorFee
    ) internal returns (Party party, address payable creator, uint256 initialPrice) {
        creator = _randomAddress();

        initialPrice = 0.001 ether;
        initialPrice =
            (initialPrice *
                (1e4 + authority.treasuryFeeBps() + authority.partyDaoFeeBps() + creatorFee)) /
            1e4;

        vm.deal(creator, initialPrice);
        vm.prank(creator);
        party = authority.createParty{ value: initialPrice }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: factory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFee: creatorFee
            })
        );
    }

    function test_initialize_revertIfGreaterThanMaxPartyDaoFee() public {
        uint16 maxPartyDaoFeeBps = 250;
        vm.expectRevert(BondingCurveAuthority.InvalidPartyDaoFee.selector);
        new BondingCurveAuthority(PARTY_DAO, maxPartyDaoFeeBps + 1, TREASURY_FEE_BPS);
    }

    function test_initialize_revertIfGreaterThanMaxTreasuryFee() public {
        uint16 maxTreasuryFeeBps = 1000;
        vm.expectRevert(BondingCurveAuthority.InvalidTreasuryFee.selector);
        new BondingCurveAuthority(PARTY_DAO, PARTY_DAO_FEE_BPS, maxTreasuryFeeBps + 1);
    }

    function test_createParty_works() public {
        (Party party, address payable creator, ) = _createParty(CREATOR_FEE_BPS);

        uint256 expectedBondingCurvePrice = 0.001 ether;
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;
        uint256 expectedTreasuryFee = (expectedBondingCurvePrice * TREASURY_FEE_BPS) / 1e4;
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        (address payable partyCreator, uint80 supply, uint16 creatorFee) = authority.partyInfos(
            party
        );

        assertEq(partyCreator, creator);
        assertEq(supply, 1);
        assertEq(creatorFee, CREATOR_FEE_BPS);
        assertEq(party.balanceOf(creator), 1);
        assertEq(party.getVotingPowerAt(creator, uint40(block.timestamp), 0), 0.1 ether);
        assertEq(address(party).balance, expectedTreasuryFee);
        assertEq(creator.balance, expectedCreatorFee);
        assertEq(
            address(authority).balance,
            // Creator fee is held in BondingCurveAuthority until claimed.
            expectedBondingCurvePrice + expectedPartyDaoFee
        );
    }

    function test_createParty_revertIfGreaterThanMaxCreatorFee() public {
        uint16 maxCreatorFeeBps = 500;
        vm.expectRevert(BondingCurveAuthority.InvalidCreatorFee.selector);
        authority.createParty(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: factory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFee: maxCreatorFeeBps + 1
            })
        );
    }

    function test_buyPartyCards_works()
        public
        returns (
            Party party,
            address payable creator,
            uint256 initialBalanceExcludingPartyDaoFee,
            address buyer,
            uint256 expectedBondingCurvePrice
        )
    {
        (party, creator, ) = _createParty(CREATOR_FEE_BPS);

        initialBalanceExcludingPartyDaoFee =
            address(authority).balance -
            authority.partyDaoFeeClaimable();

        uint256 expectedPriceToBuy = authority.getPriceToBuy(party, 10);
        expectedBondingCurvePrice =
            (expectedPriceToBuy * 1e4) /
            (1e4 + TREASURY_FEE_BPS + PARTY_DAO_FEE_BPS + CREATOR_FEE_BPS);
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;
        uint256 expectedTreasuryFee = (expectedBondingCurvePrice * TREASURY_FEE_BPS) / 1e4;
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        uint256 beforePartyTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 beforePartyBalance = address(party).balance;
        uint256 beforeAuthorityBalance = address(authority).balance;
        uint256 beforeCreatorBalance = creator.balance;

        buyer = _randomAddress();
        vm.deal(buyer, expectedPriceToBuy);
        vm.prank(buyer);

        {
            uint256[] memory tokenIds = new uint256[](10);
            for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

            vm.expectEmit(true, true, true, true);
            emit PartyCardsBought(
                party,
                buyer,
                tokenIds,
                expectedPriceToBuy,
                expectedPartyDaoFee,
                expectedTreasuryFee,
                expectedCreatorFee
            );
        }

        authority.buyPartyCards{ value: expectedPriceToBuy }(party, 10, address(0));

        (, uint80 supply, ) = authority.partyInfos(party);

        assertEq(party.balanceOf(buyer), 10);
        assertEq(
            party.getGovernanceValues().totalVotingPower,
            beforePartyTotalVotingPower + 1 ether
        );
        assertEq(party.getVotingPowerAt(buyer, uint40(block.timestamp), 0), 1 ether);
        assertEq(supply, 11);
        assertEq(buyer.balance, 0);
        assertEq(
            address(authority).balance - beforeAuthorityBalance,
            // Creator fee is held in BondingCurveAuthority until claimed.
            expectedBondingCurvePrice + expectedPartyDaoFee
        );
        assertEq(address(party).balance - beforePartyBalance, expectedTreasuryFee);
        assertEq(creator.balance - beforeCreatorBalance, expectedCreatorFee);
    }

    function test_buyPartyCards_revertIfGreaterThanPriceToBuy() public {
        (Party party, , ) = _createParty(CREATOR_FEE_BPS);

        uint256 priceToBuy = authority.getPriceToBuy(party, 10);

        vm.expectRevert(BondingCurveAuthority.InvalidMessageValue.selector);
        authority.buyPartyCards{ value: priceToBuy + 1 }(party, 10, address(0));
    }

    function test_buyPartyCards_revertIfLessThanPriceToBuy() public {
        (Party party, , ) = _createParty(CREATOR_FEE_BPS);

        uint256 priceToBuy = authority.getPriceToBuy(party, 10);

        vm.expectRevert(BondingCurveAuthority.InvalidMessageValue.selector);
        authority.buyPartyCards{ value: priceToBuy - 1 }(party, 10, address(0));
    }

    function test_buyPartyCards_revertIfZeroAmount() public {
        (Party party, , ) = _createParty(CREATOR_FEE_BPS);

        vm.expectRevert(BondingCurveAuthority.InvalidMessageValue.selector);
        authority.buyPartyCards(party, 0, address(0));
    }

    function test_buyPartyCards_revertIfPartyInfoNotFound() public {
        Party party = Party(payable(_randomAddress()));

        vm.expectRevert(BondingCurveAuthority.PartyNotSupported.selector);
        authority.buyPartyCards(party, 10, address(0));
    }

    function test_sellPartyCards_works() public {
        (
            Party party,
            address payable creator,
            uint256 initialBalanceExcludingPartyDaoFee,
            address buyer,
            uint256 expectedBondingCurvePrice
        ) = test_buyPartyCards_works();

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

        uint256 expectedSaleProceeds = authority.getSaleProceeds(party, 10);
        expectedBondingCurvePrice =
            (expectedSaleProceeds * 1e4) /
            (1e4 - TREASURY_FEE_BPS - PARTY_DAO_FEE_BPS - CREATOR_FEE_BPS);
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;
        uint256 expectedTreasuryFee = (expectedBondingCurvePrice * TREASURY_FEE_BPS) / 1e4;
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        uint256 beforePartyTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 beforePartyBalance = address(party).balance;
        uint256 beforeCreatorBalance = creator.balance;

        vm.prank(buyer);

        vm.expectEmit(true, true, true, true);
        emit PartyCardsSold(
            party,
            buyer,
            tokenIds,
            expectedSaleProceeds,
            expectedPartyDaoFee,
            expectedTreasuryFee,
            expectedCreatorFee
        );

        authority.sellPartyCards(party, tokenIds);

        (, uint80 supply, ) = authority.partyInfos(party);

        assertEq(supply, 1);
        assertEq(party.balanceOf(buyer), 0);
        assertEq(
            party.getGovernanceValues().totalVotingPower,
            beforePartyTotalVotingPower - 1 ether
        );
        assertEq(party.getVotingPowerAt(buyer, uint40(block.timestamp), 0), 0);
        assertEq(buyer.balance, expectedSaleProceeds);
        assertEq(
            address(authority).balance,
            // Should only be the initial balance and the unclaimed Party DAO
            // fees leftover.
            initialBalanceExcludingPartyDaoFee + authority.partyDaoFeeClaimable()
        );
        assertEq(address(party).balance - beforePartyBalance, expectedTreasuryFee);
        assertEq(creator.balance - beforeCreatorBalance, expectedCreatorFee);
    }

    function test_sellPartyCards_isApprovedForAll() public {
        (Party party, , , address buyer, ) = test_buyPartyCards_works();

        address approved = _randomAddress();

        vm.prank(buyer);
        party.setApprovalForAll(approved, true);

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

        vm.prank(approved);
        authority.sellPartyCards(party, tokenIds);
    }

    function test_sellPartyCards_getApproved() public {
        (Party party, , , address buyer, ) = test_buyPartyCards_works();

        address approved = _randomAddress();
        uint256 tokenId = 2;

        vm.prank(buyer);
        party.approve(approved, tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(approved);
        authority.sellPartyCards(party, tokenIds);
    }

    function test_sellPartyCards_revertIfNotApproved() public {
        (Party party, , , , ) = test_buyPartyCards_works();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.sellPartyCards(party, tokenIds);
    }

    function test_setTreasuryFee_works(uint16 newTreasuryFee) public {
        vm.assume(newTreasuryFee <= 1000);

        vm.expectEmit(true, true, true, true);
        emit TreasuryFeeUpdated(authority.treasuryFeeBps(), newTreasuryFee);

        vm.prank(PARTY_DAO);
        authority.setTreasuryFee(newTreasuryFee);

        assertEq(authority.treasuryFeeBps(), newTreasuryFee);
    }

    function test_setTreasuryFee_revertItNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.setTreasuryFee(0);
    }

    function test_setPartyDaoFee_works(uint16 newPartyDaoFee) public {
        vm.assume(newPartyDaoFee <= 250);

        vm.expectEmit(true, true, true, true);
        emit PartyDaoFeeUpdated(authority.partyDaoFeeBps(), newPartyDaoFee);

        vm.prank(PARTY_DAO);
        authority.setPartyDaoFee(newPartyDaoFee);

        assertEq(authority.partyDaoFeeBps(), newPartyDaoFee);
    }

    function test_setPartyDaoFee_revertItNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.setPartyDaoFee(0);
    }

    function test_setCreatorFee_works(uint16 newCreatorFee) public {
        vm.assume(newCreatorFee <= 250);

        (Party party, address payable creator, ) = _createParty(CREATOR_FEE_BPS);

        vm.prank(creator);
        authority.setCreatorFee(party, newCreatorFee);

        (, , uint16 creatorFee) = authority.partyInfos(party);
        assertEq(creatorFee, newCreatorFee);
    }

    function test_setCreatorFee_revertIfNotCreator() public {
        (Party party, , ) = _createParty(CREATOR_FEE_BPS);

        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.setCreatorFee(party, 0);
    }

    function test_claimPartyDaoFees_works() public {
        _createParty(CREATOR_FEE_BPS);

        uint256 expectedBondingCurvePrice = 0.001 ether;
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;

        vm.prank(PARTY_DAO);
        authority.claimPartyDaoFees();

        assertEq(address(authority).balance, expectedBondingCurvePrice);
        assertEq(PARTY_DAO.balance, expectedPartyDaoFee);
    }

    function test_claimPartyDaoFees_revertIfNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.claimPartyDaoFees();
    }
}

contract MockBondingCurveAuthority is BondingCurveAuthority {
    constructor(
        address payable partyDao,
        uint16 initialPartyDaoFeeBps,
        uint16 initialTreasuryFeeBps
    ) BondingCurveAuthority(partyDao, initialPartyDaoFeeBps, initialTreasuryFeeBps) {}

    function getBondingCurvePrice(
        uint256 lowerSupply,
        uint256 amount
    ) external pure returns (uint256) {
        return super._getBondingCurvePrice(lowerSupply, amount);
    }
}
