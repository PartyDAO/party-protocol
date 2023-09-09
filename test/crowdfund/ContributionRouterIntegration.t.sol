// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/globals/Globals.sol";
import "../../contracts/party/PartyFactory.sol";
import "../../contracts/crowdfund/InitialETHCrowdfund.sol";
import "../../contracts/crowdfund/ContributionRouter.sol";

import "../TestUtils.sol";

contract ContributionRouterIntegrationTest is TestUtils {
    InitialETHCrowdfund crowdfund;
    Globals globals;
    Party partyImpl;
    PartyFactory partyFactory;

    uint96 feePerMint;
    ContributionRouter router;

    constructor() {
        feePerMint = 0.01 ether;
        router = new ContributionRouter(address(this), feePerMint);

        globals = new Globals(address(this));
        partyImpl = new Party(globals);
        partyFactory = new PartyFactory(globals);

        InitialETHCrowdfund initialETHCrowdfundImpl = new InitialETHCrowdfund(globals);

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        crowdfundOpts.maxContribution = type(uint96).max;
        crowdfundOpts.maxTotalContributions = type(uint96).max;
        crowdfundOpts.duration = 7 days;
        crowdfundOpts.exchangeRateBps = 1e4;

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts;
        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfund = InitialETHCrowdfund(
            payable(
                new Proxy(
                    initialETHCrowdfundImpl,
                    abi.encodeCall(
                        InitialETHCrowdfund.initialize,
                        (crowdfundOpts, partyOpts, MetadataProvider(address(0)), "")
                    )
                )
            )
        );
    }

    function test_contributionFee_withSingleMint() public {
        // Setup for contribution.
        address payable member = _randomAddress();
        uint256 amount = 1 ether;
        vm.deal(member, amount);
        bytes memory data = abi.encodeCall(
            InitialETHCrowdfund.contributeFor,
            (0, member, member, "")
        );

        // Make contribution.
        vm.prank(member);
        (bool success, bytes memory res) = address(router).call{ value: amount }(
            abi.encodePacked(data, address(crowdfund))
        );

        // Check results.
        assertEq(success, true);
        assertEq(res.length, 0);
        assertEq(address(crowdfund).balance, amount - feePerMint);
        assertEq(address(router).balance, feePerMint);
        assertEq(member.balance, 0);
    }

    function test_contributionFee_withBatchMint() public {
        // Setup for contribution.
        address payable member = _randomAddress();
        uint96 amount = 1 ether;
        uint256 numOfMints;
        uint256[] memory tokenIds = new uint256[](numOfMints);
        address payable[] memory recipients = new address payable[](numOfMints);
        address[] memory delegates = new address[](numOfMints);
        uint96[] memory values = new uint96[](numOfMints);
        bytes[] memory gateDatas = new bytes[](numOfMints);
        for (uint256 i; i < numOfMints; ++i) {
            recipients[i] = _randomAddress();
            delegates[i] = _randomAddress();
            values[i] = amount;
        }
        vm.deal(member, amount * numOfMints);
        bytes memory data = abi.encodeCall(
            InitialETHCrowdfund.batchContributeFor,
            (
                InitialETHCrowdfund.BatchContributeForArgs({
                    tokenIds: tokenIds,
                    recipients: recipients,
                    initialDelegates: delegates,
                    values: values,
                    gateDatas: gateDatas,
                    revertOnFailure: true
                })
            )
        );

        // Make contribution.
        vm.prank(member);
        (bool success, bytes memory res) = address(router).call{ value: amount * numOfMints }(
            abi.encodePacked(data, address(crowdfund))
        );

        // Check results.
        assertEq(success, true);
        assertEq(res.length, 0);
        assertEq(address(crowdfund).balance, (amount - feePerMint) * numOfMints);
        assertEq(address(router).balance, feePerMint * numOfMints);
        assertEq(member.balance, 0);
    }
}
