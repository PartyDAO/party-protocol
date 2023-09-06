// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/globals/Globals.sol";
import "../../contracts/party/PartyFactory.sol";
import "../../contracts/crowdfund/InitialETHCrowdfund.sol";
import "../../contracts/crowdfund/ContributionRouter.sol";
import "../TestUtils.sol";

contract ContributionRouterGasBenchmarkTest is TestUtils {
    InitialETHCrowdfund crowdfund;
    Globals globals;
    Party partyImpl;
    PartyFactory partyFactory;

    address owner;
    uint96 feePerContribution;
    ContributionRouter router;

    constructor() {
        owner = _randomAddress();
        feePerContribution = 0.01 ether;
        router = new ContributionRouter(owner, feePerContribution);

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

    function testGas_contributeForAlone() external {
        // Setup for benchmark.
        address payable member = _randomAddress();
        uint256 amount = 1 ether;
        vm.deal(member, amount);

        // Benchmark fallback.
        vm.prank(member);
        uint256 gas = gasleft();
        crowdfund.contributeFor{ value: amount }(0, member, member, "");
        console.log("contributeFor gas used: %d", gas - gasleft());

        // Check that call behaved as expected.
        assertEq(address(crowdfund).balance, amount);
        assertEq(member.balance, 0);
    }

    function testGas_contributeForWithCallWithFee() public {
        // Setup for benchmark.
        address payable member = _randomAddress();
        uint256 amount = 1 ether;
        vm.deal(member, amount);
        bytes memory data = abi.encodeCall(
            InitialETHCrowdfund.contributeFor,
            (0, member, member, "")
        );

        // Benchmark callWithFee().
        vm.prank(member);
        uint256 gas = gasleft();
        router.callWithFee{ value: amount }(address(crowdfund), data);
        console.log("callWithFee gas used: %d", gas - gasleft());

        // Check that call behaved as expected.
        assertEq(address(crowdfund).balance, amount - feePerContribution);
        assertEq(address(router).balance, feePerContribution);
        assertEq(member.balance, 0);
    }

    function testGas_contributeForWithFallback() external {
        // Setup for benchmark.
        address payable member = _randomAddress();
        uint256 amount = 1 ether;
        vm.deal(member, amount);
        bytes memory data = abi.encodeCall(
            InitialETHCrowdfund.contributeFor,
            (0, member, member, "")
        );

        // Benchmark fallback.
        vm.prank(member);
        uint256 gas = gasleft();
        (bool success, bytes memory res) = address(router).call{ value: amount }(
            abi.encodePacked(data, address(crowdfund))
        );
        console.log("fallback gas used: %d", gas - gasleft());

        // Check that call behaved as expected.
        assertEq(success, true);
        assertEq(res.length, 0);
        assertEq(address(crowdfund).balance, amount - feePerContribution);
        assertEq(address(router).balance, feePerContribution);
        assertEq(member.balance, 0);
    }
}
