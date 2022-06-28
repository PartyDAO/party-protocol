// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import '../contracts/tokens/IERC721.sol';
import "../contracts/party/PartyFactory.sol";
import "../contracts/party/PartyGovernance.sol";
import "../contracts/proposals/ListOnOpenSeaportProposal.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";

contract RinkebySeaportProposal is Test {

  address constant PARTY_ADDRESS = 0xA5C1c616968268Ed31098397ca46Be3fFB8daAE1; // REPLACE_ME
  address constant NFT_CONTRACT_ADDRESS = 0x15cBc9615CC058F6Eb9F5c584027511207C96A73; // REPLACE_ME
  uint256 constant NFT_TOKEN_ID = 421; // REPLACE_ME
  uint256 constant NONCE = 1;

  uint256 constant LIST_PRICE = 4.2 ether;
  uint40 constant DURATION = 24 hours;

  function run() public {
    // vm.startBroadcast();
   
    PartyGovernance party = PartyGovernance(PARTY_ADDRESS);

    IERC721 nft = IERC721(NFT_CONTRACT_ADDRESS);
    if (nft.ownerOf(NFT_TOKEN_ID) != address(party)) {
      revert("party doesnt have NFT");
    }

    ListOnOpenSeaportProposal.OpenSeaportProposalData memory opd = ListOnOpenSeaportProposal.OpenSeaportProposalData({
      listPrice: LIST_PRICE,
      duration: DURATION,
      token: nft,
      tokenId: NFT_TOKEN_ID
    });
    bytes memory proposalData = abi.encodeWithSelector(
        bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnOpenSea)),
        opd
    );
    PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
      maxExecutableTime: uint40(block.timestamp + 10000 hours),
      nonce: NONCE,
      proposalData: proposalData
    });

    uint256 proposalId = party.propose(proposal);
    console.log('created proposal');
    console.log(proposalId);

    // vm.stopBroadcast();
  }
}