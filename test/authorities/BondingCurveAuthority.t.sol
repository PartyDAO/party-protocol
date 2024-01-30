// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Party } from "../../contracts/party/Party.sol";
import { PartyFactory } from "../../contracts/party/PartyFactory.sol";
import { BondingCurveAuthority } from "../../contracts/authorities/BondingCurveAuthority.sol";
import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { MetadataProvider } from "contracts/renderers/MetadataProvider.sol";
import { ProposalStorage } from "../../contracts/proposals/ProposalStorage.sol";
import { Test } from "forge-std/Test.sol";
import { IERC721 } from "contracts/tokens/IERC721.sol";

contract BondingCurveAuthorityTest is SetupPartyHelper {
    event BondingCurvePartyCreated(
        Party indexed party,
        address indexed creator,
        BondingCurveAuthority.BondingCurvePartyOptions partyOpts
    );
    event TreasuryFeeUpdated(uint16 previousTreasuryFee, uint16 newTreasuryFee);
    event PartyDaoFeeUpdated(uint16 previousPartyDaoFee, uint16 newPartyDaoFee);
    event CreatorFeeUpdated(uint16 previousCreatorFee, uint16 newCreatorFee);
    event PartyDaoFeesClaimed(uint96 amount);
    event PartyCardsBought(
        Party indexed party,
        address indexed buyer,
        uint256[] tokenIds,
        uint256 totalPrice,
        uint256 lastBondingCurvePrice,
        uint256 partyDaoFee,
        uint256 treasuryFee,
        uint256 creatorFee
    );
    event PartyCardsSold(
        Party indexed party,
        address indexed seller,
        uint256[] tokenIds,
        uint256 sellerProceeds,
        uint256 lastBondingCurvePrice,
        uint256 partyDaoFee,
        uint256 treasuryFee,
        uint256 creatorFee
    );

    MockBondingCurveAuthority authority;
    Party.PartyOptions opts;

    uint16 TREASURY_FEE_BPS = 0.1e4; // 10%
    uint16 PARTY_DAO_FEE_BPS = 0.025e4; // 2.5%
    uint16 CREATOR_FEE_BPS = 0.025e4; // 2.5%

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();

        authority = new MockBondingCurveAuthority(
            globalDaoWalletAddress,
            PARTY_DAO_FEE_BPS,
            TREASURY_FEE_BPS,
            CREATOR_FEE_BPS
        );

        address[] memory hosts = new address[](1);
        hosts[0] = _randomAddress();
        opts.name = "PARTY";
        opts.symbol = "PRT";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = 4 days;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 0;
        opts.proposalEngine.distributionsConfig = ProposalStorage.DistributionsConfig.NotAllowed;

        // Set a default treasury fee
        vm.prank(globalDaoWalletAddress);
        authority.setTreasuryFee(TREASURY_FEE_BPS);

        // Set a default Party DAO fee
        vm.prank(globalDaoWalletAddress);
        authority.setPartyDaoFee(PARTY_DAO_FEE_BPS);
    }

    function _createParty(
        uint80 initialBuyAmount,
        bool creatorFeeOn
    ) internal returns (Party party, address payable creator, uint256 initialPrice) {
        creator = _randomAddress();

        initialPrice = authority.getPriceToBuy(
            0,
            initialBuyAmount,
            50_000,
            uint80(0.001 ether),
            creatorFeeOn,
            0
        );

        BondingCurveAuthority.BondingCurvePartyOptions
            memory bondingCurveOpts = BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: creatorFeeOn,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            });

        vm.deal(creator, initialPrice);
        vm.expectEmit(false, true, true, true); // Don't check party address so we don't have to derive it
        emit BondingCurvePartyCreated(Party(payable(address(0))), creator, bondingCurveOpts);
        vm.prank(creator);
        party = authority.createParty{ value: initialPrice }(bondingCurveOpts, initialBuyAmount);
    }

    function test_initialize_revertIfGreaterThanMaxPartyDaoFee() public {
        uint16 maxPartyDaoFeeBps = 250;
        vm.expectRevert(BondingCurveAuthority.InvalidPartyDaoFee.selector);
        new BondingCurveAuthority(
            globalDaoWalletAddress,
            maxPartyDaoFeeBps + 1,
            TREASURY_FEE_BPS,
            CREATOR_FEE_BPS
        );
    }

    function test_initialize_revertIfGreaterThanMaxTreasuryFee() public {
        uint16 maxTreasuryFeeBps = 1000;
        vm.expectRevert(BondingCurveAuthority.InvalidTreasuryFee.selector);
        new BondingCurveAuthority(
            globalDaoWalletAddress,
            PARTY_DAO_FEE_BPS,
            maxTreasuryFeeBps + 1,
            CREATOR_FEE_BPS
        );
    }

    function test_initialize_revertIfGreaterThanMaxCreatorFee() public {
        uint16 maxCreatorFeeBps = 250;
        vm.expectRevert(BondingCurveAuthority.InvalidCreatorFee.selector);
        new BondingCurveAuthority(
            globalDaoWalletAddress,
            PARTY_DAO_FEE_BPS,
            TREASURY_FEE_BPS,
            maxCreatorFeeBps + 1
        );
    }

    function test_createParty_works() public {
        (Party party, address payable creator, ) = _createParty(1, true);

        uint256 expectedBondingCurvePrice = 0.001 ether;
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;
        uint256 expectedTreasuryFee = (expectedBondingCurvePrice * TREASURY_FEE_BPS) / 1e4;
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        (address payable partyCreator, uint80 supply, bool creatorFeeOn, , , ) = authority
            .partyInfos(party);

        assertEq(partyCreator, creator);
        assertTrue(creatorFeeOn);
        assertEq(supply, 1);
        assertEq(party.balanceOf(creator), 1);
        assertEq(party.getVotingPowerAt(creator, uint40(block.timestamp), 0), 0.1 ether);
        assertEq(address(party).balance, expectedTreasuryFee);
        assertEq(creator.balance, expectedCreatorFee);
        assertEq(
            address(authority).balance,
            // Creator fee is held in BondingCurveAuthority until claimed.
            expectedBondingCurvePrice + expectedPartyDaoFee + 1
        );
    }

    function test_createParty_revertAddAuthorityProposalNotSupported() external {
        opts.proposalEngine.enableAddAuthorityProposal = true;

        vm.expectRevert(BondingCurveAuthority.AddAuthorityProposalNotSupported.selector);
        authority.createParty(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            1
        );
    }

    function test_createParty_revertDistributionsNotSupported() external {
        opts.proposalEngine.distributionsConfig = ProposalStorage
            .DistributionsConfig
            .AllowedWithoutVote;

        vm.expectRevert(BondingCurveAuthority.DistributionsNotSupported.selector);
        authority.createParty(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            1
        );
    }

    function test_createParty_revertBelowMinExecutionDelay() external {
        opts.governance.executionDelay = 0;

        vm.expectRevert(BondingCurveAuthority.ExecutionDelayTooShort.selector);
        authority.createParty(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            1
        );
    }

    function test_createParty_revertNeedAtLeastOneHost() external {
        opts.governance.hosts = new address[](0);
        vm.expectRevert(BondingCurveAuthority.NeedAtLeastOneHost.selector);
        authority.createParty(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            1
        );
    }

    function test_createParty_moreThanOnePartyCard() public {
        (Party party, address payable creator, ) = _createParty(5, true);

        (address payable partyCreator, uint80 supply, bool creatorFeeOn, , , ) = authority
            .partyInfos(party);

        assertEq(partyCreator, creator);
        assertTrue(creatorFeeOn);
        assertEq(supply, 5);
        assertEq(party.balanceOf(creator), 5);
        assertEq(party.getVotingPowerAt(creator, uint40(block.timestamp), 0), 0.5 ether);
    }

    function test_createParty_alreadyExists() external {
        // Create party to attempt to take over
        _createParty(1, true);

        PartyFactory trickFactory = PartyFactory(address(new TrickFactory(address(partyFactory))));

        address creator = _randomAddress();
        uint256 initialPrice = authority.getPriceToBuy(0, 2, 50_000, uint80(0.001 ether), true, 0);

        vm.deal(creator, initialPrice);
        vm.prank(creator);
        vm.expectRevert(BondingCurveAuthority.ExistingParty.selector);
        authority.createParty{ value: initialPrice }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: trickFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            2
        );

        vm.prank(creator);
        vm.expectRevert(BondingCurveAuthority.ExistingParty.selector);
        authority.createPartyWithMetadata{ value: initialPrice }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: trickFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            MetadataProvider(address(0)),
            "",
            2
        );
    }

    function test_createPartyWithMetadata_works() public {
        MetadataProvider metadataProvider = new MetadataProvider(globals);
        bytes memory metadata = abi.encodePacked("custom_metadata");

        address payable creator = _randomAddress();

        uint256 initialPrice = 0.001 ether;
        initialPrice =
            (initialPrice * (1e4 + authority.treasuryFeeBps() + authority.partyDaoFeeBps())) /
            1e4 +
            1;

        vm.deal(creator, initialPrice);
        vm.prank(creator);
        Party party = authority.createPartyWithMetadata{ value: initialPrice }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: false,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            metadataProvider,
            metadata,
            1
        );

        assertEq(address(metadataRegistry.getProvider(address(party))), address(metadataProvider));
        assertEq(metadataProvider.getMetadata(address(party), 1), metadata);
    }

    function test_createParty_revertsIfTotalVotingPowerNonZero() public {
        address creator = _randomAddress();

        uint256 initialPrice = 0.001 ether;
        initialPrice =
            (initialPrice *
                (1e4 +
                    authority.treasuryFeeBps() +
                    authority.partyDaoFeeBps() +
                    authority.creatorFeeBps())) /
            1e4;

        vm.deal(creator, initialPrice);
        vm.prank(creator);
        vm.expectRevert(BondingCurveAuthority.InvalidTotalVotingPower.selector);
        opts.governance.totalVotingPower = 100;
        party = authority.createParty{ value: initialPrice }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            1
        );

        vm.expectRevert(BondingCurveAuthority.InvalidTotalVotingPower.selector);
        party = authority.createPartyWithMetadata{ value: initialPrice }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: 0
            }),
            MetadataProvider(address(0)),
            "",
            1
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
        (party, creator, ) = _createParty(1, true);

        initialBalanceExcludingPartyDaoFee =
            address(authority).balance -
            authority.partyDaoFeeClaimable();

        uint256 expectedPriceToBuy = authority.getPriceToBuy(party, 10);
        expectedBondingCurvePrice =
            ((expectedPriceToBuy - 10) * 1e4) /
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

        {
            uint256[] memory tokenIds = new uint256[](10);
            for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

            uint256 lastBondingCurvePrice = authority.getBondingCurvePrice(
                10,
                1,
                50_000,
                uint80(0.001 ether)
            );

            vm.prank(buyer);
            vm.expectEmit(true, true, true, true);
            emit PartyCardsBought(
                party,
                buyer,
                tokenIds,
                expectedPriceToBuy,
                lastBondingCurvePrice,
                expectedPartyDaoFee,
                expectedTreasuryFee,
                expectedCreatorFee
            );
        }

        authority.buyPartyCards{ value: expectedPriceToBuy }(party, 10, address(0));

        (, uint80 supply, , , , ) = authority.partyInfos(party);

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
            expectedBondingCurvePrice + expectedPartyDaoFee + 10
        );
        assertEq(address(party).balance - beforePartyBalance, expectedTreasuryFee);
        assertEq(creator.balance - beforeCreatorBalance, expectedCreatorFee);
    }

    function test_buyPartyCards_noCreatorFee()
        public
        returns (Party party, address payable creator, address buyer)
    {
        (party, creator, ) = _createParty(1, false);
        uint256 expectedPriceToBuy = authority.getPriceToBuy(party, 3);

        buyer = _randomAddress();
        vm.deal(buyer, expectedPriceToBuy);
        vm.prank(buyer);
        uint256[] memory tokenIds = authority.buyPartyCards{ value: expectedPriceToBuy }(
            party,
            3,
            address(0)
        );

        uint256[] memory expectedTokenIds = new uint256[](3);
        expectedTokenIds[0] = 2;
        expectedTokenIds[1] = 3;
        expectedTokenIds[2] = 4;
        assertEq(tokenIds, expectedTokenIds);

        assertEq(creator.balance, 0);
    }

    function test_buyPartyCards_creatorFeeFails() public {
        (Party party, address creator, ) = _createParty(1, true);
        uint256 creatorBalanceBefore = creator.balance;

        // Store this code to creator will cause eth transfer to revert
        vm.etch(creator, address(authority).code);

        uint256 expectedPriceToBuy = authority.getPriceToBuy(party, 3);
        uint256 expectedBondingCurvePrice = (expectedPriceToBuy * 1e4) /
            (1e4 + TREASURY_FEE_BPS + PARTY_DAO_FEE_BPS + CREATOR_FEE_BPS);
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        address buyer = _randomAddress();
        vm.deal(buyer, expectedPriceToBuy);
        vm.prank(buyer);
        authority.buyPartyCards{ value: expectedPriceToBuy }(party, 3, address(0));
        assertEq(buyer.balance, expectedCreatorFee); // got back creator fee
        assertEq(creator.balance, creatorBalanceBefore);
    }

    function test_buyPartyCards_refundIfGreaterThanPriceToBuy() public {
        (Party party, , ) = _createParty(1, true);

        uint256 priceToBuy = authority.getPriceToBuy(party, 10);
        uint256 expectedBondingCurvePrice = (priceToBuy * 1e4) /
            (1e4 + TREASURY_FEE_BPS + PARTY_DAO_FEE_BPS + CREATOR_FEE_BPS);
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;
        uint256 expectedTreasuryFee = (expectedBondingCurvePrice * TREASURY_FEE_BPS) / 1e4;
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

        uint256 lastBondingCurvePrice = authority.getBondingCurvePrice(
            10,
            1,
            50_000,
            uint80(0.001 ether)
        );

        uint256 balanceBefore = address(this).balance;
        vm.expectEmit(true, true, true, true);
        emit PartyCardsBought(
            party,
            address(this),
            tokenIds,
            priceToBuy,
            lastBondingCurvePrice,
            expectedPartyDaoFee,
            expectedTreasuryFee,
            expectedCreatorFee
        );

        authority.buyPartyCards{ value: priceToBuy + 100 }(party, 10, address(0));

        assertEq(address(this).balance, balanceBefore - priceToBuy);
    }

    function test_buyPartyCards_revertIfLessThanPriceToBuy() public {
        (Party party, , ) = _createParty(1, true);

        uint256 priceToBuy = authority.getPriceToBuy(party, 10);

        vm.expectRevert(BondingCurveAuthority.InvalidMessageValue.selector);
        authority.buyPartyCards{ value: priceToBuy - 1 }(party, 10, address(0));
    }

    function test_buyPartyCards_revertIfZeroAmount() public {
        (Party party, , ) = _createParty(1, true);

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

        {
            uint256 lastBondingCurvePrice = authority.getBondingCurvePrice(
                1,
                1,
                50_000,
                uint80(0.001 ether)
            );

            vm.prank(buyer);
            vm.expectEmit(true, true, true, true);
            emit PartyCardsSold(
                party,
                buyer,
                tokenIds,
                expectedSaleProceeds,
                lastBondingCurvePrice,
                expectedPartyDaoFee,
                expectedTreasuryFee,
                expectedCreatorFee
            );
        }

        authority.sellPartyCards(party, tokenIds, 0);
        (, uint80 supply, , , , ) = authority.partyInfos(party);

        assertEq(supply, 1);
        assertEq(party.balanceOf(buyer), 0);
        assertEq(
            party.getGovernanceValues().totalVotingPower,
            beforePartyTotalVotingPower - 1 ether
        );
        assertEq(party.getVotingPowerAt(buyer, uint40(block.timestamp), 0), 0);
        assertEq(buyer.balance, expectedSaleProceeds);
        assertApproxEqAbs(
            address(authority).balance,
            // Should only be the initial balance and the unclaimed Party DAO
            // fees leftover.
            initialBalanceExcludingPartyDaoFee + authority.partyDaoFeeClaimable(),
            10
        );
        assertEq(address(party).balance - beforePartyBalance, expectedTreasuryFee);
        assertEq(creator.balance - beforeCreatorBalance, expectedCreatorFee);
    }

    function test_sellPartyCards_revertIfTooMuchSlippage() public {
        (Party party, address payable creator, , address buyer, ) = test_buyPartyCards_works();

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

        uint256 expectedSaleProceeds = authority.getSaleProceeds(party, 10);

        uint256[] memory creatorTokenIds = new uint256[](1);
        creatorTokenIds[0] = 1;
        vm.prank(creator);
        authority.sellPartyCards(party, creatorTokenIds, 0);

        vm.prank(buyer);
        vm.expectRevert(BondingCurveAuthority.ExcessSlippage.selector);
        authority.sellPartyCards(party, tokenIds, expectedSaleProceeds);
    }

    function test_sellPartyCards_partyNotRecognized() public {
        vm.expectRevert(BondingCurveAuthority.PartyNotSupported.selector);
        authority.sellPartyCards(Party(payable(_randomAddress())), new uint256[](1), 0);
    }

    function test_sellPartyCards_cantSellZero() public {
        vm.expectRevert(BondingCurveAuthority.SellZeroPartyCards.selector);
        authority.sellPartyCards(Party(payable(_randomAddress())), new uint256[](0), 0);
    }

    function test_sellPartyCards_isApprovedForAll() public {
        (Party party, , , address buyer, ) = test_buyPartyCards_works();

        address approved = _randomAddress();

        vm.prank(buyer);
        party.setApprovalForAll(approved, true);

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) tokenIds[i] = i + 2;

        vm.prank(approved);
        authority.sellPartyCards(party, tokenIds, 0);
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
        authority.sellPartyCards(party, tokenIds, 0);
    }

    function test_sellPartyCards_revertIfNotApproved() public {
        (Party party, , , , ) = test_buyPartyCards_works();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.sellPartyCards(party, tokenIds, 0);
    }

    function test_sellPartyCards_noCreatorFee() public {
        (Party party, address payable creator, address buyer) = test_buyPartyCards_noCreatorFee();

        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) tokenIds[i] = i + 2;

        uint256 saleProceeds = authority.getSaleProceeds(party, 3);
        uint256 expectedBondingCurvePrice = ((saleProceeds + tokenIds.length) * 1e4) /
            (1e4 - TREASURY_FEE_BPS - PARTY_DAO_FEE_BPS);
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;
        uint256 expectedTreasuryFee = (expectedBondingCurvePrice * TREASURY_FEE_BPS) / 1e4;

        uint256 lastBondingCurvePrice = authority.getBondingCurvePrice(
            1,
            1,
            50_000,
            uint80(0.001 ether)
        );

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit PartyCardsSold(
            party,
            buyer,
            tokenIds,
            saleProceeds,
            lastBondingCurvePrice,
            expectedPartyDaoFee,
            expectedTreasuryFee,
            0
        );
        authority.sellPartyCards(party, tokenIds, 0);

        assertEq(address(creator).balance, 0);
    }

    function test_sellPartyCards_creatorFeeFails() public {
        (Party party, address payable creator, , address buyer, ) = test_buyPartyCards_works();

        // Store this code to creator will cause eth transfer to revert
        vm.etch(creator, address(authority).code);

        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) tokenIds[i] = i + 2;

        uint256 saleProceeds = authority.getSaleProceeds(party, 3);
        uint256 expectedBondingCurvePrice = ((saleProceeds + tokenIds.length) * 1e4) /
            (1e4 - TREASURY_FEE_BPS - PARTY_DAO_FEE_BPS - CREATOR_FEE_BPS);
        uint256 expectedCreatorFee = (expectedBondingCurvePrice * CREATOR_FEE_BPS) / 1e4;

        uint256 beforeBuyerBalance = buyer.balance;
        vm.prank(buyer);
        authority.sellPartyCards(party, tokenIds, 0);

        // Ensure buyer gets the creator fee as well
        assertEq(buyer.balance, beforeBuyerBalance + expectedCreatorFee + saleProceeds);
    }

    function test_setTreasuryFee_works(uint16 newTreasuryFee) public {
        vm.assume(newTreasuryFee <= 1000);

        vm.expectEmit(true, true, true, true);
        emit TreasuryFeeUpdated(authority.treasuryFeeBps(), newTreasuryFee);

        vm.prank(globalDaoWalletAddress);
        authority.setTreasuryFee(newTreasuryFee);

        assertEq(authority.treasuryFeeBps(), newTreasuryFee);
    }

    function test_setTreasuryFee_revertIfNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.setTreasuryFee(0);
    }

    function test_setTreasuryFee_revertIfOutOfBounds() public {
        vm.prank(globalDaoWalletAddress);
        vm.expectRevert(BondingCurveAuthority.InvalidTreasuryFee.selector);
        authority.setTreasuryFee(TREASURY_FEE_BPS + 1);
    }

    function test_setCreatorFee_works(uint16 newCreatorFee) public {
        vm.assume(newCreatorFee <= 250);

        vm.expectEmit(true, true, true, true);
        emit CreatorFeeUpdated(authority.creatorFeeBps(), newCreatorFee);

        vm.prank(globalDaoWalletAddress);
        authority.setCreatorFee(newCreatorFee);

        assertEq(authority.creatorFeeBps(), newCreatorFee);
    }

    function test_setCreatorFee_revertIfNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.setCreatorFee(0);
    }

    function test_setCreatorFee_revertIfOutOfBounds() public {
        vm.prank(globalDaoWalletAddress);
        vm.expectRevert(BondingCurveAuthority.InvalidCreatorFee.selector);
        authority.setCreatorFee(CREATOR_FEE_BPS + 1);
    }

    function test_setPartyDaoFee_works(uint16 newPartyDaoFee) public {
        vm.assume(newPartyDaoFee <= 250);

        vm.expectEmit(true, true, true, true);
        emit PartyDaoFeeUpdated(authority.partyDaoFeeBps(), newPartyDaoFee);

        vm.prank(globalDaoWalletAddress);
        authority.setPartyDaoFee(newPartyDaoFee);

        assertEq(authority.partyDaoFeeBps(), newPartyDaoFee);
    }

    function test_setPartyDaoFee_revertIfOutOfBounds() public {
        vm.prank(globalDaoWalletAddress);
        vm.expectRevert(BondingCurveAuthority.InvalidPartyDaoFee.selector);
        authority.setPartyDaoFee(PARTY_DAO_FEE_BPS + 1);
    }

    function test_setPartyDaoFee_revertIfNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.setPartyDaoFee(0);
    }

    function test_claimPartyDaoFees_works() public {
        _createParty(1, true);

        uint256 expectedBondingCurvePrice = 0.001 ether;
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;

        vm.expectEmit(true, true, true, true);
        emit PartyDaoFeesClaimed(uint96(expectedPartyDaoFee));

        vm.prank(globalDaoWalletAddress);
        authority.claimPartyDaoFees();

        assertEq(address(authority).balance, expectedBondingCurvePrice + 1);
        assertEq(globalDaoWalletAddress.balance, expectedPartyDaoFee);
    }

    function test_claimPartyDaoFees_revertIfNotPartyDAO() public {
        vm.prank(_randomAddress());
        vm.expectRevert(BondingCurveAuthority.Unauthorized.selector);
        authority.claimPartyDaoFees();
    }

    function test_claimPartyDaoFees_revertIfTransferFails() public {
        _createParty(1, true);

        uint256 expectedBondingCurvePrice = 0.001 ether;
        uint256 expectedPartyDaoFee = (expectedBondingCurvePrice * PARTY_DAO_FEE_BPS) / 1e4;

        // Cause transfer to fail
        vm.etch(address(globalDaoWalletAddress), address(authority).code);
        vm.prank(globalDaoWalletAddress);
        vm.expectRevert(BondingCurveAuthority.EthTransferFailed.selector);
        authority.claimPartyDaoFees();

        assertEq(authority.partyDaoFeeClaimable(), expectedPartyDaoFee);
    }

    function test_buyThenSellPartyCards() public {
        address buyer1 = _randomAddress();
        address buyer2 = _randomAddress();

        (Party party, address payable creator, ) = _createParty(1, true);

        vm.prank(creator);
        uint256[] memory creatorToken = new uint256[](1);
        creatorToken[0] = 1;
        authority.sellPartyCards(party, creatorToken, 0);

        uint256[] memory buyer1Tokens = new uint256[](10);
        uint256[] memory buyer2Tokens = new uint256[](7);

        for (uint256 i = 0; i < 10; i++) {
            if (i < 7) {
                uint256 price = authority.getPriceToBuy(party, 1);
                vm.deal(buyer2, price);
                vm.prank(buyer2);
                buyer2Tokens[i] = authority.buyPartyCards{ value: price }(party, 1, address(0))[0];
            }
            uint256 price = authority.getPriceToBuy(party, 1);
            vm.deal(buyer1, price);
            vm.prank(buyer1);
            buyer1Tokens[i] = authority.buyPartyCards{ value: price }(party, 1, address(0))[0];
        }

        vm.prank(buyer2);
        authority.sellPartyCards(party, buyer2Tokens, 0);

        vm.prank(buyer1);
        authority.sellPartyCards(party, buyer1Tokens, 0);

        vm.prank(globalDaoWalletAddress);
        authority.claimPartyDaoFees();

        assertApproxEqAbs(address(authority).balance, 0, 18);
    }

    function test_firstPartyCardFree() public {
        Party party = authority.createParty{ value: 1 }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: partyFactory,
                partyImpl: partyImpl,
                opts: opts,
                creatorFeeOn: true,
                a: 50_000,
                b: uint80(0.001 ether),
                firstCardDiscount: uint80(0.001 ether)
            }),
            1
        );

        assertEq(authority.getSaleProceeds(party, 1), 0);

        uint256[] memory partyCardsToSell = new uint256[](1);
        partyCardsToSell[0] = 1;

        uint256 balanceBefore = address(this).balance;
        authority.sellPartyCards(party, partyCardsToSell, 0);
        // Ensure no proceeds
        assertEq(address(this).balance, balanceBefore);
    }

    // Check bonding curve pricing calculations
    function test_checkBondingCurvePrice_firstMints() public {
        uint256 previousSupply = 0;

        for (uint i = 1; i < 10; i++) {
            // Check if buying i works as expected
            uint256 expectedBondingCurvePrice = 0;

            for (uint j = 1; j <= i; j++) {
                expectedBondingCurvePrice +=
                    (1 ether * (previousSupply + j - 1) * (previousSupply + j - 1)) /
                    50_000 +
                    0.001 ether;
            }

            assertEq(
                authority.getBondingCurvePrice(previousSupply, i, 50_000, uint80(0.001 ether)),
                expectedBondingCurvePrice
            );
        }
    }

    function test_checkBondingCurvePrice_existingSupply() public {
        for (uint i = 0; i < 10; i++) {
            // Check if buying 3 works as expected with random existing supply 10 times
            uint256 expectedBondingCurvePrice = 0;
            uint256 previousSupply = _randomRange(1, 100);

            for (uint j = 1; j <= 3; j++) {
                expectedBondingCurvePrice +=
                    (1 ether * (previousSupply + j - 1) * (previousSupply + j - 1)) /
                    50_000 +
                    0.001 ether;
            }

            assertEq(
                authority.getBondingCurvePrice(previousSupply, 3, 50_000, uint80(0.001 ether)),
                expectedBondingCurvePrice
            );
        }
    }

    function test_checkBondingCurvePrice_random_checkPrice(
        uint16 amount,
        uint16 previousSupply,
        uint32 a,
        uint80 b
    ) public {
        vm.assume(a > 0);
        vm.assume(amount < 200);

        uint256 expectedBondingCurvePrice = 0;

        for (uint i = 1; i <= amount; i++) {
            expectedBondingCurvePrice +=
                (1 ether * (previousSupply + i - 1) * (previousSupply + i - 1)) /
                a +
                b;
        }

        assertApproxEqAbs(
            authority.getBondingCurvePrice(previousSupply, amount, a, b),
            expectedBondingCurvePrice,
            amount
        );
    }

    function test_checkBondingCurvePrice_randomAAndB_ensureSumMatches(
        uint16 amount,
        uint16 previousSupply,
        uint32 a,
        uint80 b
    ) public {
        vm.assume(a > 0);
        vm.assume(amount < 200);

        uint256 aggregatePrice = 0;
        for (uint i = 0; i < amount; i++) {
            aggregatePrice += authority.getBondingCurvePrice(previousSupply + i, 1, a, b);
        }

        assertApproxEqAbs(
            aggregatePrice,
            authority.getBondingCurvePrice(previousSupply, amount, a, b),
            amount
        );
    }

    receive() external payable {}
}

contract MockBondingCurveAuthority is BondingCurveAuthority {
    constructor(
        address payable partyDao,
        uint16 initialPartyDaoFeeBps,
        uint16 initialTreasuryFeeBps,
        uint16 initialCreatorFeeBps
    )
        BondingCurveAuthority(
            partyDao,
            initialPartyDaoFeeBps,
            initialTreasuryFeeBps,
            initialCreatorFeeBps
        )
    {}

    function getBondingCurvePrice(
        uint256 lowerSupply,
        uint256 amount,
        uint32 a,
        uint80 b
    ) external pure returns (uint256) {
        return super._getBondingCurvePrice(lowerSupply, amount, a, b, 0);
    }
}

contract TrickFactory is Test {
    address realFactory;

    constructor(address realFactory_) {
        realFactory = realFactory_;
    }

    function createParty(
        Party,
        address[] memory,
        Party.PartyOptions memory,
        IERC721[] memory,
        uint256[] memory,
        uint40
    ) external view returns (Party party) {
        return Party(payable(contractAddressFrom(realFactory, vm.getNonce(realFactory) - 1)));
    }

    function createPartyWithMetadata(
        Party,
        address[] memory,
        Party.PartyOptions memory,
        IERC721[] memory,
        uint256[] memory,
        uint40,
        MetadataProvider,
        bytes memory
    ) external view returns (Party party) {
        return Party(payable(contractAddressFrom(realFactory, vm.getNonce(realFactory) - 1)));
    }

    function contractAddressFrom(address deployer, uint256 nonce) internal pure returns (address) {
        if (nonce == 0x00)
            return
                address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(0x80))
                            )
                        )
                    )
                );
        if (nonce <= 0x7f)
            return
                address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    bytes1(0xd6),
                                    bytes1(0x94),
                                    deployer,
                                    bytes1(uint8(nonce))
                                )
                            )
                        )
                    )
                );
        if (nonce <= 0xff)
            return
                address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    bytes1(0xd7),
                                    bytes1(0x94),
                                    deployer,
                                    bytes1(0x81),
                                    uint8(nonce)
                                )
                            )
                        )
                    )
                );
        if (nonce <= 0xffff)
            return
                address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    bytes1(0xd8),
                                    bytes1(0x94),
                                    deployer,
                                    bytes1(0x82),
                                    uint16(nonce)
                                )
                            )
                        )
                    )
                );
        if (nonce <= 0xffffff)
            return
                address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    bytes1(0xd9),
                                    bytes1(0x94),
                                    deployer,
                                    bytes1(0x83),
                                    uint24(nonce)
                                )
                            )
                        )
                    )
                );
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xda),
                                bytes1(0x94),
                                deployer,
                                bytes1(0x84),
                                uint32(nonce)
                            )
                        )
                    )
                )
            );
    }
}
