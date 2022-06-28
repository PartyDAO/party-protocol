// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import '../contracts/tokens/IERC721.sol';
import "../contracts/party/PartyFactory.sol";
import "../contracts/party/PartyGovernance.sol";
import "../contracts/proposals/ListOnOpenSeaportProposal.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";

contract RinkebySeaportProposal is Test {

  address constant PARTY_ADDRESS = 0x7eb6EeC1Ee31eD875568314e86EB901b5FD0939E; // REPLACE_ME
  address constant NFT_CONTRACT_ADDRESS = 0x1DD9b99ce89cC088E20951b6C0F5C9c1AFdfb1c5; // REPLACE_ME
  uint256 constant NFT_TOKEN_ID = 2; // REPLACE_ME
  uint256 constant NONCE = 1;

  uint256 constant LIST_PRICE = 0.0975 ether;
  uint256 constant FEE_PRICE = 0.0025 ether;
  uint40 constant DURATION = 24 hours;
  address payable constant OS_FEE_RECIP = payable(0x8De9C5A032463C561423387a9648c5C7BCC5BC90);

  function run() public {
    vm.startBroadcast();
   
    PartyGovernance party = PartyGovernance(PARTY_ADDRESS);

    IERC721 nft = IERC721(NFT_CONTRACT_ADDRESS);
    if (nft.ownerOf(NFT_TOKEN_ID) != address(party)) {
      revert("party doesnt have NFT");
    }

    uint256[] memory fees = new uint256[](1);
    fees[0] = FEE_PRICE;

    address payable[] memory feeRecipients = new address payable[](1);
    feeRecipients[0] = OS_FEE_RECIP;

    ListOnOpenSeaportProposal.OpenSeaportProposalData memory opd = ListOnOpenSeaportProposal.OpenSeaportProposalData({
      listPrice: LIST_PRICE,
      duration: DURATION,
      token: nft,
      tokenId: NFT_TOKEN_ID,
      fees: fees,
      feeRecipients: feeRecipients
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

    vm.stopBroadcast();
  }
}