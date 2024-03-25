// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper, Party } from "../utils/SetupPartyHelper.sol";
import { IERC20 } from "openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20Creator, IUniswapV2Router02, IUniswapV2Factory, ITokenDistributor } from "erc20-creator/ERC20Creator.sol";
import { ERC20LaunchCrowdfund, IERC20Creator } from "contracts/crowdfund/ERC20LaunchCrowdfund.sol";
import { CrowdfundFactory } from "contracts/crowdfund/CrowdfundFactory.sol";
import { Vm } from "forge-std/Test.sol";

contract ERC20LaunchCrowdfundForkedTest is SetupPartyHelper {
    constructor() onlyForked SetupPartyHelper(true) {}

    ERC20Creator internal creator;
    ERC20LaunchCrowdfund internal launchCrowdfundImpl;
    CrowdfundFactory internal crowdfundFactory;

    function setUp() public override onlyForked {
        super.setUp();

        // Existing addresses on Sepolia
        creator = new ERC20Creator(
            ITokenDistributor(address(tokenDistributor)),
            IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D),
            IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            address(0),
            0
        );
        launchCrowdfundImpl = new ERC20LaunchCrowdfund(globals, IERC20Creator(address(creator)));
        crowdfundFactory = new CrowdfundFactory();
    }

    function test_ERC20LaunchCrowdfund_happy_path() public onlyForked {
        ERC20LaunchCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        ERC20LaunchCrowdfund.ETHPartyOptions memory partyOpts;
        ERC20LaunchCrowdfund.ERC20LaunchOptions memory tokenOpts;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfundOpts.maxTotalContributions = 1 ether;
        crowdfundOpts.minTotalContributions = 0.001 ether;
        crowdfundOpts.exchangeRate = 1 ether;
        crowdfundOpts.minContribution = 0.001 ether;
        crowdfundOpts.maxContribution = 1 ether;
        crowdfundOpts.duration = 1 days;
        crowdfundOpts.fundingSplitRecipient = payable(address(this));
        crowdfundOpts.fundingSplitBps = 0.1e4;

        tokenOpts.name = "Test ERC20";
        tokenOpts.symbol = "TEST";
        tokenOpts.totalSupply = 1e6 ether;
        tokenOpts.recipient = address(this);
        tokenOpts.numTokensForDistribution = 5e4 ether;
        tokenOpts.numTokensForRecipient = 5e4 ether;
        tokenOpts.numTokensForLP = 9e5 ether;

        ERC20LaunchCrowdfund launchCrowdfund = crowdfundFactory.createERC20LaunchCrowdfund(
            launchCrowdfundImpl,
            crowdfundOpts,
            partyOpts,
            tokenOpts,
            ""
        );

        address contributor = _randomAddress();
        vm.deal(contributor, 2 ether);
        vm.prank(contributor);
        vm.recordLogs();
        launchCrowdfund.contribute{ value: 1 ether }(contributor, "");
        launchCrowdfund.launchToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 balanceBefore = address(this).balance;
        launchCrowdfund.sendFundingSplit();
        assertEq(address(this).balance, balanceBefore + 0.1 ether);

        ITokenDistributor.DistributionInfo memory info;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(tokenDistributor)) {
                continue;
            }
            if (
                logs[i].topics[0] !=
                keccak256(
                    "DistributionCreated(address,(uint8,uint256,address,address,address,uint128,uint128,uint96))"
                )
            ) {
                continue;
            }
            info = abi.decode(logs[i].data, (ITokenDistributor.DistributionInfo));
        }

        vm.prank(contributor);

        bytes memory callData = abi.encodeCall(ITokenDistributor.claim, (info, 1));
        address(tokenDistributor).call(callData);

        assertEq(IERC20(info.token).balanceOf(contributor), 5e4 ether);
        assertEq(IERC20(info.token).balanceOf(address(this)), 5e4 ether);
    }

    function test_ERC20LaunchCrowdfund_revertIfNumTokensNotAddUpToTotal() public onlyForked {
        ERC20LaunchCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        ERC20LaunchCrowdfund.ETHPartyOptions memory partyOpts;
        ERC20LaunchCrowdfund.ERC20LaunchOptions memory tokenOpts;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfundOpts.maxTotalContributions = 1 ether;
        crowdfundOpts.minTotalContributions = 0.001 ether;
        crowdfundOpts.exchangeRate = 1 ether;
        crowdfundOpts.minContribution = 0.001 ether;
        crowdfundOpts.maxContribution = 1 ether;
        crowdfundOpts.duration = 1 days;
        crowdfundOpts.fundingSplitRecipient = payable(address(this));
        crowdfundOpts.fundingSplitBps = 0.1e4;

        tokenOpts.name = "Test ERC20";
        tokenOpts.symbol = "TEST";
        tokenOpts.totalSupply = 1e6 ether;
        tokenOpts.recipient = address(this);
        tokenOpts.numTokensForDistribution = 5e4 ether + 1; // Add 1 to make it invalid
        tokenOpts.numTokensForRecipient = 5e4 ether;
        tokenOpts.numTokensForLP = 9e5 ether;

        vm.expectRevert(ERC20LaunchCrowdfund.InvalidTokenDistribution.selector);
        ERC20LaunchCrowdfund launchCrowdfund = crowdfundFactory.createERC20LaunchCrowdfund(
            launchCrowdfundImpl,
            crowdfundOpts,
            partyOpts,
            tokenOpts,
            ""
        );
    }

    function test_ERC20LaunchCrowdfund_revertIfNumTokensForLPIsTooLow() public onlyForked {
        ERC20LaunchCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        ERC20LaunchCrowdfund.ETHPartyOptions memory partyOpts;
        ERC20LaunchCrowdfund.ERC20LaunchOptions memory tokenOpts;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfundOpts.maxTotalContributions = 1 ether;
        crowdfundOpts.minTotalContributions = 0.001 ether;
        crowdfundOpts.exchangeRate = 1 ether;
        crowdfundOpts.minContribution = 0.001 ether;
        crowdfundOpts.maxContribution = 1 ether;
        crowdfundOpts.duration = 1 days;
        crowdfundOpts.fundingSplitRecipient = payable(address(this));
        crowdfundOpts.fundingSplitBps = 0.1e4;

        tokenOpts.name = "Test ERC20";
        tokenOpts.symbol = "TEST";
        tokenOpts.totalSupply = 1e6 ether;
        tokenOpts.recipient = address(this);
        tokenOpts.numTokensForDistribution = 5e4 ether;
        tokenOpts.numTokensForRecipient = 5e4 ether;
        tokenOpts.numTokensForLP = 1e4 - 1; // Too low

        vm.expectRevert(ERC20LaunchCrowdfund.InvalidTokenDistribution.selector);
        ERC20LaunchCrowdfund launchCrowdfund = crowdfundFactory.createERC20LaunchCrowdfund(
            launchCrowdfundImpl,
            crowdfundOpts,
            partyOpts,
            tokenOpts,
            ""
        );
    }

    function test_ERC20LaunchCrowdfund_revertIfFundingSplitBpsTooHigh() public onlyForked {
        ERC20LaunchCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        ERC20LaunchCrowdfund.ETHPartyOptions memory partyOpts;
        ERC20LaunchCrowdfund.ERC20LaunchOptions memory tokenOpts;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfundOpts.maxTotalContributions = 1 ether;
        crowdfundOpts.minTotalContributions = 0.001 ether;
        crowdfundOpts.exchangeRate = 1 ether;
        crowdfundOpts.minContribution = 0.001 ether;
        crowdfundOpts.maxContribution = 1 ether;
        crowdfundOpts.duration = 1 days;
        crowdfundOpts.fundingSplitRecipient = payable(address(this));
        crowdfundOpts.fundingSplitBps = 0.5e4 + 1; // Too high

        tokenOpts.name = "Test ERC20";
        tokenOpts.symbol = "TEST";
        tokenOpts.totalSupply = 1e6 ether;
        tokenOpts.recipient = address(this);
        tokenOpts.numTokensForDistribution = 5e4 ether;
        tokenOpts.numTokensForRecipient = 5e4 ether;
        tokenOpts.numTokensForLP = 9e5 ether;

        vm.expectRevert(ERC20LaunchCrowdfund.InvalidTokenDistribution.selector);
        ERC20LaunchCrowdfund launchCrowdfund = crowdfundFactory.createERC20LaunchCrowdfund(
            launchCrowdfundImpl,
            crowdfundOpts,
            partyOpts,
            tokenOpts,
            ""
        );
    }

    function test_ERC20LaunchCrowdfund_canClaimAsLastMember() public onlyForked {
        ERC20LaunchCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        ERC20LaunchCrowdfund.ETHPartyOptions memory partyOpts;
        ERC20LaunchCrowdfund.ERC20LaunchOptions memory tokenOpts;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfundOpts.maxTotalContributions = 1 ether;
        crowdfundOpts.minTotalContributions = 0.001 ether;
        crowdfundOpts.exchangeRate = 1 ether;
        crowdfundOpts.minContribution = 0.001 ether;
        crowdfundOpts.maxContribution = 1 ether;
        crowdfundOpts.duration = 1 days;
        crowdfundOpts.fundingSplitRecipient = payable(address(this));
        crowdfundOpts.fundingSplitBps = 0.1e4;

        tokenOpts.name = "Test ERC20";
        tokenOpts.symbol = "TEST";
        tokenOpts.totalSupply = 1e6 ether;
        tokenOpts.recipient = address(this);
        tokenOpts.numTokensForDistribution = 5e4 ether;
        tokenOpts.numTokensForRecipient = 5e4 ether;
        tokenOpts.numTokensForLP = 9e5 ether;

        ERC20LaunchCrowdfund launchCrowdfund = crowdfundFactory.createERC20LaunchCrowdfund(
            launchCrowdfundImpl,
            crowdfundOpts,
            partyOpts,
            tokenOpts,
            ""
        );

        address contributor1 = _randomAddress();
        vm.deal(contributor1, 2 ether);
        vm.prank(contributor1);
        vm.recordLogs();
        launchCrowdfund.contribute{ value: 0.5 ether }(contributor1, "");
        address contributor2 = _randomAddress();
        vm.deal(contributor2, 2 ether);
        vm.prank(contributor2);
        vm.recordLogs();
        launchCrowdfund.contribute{ value: 0.5 ether }(contributor2, "");
        launchCrowdfund.launchToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 balanceBefore = address(this).balance;
        launchCrowdfund.sendFundingSplit();
        assertEq(address(this).balance, balanceBefore + 0.1 ether);

        ITokenDistributor.DistributionInfo memory info;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(tokenDistributor)) {
                continue;
            }
            if (
                logs[i].topics[0] !=
                keccak256(
                    "DistributionCreated(address,(uint8,uint256,address,address,address,uint128,uint128,uint96))"
                )
            ) {
                continue;
            }
            info = abi.decode(logs[i].data, (ITokenDistributor.DistributionInfo));
        }

        Party launchParty = launchCrowdfund.party();

        // Increase total voting power so that maxTokenId check in
        // TokenDistributor is triggered
        vm.prank(address(launchCrowdfund));
        launchParty.increaseTotalVotingPower(1 ether);

        // Claim as last contributor
        vm.prank(contributor2);
        bytes memory callData = abi.encodeCall(ITokenDistributor.claim, (info, 2));
        address(tokenDistributor).call(callData);

        assertEq(IERC20(info.token).balanceOf(contributor2), 2.5e4 ether);
    }

    function test_ERC20LaunchCrowdfund_finalize() public {
        ERC20LaunchCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        ERC20LaunchCrowdfund.ETHPartyOptions memory partyOpts;
        ERC20LaunchCrowdfund.ERC20LaunchOptions memory tokenOpts;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfundOpts.maxTotalContributions = 1 ether;
        crowdfundOpts.minTotalContributions = 0.001 ether;
        crowdfundOpts.exchangeRate = 1 ether;
        crowdfundOpts.minContribution = 0.001 ether;
        crowdfundOpts.maxContribution = 1 ether;
        crowdfundOpts.duration = 1 days;
        crowdfundOpts.fundingSplitRecipient = payable(address(this));
        crowdfundOpts.fundingSplitBps = 0.1e4;

        tokenOpts.name = "Test ERC20";
        tokenOpts.symbol = "TEST";
        tokenOpts.totalSupply = 1e6 ether;
        tokenOpts.recipient = address(this);
        tokenOpts.numTokensForDistribution = 5e4 ether;
        tokenOpts.numTokensForRecipient = 5e4 ether;
        tokenOpts.numTokensForLP = 9e5 ether;

        ERC20LaunchCrowdfund launchCrowdfund = crowdfundFactory.createERC20LaunchCrowdfund(
            launchCrowdfundImpl,
            crowdfundOpts,
            partyOpts,
            tokenOpts,
            ""
        );

        address contributor = _randomAddress();
        vm.deal(contributor, 2 ether);
        vm.prank(contributor);
        vm.recordLogs();
        launchCrowdfund.contribute{ value: 0.5 ether }(contributor, "");
        skip(crowdfundOpts.duration + 1);
        launchCrowdfund.finalize();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 balanceBefore = address(this).balance;
        launchCrowdfund.sendFundingSplit();
        assertEq(address(this).balance, balanceBefore + 0.05 ether);

        ITokenDistributor.DistributionInfo memory info;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(tokenDistributor)) {
                continue;
            }
            if (
                logs[i].topics[0] !=
                keccak256(
                    "DistributionCreated(address,(uint8,uint256,address,address,address,uint128,uint128,uint96))"
                )
            ) {
                continue;
            }
            info = abi.decode(logs[i].data, (ITokenDistributor.DistributionInfo));
        }

        vm.prank(contributor);

        bytes memory callData = abi.encodeCall(ITokenDistributor.claim, (info, 1));
        address(tokenDistributor).call(callData);

        assertEq(IERC20(info.token).balanceOf(contributor), 5e4 ether);
        assertEq(IERC20(info.token).balanceOf(address(this)), 5e4 ether);
    }

    receive() external payable {}
}
