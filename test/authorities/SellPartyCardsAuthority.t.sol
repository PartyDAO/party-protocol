// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Party, SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { SellPartyCardsAuthority } from "contracts/authorities/SellPartyCardsAuthority.sol";
import { IGateKeeper } from "contracts/gatekeepers/IGateKeeper.sol";
import { ContributionRouter } from "../../contracts/crowdfund/ContributionRouter.sol";
import { TokenGateKeeper, Token } from "contracts/gatekeepers/TokenGateKeeper.sol";
import { DummyERC20 } from "../DummyERC20.sol";

contract SellPartyCardsAuthorityTest is SetupPartyHelper {
    event MintedFromSale(
        Party indexed party,
        uint256 indexed saledId,
        uint256 indexed tokenId,
        address sender,
        address contributor,
        uint96 contribution,
        address delegate
    );
    event Finalized(Party indexed party, uint256 indexed saleId);

    constructor() SetupPartyHelper(false) {}

    SellPartyCardsAuthority internal sellPartyCardsAuthority;
    ContributionRouter internal router;

    uint256 lastTokenId;

    function setUp() public override {
        super.setUp();
        sellPartyCardsAuthority = new SellPartyCardsAuthority();

        vm.prank(address(party));
        party.addAuthority(address(sellPartyCardsAuthority));
        router = new ContributionRouter(address(this), 0.0001 ether);

        lastTokenId = party.tokenCount();
    }

    function testSellPartyCards_createNewFixedSaleAndBuyOut() public {
        uint96 originalTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 originalPartyBalance = address(party).balance;
        uint256 saleId = _createNewFixedSale();
        assertEq(originalTotalVotingPower, party.getGovernanceValues().totalVotingPower);

        for (uint i = 0; i < 3; i++) {
            address buyer = _randomAddress();
            vm.deal(buyer, 1 ether);
            vm.prank(buyer);
            vm.expectEmit(true, true, true, true);
            emit MintedFromSale(party, saleId, lastTokenId + i + 1, buyer, buyer, 1 ether, buyer);
            sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");
            assertEq(
                originalTotalVotingPower + (1 + i) * 0.001 ether,
                party.getGovernanceValues().totalVotingPower
            );
            assertEq(party.balanceOf(buyer), 1);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
            assertEq(party.getVotingPowerAt(buyer, uint40(block.timestamp)), 0.001 ether);
        }

        assertEq(address(party).balance, originalPartyBalance + 3 ether);

        // Don't allow further contributions
        address buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.SaleInactiveError.selector);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");
    }

    function testSellPartyCards_createNewFlexibleSaleAndBuyOut() public {
        uint96 originalTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 saleId = _createNewFlexibleSale();
        assertEq(originalTotalVotingPower, party.getGovernanceValues().totalVotingPower);

        for (uint i = 0; i < 3; i++) {
            address buyer = _randomAddress();
            uint96 amount = uint96(0.001 ether + i * 0.998 ether);
            vm.deal(buyer, 2 ether);
            vm.prank(buyer);
            vm.expectEmit(true, true, true, true);
            emit MintedFromSale(party, saleId, lastTokenId + i + 1, buyer, buyer, amount, buyer);
            sellPartyCardsAuthority.contribute{ value: amount }(party, saleId, buyer, "");
            assertEq(party.balanceOf(buyer), 1);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
            assertEq(party.getVotingPowerAt(buyer, uint40(block.timestamp)), amount);
        }
        assertEq(
            originalTotalVotingPower + 2.997 ether,
            party.getGovernanceValues().totalVotingPower
        );

        // Reduce contribution to available amount
        address buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit MintedFromSale(party, saleId, lastTokenId + 4, buyer, buyer, 0.003 ether, buyer);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");

        // Don't allow further contributions
        buyer = _randomAddress();
        vm.prank(buyer);
        vm.deal(buyer, 1 ether);
        vm.expectRevert(SellPartyCardsAuthority.SaleInactiveError.selector);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");
    }

    function testSellPartyCards_createNewFixedSaleAndBuyOut_batchContribute() public {
        uint96 originalTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 saleId = _createNewFixedSale();
        assertEq(originalTotalVotingPower, party.getGovernanceValues().totalVotingPower);

        address buyer = _randomAddress();
        vm.deal(buyer, 3 ether);

        uint96[] memory values = new uint96[](3);
        for (uint i = 0; i < 3; i++) {
            values[i] = 1 ether;
        }

        // First try with incorrect value
        vm.expectRevert(SellPartyCardsAuthority.InvalidMessageValue.selector);
        vm.prank(buyer);
        sellPartyCardsAuthority.batchContribute{ value: 2 ether }(party, saleId, buyer, values, "");

        vm.prank(buyer);
        sellPartyCardsAuthority.batchContribute{ value: 3 ether }(party, saleId, buyer, values, "");
        assertEq(
            originalTotalVotingPower + 0.003 ether,
            party.getGovernanceValues().totalVotingPower
        );
        assertEq(party.balanceOf(buyer), 3);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
        assertEq(party.getVotingPowerAt(buyer, uint40(block.timestamp)), 0.003 ether);
    }

    function testSellPartyCards_fundingSplit() public {
        address payable fundingSplitReceiver = payable(_randomAddress());
        assertEq(fundingSplitReceiver.balance, 0);
        uint16 fundingSplitBps = 1000;

        SellPartyCardsAuthority.FixedMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FixedMembershipSaleOpts({
                pricePerMembership: 1 ether,
                votingPowerPerMembership: 0.001 ether,
                totalMembershipsForSale: 3,
                fundingSplitBps: fundingSplitBps,
                fundingSplitRecipient: fundingSplitReceiver,
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        uint256 saleId = sellPartyCardsAuthority.createFixedMembershipSale(opts);

        address buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");

        assertEq(fundingSplitReceiver.balance, (1 ether * uint256(fundingSplitBps)) / 10_000);
    }

    function testSellPartyCards_contributeAboveMax() public {
        uint256 saleId = _createNewFlexibleSale();

        address buyer = _randomAddress();
        vm.deal(buyer, 2.5 ether);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellPartyCardsAuthority.OutOfBoundsContributionsError.selector,
                2.5 ether,
                2 ether
            )
        );
        sellPartyCardsAuthority.contribute{ value: 2.5 ether }(party, saleId, buyer, "");
    }

    function testSellPartyCards_contributeBelowMin() public {
        uint256 saleId = _createNewFlexibleSale();

        address buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellPartyCardsAuthority.OutOfBoundsContributionsError.selector,
                0.0005 ether,
                0.001 ether
            )
        );
        sellPartyCardsAuthority.contribute{ value: 0.0005 ether }(party, saleId, buyer, "");
    }

    function testSellPartyCards_createSale_minAboveMax() public {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 3 ether,
                maxContribution: 2 ether,
                maxTotalContributions: 3 ether,
                exchangeRate: 1e18,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        vm.expectRevert(
            abi.encodeWithSelector(
                SellPartyCardsAuthority.MinGreaterThanMaxError.selector,
                3 ether,
                2 ether
            )
        );
        sellPartyCardsAuthority.createFlexibleMembershipSale(opts);
    }

    function testSellPartyCards_createSale_totalContributionsZero() public {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 1 ether,
                maxContribution: 2 ether,
                maxTotalContributions: 0 ether,
                exchangeRate: 1e18,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        vm.expectRevert(SellPartyCardsAuthority.ZeroMaxTotalContributionsError.selector);
        sellPartyCardsAuthority.createFlexibleMembershipSale(opts);
    }

    function testSellPartyCards_createSale_zeroExchangeRate() public {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 1 ether,
                maxContribution: 2 ether,
                maxTotalContributions: 5 ether,
                exchangeRate: 0,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        vm.expectRevert(SellPartyCardsAuthority.ZeroExchangeRateError.selector);
        sellPartyCardsAuthority.createFlexibleMembershipSale(opts);
    }

    function testSellPartyCards_createSale_invalidFundingSplit() public {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 1 ether,
                maxContribution: 2 ether,
                maxTotalContributions: 5 ether,
                exchangeRate: 1e18,
                fundingSplitBps: 10001,
                fundingSplitRecipient: payable(address(this)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        vm.expectRevert(
            abi.encodeWithSelector(SellPartyCardsAuthority.InvalidBpsError.selector, 10001)
        );
        sellPartyCardsAuthority.createFlexibleMembershipSale(opts);
    }

    function testSellPartyCards_contributeFor() public {
        uint256 saleId = _createNewFixedSale();

        address buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        address receiver = _randomAddress();

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit MintedFromSale(party, saleId, lastTokenId + 1, buyer, receiver, 1 ether, receiver);
        sellPartyCardsAuthority.contributeFor{ value: 1 ether }(
            party,
            saleId,
            receiver,
            receiver,
            ""
        );

        assertEq(party.balanceOf(receiver), 1);
    }

    function testSellPartyCards_batchContributeForThroughRouter() public {
        uint256 originalPartyBalance = address(party).balance;
        uint256 saleId = _createNewFixedSale();

        address buyer = _randomAddress();
        vm.deal(buyer, 4 ether);

        address receiver = _randomAddress();

        address[] memory recipients = new address[](3);
        address[] memory delegates = new address[](3);
        uint96[] memory values = new uint96[](3);

        for (uint i = 0; i < 3; i++) {
            recipients[i] = delegates[i] = _randomAddress();
            values[i] = 1 ether;
        }

        uint256 feePerMint = router.feePerMint();
        bytes memory data = abi.encodeCall(
            SellPartyCardsAuthority.batchContributeFor,
            (party, saleId, recipients, delegates, values, "")
        );

        vm.expectRevert(SellPartyCardsAuthority.InvalidMessageValue.selector);
        vm.prank(buyer);
        address(router).call{ value: 3 ether }(abi.encodePacked(data, sellPartyCardsAuthority));

        vm.prank(buyer);
        (bool success, ) = address(router).call{ value: 3 ether + 3 * feePerMint }(
            abi.encodePacked(data, sellPartyCardsAuthority)
        );

        assertTrue(success);
        for (uint i = 0; i < 3; i++) {
            assertEq(party.balanceOf(recipients[i]), 1);
            assertEq(party.getVotingPowerAt(recipients[i], uint40(block.timestamp)), 0.001 ether);
        }

        assertEq(address(router).balance, 3 * feePerMint);
        assertEq(address(party).balance, originalPartyBalance + 3 ether);
    }

    function testSellPartyCards_finalize() public {
        uint256 saleId = _createNewFixedSale();

        address buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");

        // Only from host
        vm.prank(john);
        vm.expectRevert(SellPartyCardsAuthority.OnlyPartyHostError.selector);
        sellPartyCardsAuthority.finalize(party, saleId);

        vm.expectEmit(true, true, true, true);
        emit Finalized(party, saleId);
        sellPartyCardsAuthority.finalize(party, saleId);

        // Can't contribute anymore
        buyer = _randomAddress();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.SaleInactiveError.selector);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");

        // Can't finalize again
        vm.expectRevert(SellPartyCardsAuthority.SaleInactiveError.selector);
        sellPartyCardsAuthority.finalize(party, saleId);

        (, , , , , , uint40 expiry, , ) = sellPartyCardsAuthority.getFixedMembershipSaleInfo(
            party,
            saleId
        );
        assertEq(expiry, uint40(block.timestamp));
    }

    function testSellPartyCards_getFlexibleMembershipSaleInfo() public {
        uint256 saleId = _createNewFlexibleSale();

        vm.warp(block.timestamp + 10);

        (
            uint96 minContribution,
            uint96 maxContribution,
            uint96 totalContributions,
            uint96 maxTotalContributions,
            uint96 exchangeRate,
            uint16 fundingSplitBps,
            address payable fundingSplitRecipient,
            uint40 expiry,
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId
        ) = sellPartyCardsAuthority.getFlexibleMembershipSaleInfo(party, saleId);

        assertEq(minContribution, 0.001 ether);
        assertEq(maxContribution, 2 ether);
        assertEq(totalContributions, 0 ether);
        assertEq(maxTotalContributions, 3 ether);
        assertEq(exchangeRate, 1e18);
        assertEq(fundingSplitBps, 0);
        assertEq(fundingSplitRecipient, payable(address(0)));
        assertEq(expiry, uint40(block.timestamp + 100 - 10));
        assertEq(address(gateKeeper), address(0));
        assertEq(gateKeeperId, bytes12(0));
    }

    function testSellPartyCards_getFixedMembershipSaleInfo() public {
        uint256 saleId = _createNewFixedSale();

        vm.warp(block.timestamp + 10);

        (
            uint96 pricePerMembership,
            uint96 votingPowerPerMembership,
            uint96 totalContributions,
            uint96 totalMembershipsForSale,
            uint16 fundingSplitBps,
            address payable fundingSplitRecipient,
            uint40 expiry,
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId
        ) = sellPartyCardsAuthority.getFixedMembershipSaleInfo(party, saleId);

        assertEq(pricePerMembership, 1 ether);
        assertEq(votingPowerPerMembership, 0.001 ether);
        assertEq(totalMembershipsForSale, 3);
        assertEq(totalContributions, 0);
        assertEq(fundingSplitBps, 0);
        assertEq(fundingSplitRecipient, payable(address(0)));
        assertEq(expiry, uint40(block.timestamp + 100 - 10));
        assertEq(address(gateKeeper), address(0));
        assertEq(gateKeeperId, bytes12(0));
    }

    function testSellPartyCards_gatekeepers() public {
        TokenGateKeeper gatekeeper = new TokenGateKeeper(address(router));
        DummyERC20 token = new DummyERC20();

        address buyer = _randomAddress();
        vm.deal(buyer, 2 ether);
        bytes12 gatekeeperId = gatekeeper.createGate(Token(address(token)), 0.01 ether);
        token.deal(buyer, 0.001 ether);

        SellPartyCardsAuthority.FixedMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FixedMembershipSaleOpts({
                pricePerMembership: 1 ether,
                votingPowerPerMembership: 0.001 ether,
                totalMembershipsForSale: 3,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: gatekeeper,
                gateKeeperId: gatekeeperId
            });

        vm.prank(address(party));
        uint256 saleId = sellPartyCardsAuthority.createFixedMembershipSale(opts);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                SellPartyCardsAuthority.NotAllowedByGateKeeperError.selector,
                buyer,
                gatekeeper,
                gatekeeperId,
                hex""
            )
        );
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");

        token.deal(buyer, 0.01 ether);
        vm.prank(buyer);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");
    }

    function testSellPartyCards_zeroVotingPower() public {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 0,
                maxContribution: 2 ether,
                maxTotalContributions: 3 ether,
                exchangeRate: 1e18,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        uint256 saleId = sellPartyCardsAuthority.createFlexibleMembershipSale(opts);

        address buyer = _randomAddress();
        vm.deal(buyer, 2 ether);

        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.ZeroVotingPowerError.selector);
        sellPartyCardsAuthority.contribute(party, saleId, buyer, "");

        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.ZeroVotingPowerError.selector);
        sellPartyCardsAuthority.contributeFor(party, saleId, _randomAddress(), buyer, "");

        uint96[] memory values = new uint96[](3);
        values[0] = 1 ether;
        values[1] = 0.2 ether;

        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.ZeroVotingPowerError.selector);
        sellPartyCardsAuthority.batchContribute{ value: 1.2 ether }(
            party,
            saleId,
            buyer,
            values,
            ""
        );

        address[] memory recipients = new address[](3);
        address[] memory delegates = new address[](3);
        recipients[0] = delegates[0] = _randomAddress();
        recipients[1] = delegates[1] = _randomAddress();
        recipients[2] = delegates[2] = _randomAddress();

        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.ZeroVotingPowerError.selector);
        sellPartyCardsAuthority.batchContributeFor{ value: 1.2 ether }(
            party,
            saleId,
            recipients,
            delegates,
            values,
            ""
        );
    }

    function testSellPartyCards_precision_upperPrice() public {
        SellPartyCardsAuthority.FixedMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FixedMembershipSaleOpts({
                pricePerMembership: 10 ether,
                votingPowerPerMembership: 10, // pricePerMembership/votingPowerPerMembership <= 1e18
                totalMembershipsForSale: 30,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        sellPartyCardsAuthority.createFixedMembershipSale(opts);
    }

    function testSellPartyCards_precision_lowerPrice() public {
        SellPartyCardsAuthority.FixedMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FixedMembershipSaleOpts({
                pricePerMembership: 1,
                votingPowerPerMembership: 10 ether, // votingPowerPerMembership/pricePerMembership can be much greater than 1e18
                totalMembershipsForSale: 30,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        sellPartyCardsAuthority.createFixedMembershipSale(opts);
    }

    function _createNewFixedSale() internal returns (uint256) {
        SellPartyCardsAuthority.FixedMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FixedMembershipSaleOpts({
                pricePerMembership: 1 ether,
                votingPowerPerMembership: 0.001 ether,
                totalMembershipsForSale: 3,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        return sellPartyCardsAuthority.createFixedMembershipSale(opts);
    }

    function _createNewFlexibleSale() internal returns (uint256) {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 0.001 ether,
                maxContribution: 2 ether,
                maxTotalContributions: 3 ether,
                exchangeRate: 1e18,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        return sellPartyCardsAuthority.createFlexibleMembershipSale(opts);
    }
}
