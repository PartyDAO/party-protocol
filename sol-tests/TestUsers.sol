// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../contracts/globals/Globals.sol";
import "../contracts/globals/LibGlobals.sol";
import "../contracts/party/Party.sol";
import "../contracts/party/PartyFactory.sol";

contract ERC721Holder {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract GlobalsAdmin is Test {
  Globals public globals;

  constructor() {
    globals = new Globals(address(this));
    vm.deal(address(this), 100 ether);
  }

  function setPartyImpl(address partyImplAddress) public {
    globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, partyImplAddress);
  }

  function setProposalEng(address proposalEngAddress) public {
    globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, proposalEngAddress);
  }

  function setGlobalDaoWallet(address anAddress) public {
    globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, anAddress);
  }
}

contract PartyAdmin is Test {

  struct PartyCreationMinimalOptions {
    address host1;
    address host2;
    uint16 passThresholdBps;
    uint96 totalVotingPower;
    address preciousTokenAddress;
    uint256 preciousTokenId;
  }

  function createParty(
    PartyFactory partyFactory,
    PartyCreationMinimalOptions calldata opts
  ) public returns (Party, IERC721[] memory, uint256[] memory) {
    address[] memory hosts = new address[](2);
    hosts[0] = opts.host1;
    hosts[1] = opts.host2;

    PartyGovernance.GovernanceOpts memory govOpts = PartyGovernance.GovernanceOpts({
      hosts: hosts,
      voteDuration: 99,
      executionDelay: 300,
      passThresholdBps: opts.passThresholdBps,
      totalVotingPower: opts.totalVotingPower
    });
    Party.PartyOptions memory po = Party.PartyOptions({
      governance: govOpts,
      name: 'Dope party',
      symbol: 'DOPE'
    });
    IERC721[] memory preciousTokens = new IERC721[](1);
    preciousTokens[0] = IERC721(opts.preciousTokenAddress);

    uint256[] memory preciousTokenIds = new uint256[](1);
    preciousTokenIds[0] = opts.preciousTokenId;

    Party party = partyFactory.createParty(
      address(this), po, preciousTokens, preciousTokenIds
    );
    return (party, preciousTokens, preciousTokenIds);
  }

  function mintGovNft(
    Party party,
    address mintTo,
    uint256 votingPower,
    address delegateTo
  ) public {
    party.mint(mintTo, votingPower, delegateTo);
  }

  function mintGovNft(
    Party party,
    address mintTo,
    uint256 votingPower
  ) public {
    party.mint(mintTo, votingPower, mintTo);
  }
}

contract PartyParticipant is ERC721Holder, Test  {

  constructor() {
    vm.deal(address(this), 100 ether);
  }

  struct ExecutionOptions {
    uint256 proposalId;
    PartyGovernance.Proposal proposal;
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;
    bytes progressData;
  }

  function makeProposal(
    Party party, PartyGovernance.Proposal memory proposal
  ) public {
    party.propose(proposal);
  }

  function vote(Party party, uint256 proposalId) public {
    party.accept(proposalId);
  }

  function delegate(Party party, address newDelegate) public {
    party.delegateVotingPower(newDelegate);
  }

  function executeProposal(
    Party party,
    ExecutionOptions memory eo
  ) public {
    party.execute(
      eo.proposalId, eo.proposal, eo.preciousTokens, eo.preciousTokenIds, eo.progressData
    );
  }

  function vetoProposal(
    Party party,
    uint256 proposalId
  ) public {
    party.veto(proposalId);
  }
}