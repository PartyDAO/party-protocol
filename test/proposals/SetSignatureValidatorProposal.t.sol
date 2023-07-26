// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";
import { TestUtils } from "../TestUtils.sol";
import { SetSignatureValidatorProposal } from "../../contracts/proposals/SetSignatureValidatorProposal.sol";
import { IProposalExecutionEngine } from "../../contracts/proposals/IProposalExecutionEngine.sol";
import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC721 } from "../../contracts/tokens/IERC721.sol";
import { PartyParticipant, GlobalsAdmin, PartyAdmin } from "../TestUsers.sol";
import { PartyFactory } from "../../contracts/party/PartyFactory.sol";
import { Globals } from "../../contracts/globals/Globals.sol";
import { Party } from "../../contracts/party/Party.sol";
import { TokenDistributor } from "../../contracts/distribution/TokenDistributor.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { IFractionalV1VaultFactory } from "../../contracts/proposals/vendor/FractionalV1.sol";
import { MockZoraReserveAuctionCoreEth } from "./MockZoraReserveAuctionCoreEth.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";

contract SetSignatureValidatorProposalTest is Test, TestUtils {
    event SignatureValidatorSet(bytes32 indexed hash, IERC1271 indexed signatureValidator);

    GlobalsAdmin globalsAdmin;
    Globals globals;
    Party party;
    TokenDistributor tokenDistributor;
    PartyFactory partyFactory;
    uint256 internal johnPk = 0xa11ce;
    uint256 internal dannyPk = 0xb0b;
    uint256 internal stevePk = 0xca1;
    address internal john = vm.addr(johnPk);
    address internal danny = vm.addr(dannyPk);
    address internal steve = vm.addr(stevePk);
    IERC721[] preciousTokens = new IERC721[](0);
    uint256[] preciousTokenIds = new uint256[](0);
    uint40 internal constant _EXECUTION_DELAY = 300;

    function setUp() public {
        globalsAdmin = new GlobalsAdmin();
        globals = globalsAdmin.globals();
        Party partyImpl = new Party(globals);
        address globalDaoWalletAddress = address(420);
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        tokenDistributor = new TokenDistributor(globals, 0);
        globalsAdmin.setTokenDistributor(address(tokenDistributor));

        ProposalExecutionEngine pe = new ProposalExecutionEngine(
            globals,
            new MockZoraReserveAuctionCoreEth(),
            IFractionalV1VaultFactory(address(0))
        );
        globalsAdmin.setProposalEng(address(pe));

        Party.PartyOptions memory opts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 300;

        partyFactory = new PartyFactory();
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
        party.mint(john, 100, john);
        party.mint(danny, 100, danny);
        party.mint(steve, 100, steve);
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 10);
    }

    function testSetValidatorForHash() public {
        PartyGovernance.Proposal memory proposal = _createTestProposal(
            keccak256("hello"),
            IERC1271(address(1))
        );

        vm.prank(john);
        uint256 proposalId = party.propose(proposal, 0);

        vm.warp(block.timestamp + _EXECUTION_DELAY);

        vm.expectEmit(true, true, true, true);
        emit SignatureValidatorSet(keccak256("hello"), IERC1271(address(1)));
        vm.prank(john);
        party.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");

        assertEq(_getValidatorForHash(keccak256("hello")), address(1));
    }

    function _createTestProposal(
        bytes32 hash,
        IERC1271 validator
    ) private view returns (PartyGovernance.Proposal memory proposal) {
        SetSignatureValidatorProposal.SetSignatureValidatorProposalData
            memory data = SetSignatureValidatorProposal.SetSignatureValidatorProposalData({
                signatureHash: hash,
                signatureValidator: validator
            });

        proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.SetSignatureValidatorProposal)),
                data
            )
        });
    }

    function _getValidatorForHash(bytes32 hash) internal returns (address) {
        (bool success, bytes memory res) = address(party).staticcall(
            abi.encodeWithSelector(
                SetSignatureValidatorProposal.getSignatureValidatorForHash.selector,
                hash
            )
        );
        assertTrue(success);
        return abi.decode(res, (address));
    }
}
