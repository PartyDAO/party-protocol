// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import '../contracts/tokens/IERC721.sol';
import "../contracts/party/PartyFactory.sol";
import "../contracts/party/PartyGovernance.sol";
import "../contracts/proposals/ListOnZoraProposal.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";

contract RinkebyZoraProposal is Test {

  address constant PARTY_ADDRESS = 0xA5C1c616968268Ed31098397ca46Be3fFB8daAE1;
  address constant NFT_CONTRACT_ADDRESS = 0x15cBc9615CC058F6Eb9F5c584027511207C96A73;
  uint256 constant NFT_TOKEN_ID = 421;
  uint256 constant NONCE = 1;

  function run() public {
    vm.startBroadcast();
    PartyGovernance party = PartyGovernance(PARTY_ADDRESS);

    IERC721 nft = IERC721(NFT_CONTRACT_ADDRESS);
    if (nft.ownerOf(NFT_TOKEN_ID) != address(party)) {
      revert("party doesnt have NFT");
    }
    ListOnZoraProposal.ZoraProposalData memory zpd = ListOnZoraProposal.ZoraProposalData({
      listPrice: 4.269 ether,
      duration: 48 hours,
      token: nft,
      tokenId: NFT_TOKEN_ID
    });
    bytes memory proposalData = abi.encodeWithSelector(
        bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnZora)),
        zpd
    );
    PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
      maxExecutableTime: uint40(block.timestamp + 10000 hours),
      nonce: NONCE,
      proposalData: proposalData
    });

    uint256 proposalId = party.propose(proposal);
    console.log('created proposal');
    console.log(proposalId);
    vm.stopBroadcast();
  }
}