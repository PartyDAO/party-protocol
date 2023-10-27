// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import { Vm } from "forge-std/Test.sol";
import { TestUtils } from "../TestUtils.sol";
import { IERC721 } from "../../contracts/tokens/IERC721.sol";
import { GlobalsAdmin } from "../TestUsers.sol";
import { PartyFactory } from "../../contracts/party/PartyFactory.sol";
import { Globals } from "../../contracts/globals/Globals.sol";
import { Party } from "../../contracts/party/Party.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { IFractionalV1VaultFactory } from "../../contracts/proposals/vendor/FractionalV1.sol";
import { MockZoraReserveAuctionCoreEth } from "../proposals/MockZoraReserveAuctionCoreEth.sol";
import { IReserveAuctionCoreEth } from "../../contracts/vendor/markets/IReserveAuctionCoreEth.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";
import { ERC721Receiver } from "../../contracts/tokens/ERC721Receiver.sol";
import { MetadataRegistry } from "../../contracts/renderers/MetadataRegistry.sol";
import { TokenDistributor } from "../../contracts/distribution/TokenDistributor.sol";
import { OffChainSignatureValidator } from "../../contracts/signature-validators/OffChainSignatureValidator.sol";

/// @notice This contract provides a fully functioning party instance for testing.
///     Run setup from inheriting contract.
abstract contract SetupPartyHelper is TestUtils, ERC721Receiver {
    struct SetupPartyParams {
        uint96 johnVotes;
        uint96 dannyVotes;
        uint96 steveVotes;
        uint96 thisVotes;
    }

    bool private immutable _isForked;
    GlobalsAdmin internal globalsAdmin;
    Party internal party;
    Party internal partyImpl;
    Globals internal globals;
    PartyFactory internal partyFactory;
    TokenDistributor internal tokenDistributor;
    uint256 internal johnPk = 0xa11ce;
    uint256 internal dannyPk = 0xb0b;
    uint256 internal stevePk = 0xca1;
    address internal john = vm.addr(johnPk);
    address internal danny = vm.addr(dannyPk);
    address internal steve = vm.addr(stevePk);
    uint96 internal johnVotes;
    uint96 internal dannyVotes;
    uint96 internal steveVotes;
    uint96 internal thisVotes;
    IERC721[] internal preciousTokens = new IERC721[](0);
    uint256[] internal preciousTokenIds = new uint256[](0);
    uint40 internal constant _EXECUTION_DELAY = 300;

    constructor(bool isForked) {
        _isForked = isForked;
    }

    function setUpWithParams(SetupPartyParams memory params) public {
        johnVotes = params.johnVotes;
        dannyVotes = params.dannyVotes;
        steveVotes = params.steveVotes;
        thisVotes = params.thisVotes;
        SetupPartyHelper.setUp();
    }

    function setUp() public virtual {
        globalsAdmin = new GlobalsAdmin();
        globals = globalsAdmin.globals();
        partyImpl = new Party(globals);
        address globalDaoWalletAddress = address(420);
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        ProposalExecutionEngine pe = new ProposalExecutionEngine(
            globals,
            _isForked
                ? IReserveAuctionCoreEth(0x5f7072E1fA7c01dfAc7Cf54289621AFAaD2184d0)
                : new MockZoraReserveAuctionCoreEth(),
            _isForked
                ? IFractionalV1VaultFactory(0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63)
                : IFractionalV1VaultFactory(address(0))
        );

        globalsAdmin.setProposalEng(address(pe));

        partyFactory = new PartyFactory(globals);
        globalsAdmin.setGlobalPartyFactory(address(partyFactory));

        tokenDistributor = new TokenDistributor(globals, 0);
        globalsAdmin.setTokenDistributor(address(tokenDistributor));

        address[] memory registrars = new address[](2);
        registrars[0] = address(this);
        registrars[1] = address(partyFactory);
        MetadataRegistry metadataRegistry = new MetadataRegistry(globals, registrars);
        globalsAdmin.setMetadataRegistry(address(metadataRegistry));

        OffChainSignatureValidator offChainGlobalValidator = new OffChainSignatureValidator();
        globalsAdmin.setOffChainSignatureValidator(address(offChainGlobalValidator));

        johnVotes = johnVotes == 0 ? 100 : johnVotes;
        dannyVotes = dannyVotes == 0 ? 100 : dannyVotes;
        steveVotes = steveVotes == 0 ? 100 : steveVotes;
        thisVotes = thisVotes == 0 ? 1 : thisVotes;

        Party.PartyOptions memory opts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.proposalEngine.allowArbCallsToSpendPartyEth = true;
        opts.proposalEngine.distributionsRequireVote = true;
        opts.governance.totalVotingPower = johnVotes + dannyVotes + steveVotes + thisVotes;

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);
        party = partyFactory.createParty(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            0
        );
        party.mint(john, johnVotes, john);
        party.mint(danny, dannyVotes, danny);
        party.mint(steve, steveVotes, steve);
        party.mint(address(this), thisVotes, address(this));
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 10);
    }

    /// @notice Propose pass and wait for the execution delay of a proposal
    /// @param proposal The `PartyGovernance.Proposal` struct representing the proposal
    /// @return proposalId The proposal id for the proposal
    function _proposeAndPassProposal(
        PartyGovernance.Proposal memory proposal
    ) internal returns (uint256 proposalId) {
        vm.prank(john);
        proposalId = party.propose(proposal, 0);

        vm.warp(block.timestamp + _EXECUTION_DELAY);
    }

    /// @notice Propose pass and execute the proposal
    /// @param proposal The `PartyGovernance.Proposal` struct representing the proposal
    /// @return proposalId The proposal id for the proposal
    /// @return progressData The progress data returned from the proposal execution
    function _proposePassAndExecuteProposal(
        PartyGovernance.Proposal memory proposal
    ) internal returns (uint256, bytes memory) {
        uint256 proposalId = _proposeAndPassProposal(proposal);
        bytes memory progressData = _executeProposal(proposalId, proposal);
        return (proposalId, progressData);
    }

    /// @notice Execute the given proposal
    /// @param proposalId The proposal id for the proposal
    /// @param proposal The `PartyGovernance.Proposal` struct representing the proposal
    /// @return progressData The progress data returned from the proposal execution
    function _executeProposal(
        uint256 proposalId,
        PartyGovernance.Proposal memory proposal
    ) internal returns (bytes memory) {
        return _executeProposal(proposalId, proposal, "");
    }

    /// @notice Execute the given proposal with `progressData`
    /// @param proposalId The proposal id for the proposal
    /// @param proposal The `PartyGovernance.Proposal` struct representing the proposal
    /// @param progressData The progress data to pass to the proposal execution
    /// @return progressData The progress data returned from the proposal execution
    function _executeProposal(
        uint256 proposalId,
        PartyGovernance.Proposal memory proposal,
        bytes memory progressData
    ) internal returns (bytes memory) {
        vm.recordLogs();
        party.execute(proposalId, proposal, preciousTokens, preciousTokenIds, progressData, "");

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes memory nextProgressData;

        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].emitter != address(party)) {
                continue;
            }
            if (entries[i].topics[0] != keccak256("ProposalExecuted(uint256,address,bytes)")) {
                continue;
            }

            bytes memory entryData = entries[i].data;
            (, nextProgressData) = abi.decode(entryData, (address, bytes));
        }

        return nextProgressData;
    }
}
