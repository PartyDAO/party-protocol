// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { SellPartyCardsAuthority } from "contracts/authorities/SellPartyCardsAuthority.sol";
import { IGateKeeper } from "contracts/gatekeepers/IGateKeeper.sol";

contract SellPartyCardsAuthorityTest is SetupPartyHelper {
    event Contributed(
        address indexed sender,
        address indexed contributor,
        uint96 amount,
        address delegate
    );

    constructor() SetupPartyHelper(false) {}

    SellPartyCardsAuthority internal sellPartyCardsAuthority;

    function setUp() public override {
        super.setUp();
        sellPartyCardsAuthority = new SellPartyCardsAuthority();

        vm.prank(address(party));
        party.addAuthority(address(sellPartyCardsAuthority));
    }

    function testSellPartyCards_createNewFixedSaleAndBuyOut() public {
        uint96 originalTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 saleId = _createNewFixedSale();
        assertEq(originalTotalVotingPower, party.getGovernanceValues().totalVotingPower);

        for (uint i = 0; i < 3; i++) {
            address buyer = _randomAddress();
            vm.deal(buyer, 1 ether);
            vm.prank(buyer);
            vm.expectEmit(true, true, true, true);
            emit Contributed(buyer, buyer, 1 ether, buyer);
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
            vm.deal(buyer, 2 ether);
            vm.prank(buyer);
            vm.expectEmit(true, true, true, true);
            emit Contributed(buyer, buyer, uint96(0.001 ether + i * 0.998 ether), buyer);
            sellPartyCardsAuthority.contribute{ value: 0.001 ether + i * 0.998 ether }(
                party,
                saleId,
                buyer,
                ""
            );
            assertEq(party.balanceOf(buyer), 1);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
            assertEq(
                party.getVotingPowerAt(buyer, uint40(block.timestamp)),
                0.001 ether + i * 0.998 ether
            );
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
        emit Contributed(buyer, buyer, 0.003 ether, buyer);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");

        // Don't allow further contributions
        buyer = _randomAddress();
        vm.prank(buyer);
        vm.expectRevert(SellPartyCardsAuthority.SaleInactiveError.selector);
        sellPartyCardsAuthority.contribute{ value: 1 ether }(party, saleId, buyer, "");
    }

    function testSellPartyCards_createNewFixedSaleAndBuyOut_batchContribute() public {
        uint96 originalTotalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint256 saleId = _createNewFixedSale();
        assertEq(originalTotalVotingPower, party.getGovernanceValues().totalVotingPower);

        address buyer = _randomAddress();
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);

        uint96[] memory values = new uint96[](3);
        for (uint i = 0; i < 3; i++) {
            values[i] = 1 ether;
        }

        SellPartyCardsAuthority.BatchContributeArgs memory args = SellPartyCardsAuthority
            .BatchContributeArgs({
                party: party,
                saleId: saleId,
                delegate: buyer,
                gateData: "",
                values: values
            });

        sellPartyCardsAuthority.batchContribute{ value: 3 ether }(args);
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
                exchangeRateBps: 1e4,
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
                exchangeRateBps: 1e4,
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
                exchangeRateBps: 0,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                duration: 100,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            });

        vm.prank(address(party));
        vm.expectRevert(SellPartyCardsAuthority.ZeroExchangeRateBpsError.selector);
        sellPartyCardsAuthority.createFlexibleMembershipSale(opts);
    }

    function testSellPartyCards_createSale_invalidFundingSplit() public {
        SellPartyCardsAuthority.FlexibleMembershipSaleOpts memory opts = SellPartyCardsAuthority
            .FlexibleMembershipSaleOpts({
                minContribution: 1 ether,
                maxContribution: 2 ether,
                maxTotalContributions: 5 ether,
                exchangeRateBps: 1e4,
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
        emit Contributed(buyer, receiver, 1 ether, receiver);
        sellPartyCardsAuthority.contributeFor{ value: 1 ether }(
            party,
            saleId,
            receiver,
            receiver,
            ""
        );

        assertEq(party.balanceOf(receiver), 1);
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
                exchangeRateBps: 1e4,
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
