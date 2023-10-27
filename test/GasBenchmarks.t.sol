// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper, Vm } from "./utils/SetupPartyHelper.sol";
import { Party } from "../contracts/party/Party.sol";
import { MetadataProvider } from "../contracts/renderers/MetadataProvider.sol";
import { PartyNFTRenderer } from "../contracts/renderers/PartyNFTRenderer.sol";
import { PartyGovernance } from "../contracts/party/PartyGovernance.sol";
import { ArbitraryCallsProposal } from "../contracts/proposals/ArbitraryCallsProposal.sol";
import { ProposalExecutionEngine } from "../contracts/proposals/ProposalExecutionEngine.sol";
import { DistributeProposal } from "../contracts/proposals/DistributeProposal.sol";
import { ITokenDistributor } from "../contracts/distribution/ITokenDistributor.sol";
import { InitialETHCrowdfund } from "../contracts/crowdfund/InitialETHCrowdfund.sol";
import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

contract GasBenchmarks is SetupPartyHelper {
    using Clones for address;

    constructor() SetupPartyHelper(false) {}

    /// @notice Gas benchmark the creation of a basic party
    function testCreateParty_vanilla() public {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        Party.PartyOptions memory opts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 301;

        uint256 gasLeft = gasleft();
        partyFactory.createParty(partyImpl, authorities, opts, preciousTokens, preciousTokenIds, 0);
        uint256 gasUsed = gasLeft - gasleft();
        emit log_named_uint("Create party vanilla", gasUsed);
    }

    /// @notice Gas benchmark the creation of a party with a custom description and image.
    function testCreateParty_customMetadata() public {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        Party.PartyOptions memory opts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 301;

        MetadataProvider metadataProvider = new MetadataProvider(globals);
        bytes memory metadata = abi.encode(
            PartyNFTRenderer.Metadata({
                name: "",
                description: "hello world!",
                externalURL: "",
                image: "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq",
                banner: "",
                animationURL: "",
                collectionName: "",
                collectionDescription: "",
                collectionExternalURL: "",
                royaltyReceiver: address(0),
                royaltyAmount: 0,
                renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
            })
        );

        uint256 gasLeft = gasleft();
        partyFactory.createPartyWithMetadata(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            metadataProvider,
            metadata
        );
        uint256 gasUsed = gasLeft - gasleft();
        emit log_named_uint("Create party custom metadata", gasUsed);
    }

    /// @notice Gas benchmark the proposal and execution of an eth transfer proposal.
    function testProposal_transferEth() public {
        // Give the party some eth to spend
        vm.deal(address(party), 100);
        ArbitraryCallsProposal.ArbitraryCall[]
            memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](1);
        arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
            target: _randomAddress(),
            value: 100,
            data: "",
            expectedResultHash: 0
        });
        PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                arbCalls
            )
        });
        uint256 latestSnap = party.findVotingPowerSnapshotIndex(john, uint40(block.timestamp - 1));
        vm.prank(john);
        uint256 gasLeft = gasleft();
        party.propose(proposal, latestSnap);
        uint256 gasUsed = gasLeft - gasleft();
        emit log_named_uint("Create proposal transfer eth", gasUsed);

        vm.warp(block.timestamp + _EXECUTION_DELAY);
        vm.prank(john);
        gasLeft = gasleft();
        party.execute(1, proposal, preciousTokens, preciousTokenIds, "", "");
        gasUsed = gasLeft - gasleft();
        emit log_named_uint("Execute proposal transfer eth", gasUsed);
    }

    /// @notice Gas benchmark the proposal and execution of an eth distribution proposal.
    function testPropose_distribute() public {
        vm.deal(address(party), 1 ether);
        DistributeProposal.DistributeProposalData memory distProposal = DistributeProposal
            .DistributeProposalData({
                amount: 1 ether,
                tokenType: ITokenDistributor.TokenType.Native,
                token: address(0),
                tokenId: 0
            });
        PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.Distribute)),
                distProposal
            )
        });
        vm.prank(john);
        uint256 gasLeft = gasleft();
        party.propose(proposal, 0);
        uint256 gasUsed = gasLeft - gasleft();
        emit log_named_uint("Create proposal distribute", gasUsed);

        vm.warp(block.timestamp + _EXECUTION_DELAY);
        vm.recordLogs();
        vm.prank(john);
        gasLeft = gasleft();
        party.execute(1, proposal, preciousTokens, preciousTokenIds, "", "");
        gasUsed = gasLeft - gasleft();
        emit log_named_uint("Execute proposal distribute", gasUsed);

        ITokenDistributor.DistributionInfo memory info;

        // Extract distribution info from the events
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].emitter != address(tokenDistributor)) {
                continue;
            }
            info = abi.decode(entries[i].data, (ITokenDistributor.DistributionInfo));
        }

        vm.prank(john);
        gasLeft = gasleft();
        tokenDistributor.claim(info, 1);
        gasUsed = gasLeft - gasleft();
        emit log_named_uint("Claim distribution", gasUsed);
    }

    function _setupETHCrowdfund() internal returns (InitialETHCrowdfund) {
        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        crowdfundOpts.minContribution = 0.01 ether;
        crowdfundOpts.maxContribution = 0.01 ether;
        crowdfundOpts.disableContributingForExistingCard = true;
        crowdfundOpts.maxTotalContributions = 10 ether;
        crowdfundOpts.minTotalContributions = 0.01 ether;
        crowdfundOpts.exchangeRateBps = 10000;
        crowdfundOpts.duration = 100;

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        partyOpts.name = "PARTY";
        partyOpts.symbol = "PR-T";
        partyOpts.governanceOpts.hosts = hosts;
        partyOpts.governanceOpts.voteDuration = 99;
        partyOpts.governanceOpts.executionDelay = _EXECUTION_DELAY;
        partyOpts.governanceOpts.passThresholdBps = 1000;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.partyImpl = partyImpl;

        InitialETHCrowdfund crowdfundImpl = new InitialETHCrowdfund(globals);
        InitialETHCrowdfund crowdfund = InitialETHCrowdfund(address(crowdfundImpl).clone());
        crowdfund.initialize(crowdfundOpts, partyOpts, MetadataProvider(address(0)), "");
        return crowdfund;
    }

    /// @notice Gas benchmark of contributing to an ETHParty membership mint twice
    function testCrowdfundContribute_ETHCrowdfund_Twice() public {
        InitialETHCrowdfund crowdfund = _setupETHCrowdfund();

        InitialETHCrowdfund.BatchContributeArgs memory batchContributeArgs;
        batchContributeArgs.tokenIds = new uint256[](2);
        batchContributeArgs.delegate = address(this);
        batchContributeArgs.values = new uint96[](2);
        batchContributeArgs.values[0] = 0.01 ether;
        batchContributeArgs.values[1] = 0.01 ether;
        batchContributeArgs.gateDatas = new bytes[](2);

        uint256 gasLeft = gasleft();
        crowdfund.batchContribute{ value: 0.02 ether }(batchContributeArgs);
        uint256 gasUsed = gasLeft - gasleft();
        emit log_named_uint("Batch contribute two memberships to ETH party", gasUsed);
    }

    /// @notice Gas benchmark of contributing to an ETHParty membezrship mint
    function testCrowdfundContribute_ETHCrowdfund() public {
        InitialETHCrowdfund crowdfund = _setupETHCrowdfund();

        uint256 gasLeft = gasleft();
        crowdfund.contribute{ value: 0.01 ether }(address(this), "");
        uint256 gasUsed = gasLeft - gasleft();
        emit log_named_uint("Contribute to ETH party", gasUsed);
    }
}
