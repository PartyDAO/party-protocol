// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import '../contracts/tokens/IERC721.sol';
import "../contracts/party/PartyFactory.sol";
import "../contracts/proposals/ListOnZoraProposal.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";

interface MintableNFT is IERC721 {
  function mint(string memory text) external;
  function lastTokenId() external returns (uint256); 
}

contract RinkebyPartify is Test {
  bool createZora = true;
  bool createOs = false;
  address constant PARTY_FACTORY_ADDRESS = 0x7c1A6A24b2436A8a088C6509671d4B588520CE62;
  address constant MINTABLE_NFT_ADDRESS = 0x1DD9b99ce89cC088E20951b6C0F5C9c1AFdfb1c5;

  address constant HOST_1 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD;
  address constant HOST_2 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;
  address constant RECIP_1 = 0xC282eC605DBe8C593380B68e18Fea69c4c628B36;
  address constant RECIP_2 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD; 
  address constant RECIP_3 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;
  address constant RECIP_4 = 0x470084c5F2a31A35D44723bFD0A32f529CE21E00;
  address constant RECIP_5 = 0xcAAAE655D431bdDB3F2f20bd31BC629928131582;
  address constant RECIP_6 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD;
  address constant RECIP_7 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;
  address constant RECIP_8 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;

  uint40 constant VOTE_DURATION = 200 hours;
  uint40 constant EXECUTION_DELAY = 5 minutes;
  uint16 constant PASS_THRESHOLD_BPS = 5100;

  uint256 constant LIST_PRICE = 0.0975 ether;
  uint256 constant FEE_PRICE = 0.0025 ether;
  uint40 constant DURATION = 24 hours;
  address payable constant OS_FEE_RECIP = payable(0x8De9C5A032463C561423387a9648c5C7BCC5BC90);

  function run() public {
    vm.startBroadcast();

    MintableNFT nftContract = MintableNFT(MINTABLE_NFT_ADDRESS);
    nftContract.mint("hallo");
    uint256 nftTokenId = nftContract.lastTokenId();

    if (nftContract.ownerOf(nftTokenId) != tx.origin) {
      revert("dont own nft");
    }

    PartyFactory partyFactory = PartyFactory(PARTY_FACTORY_ADDRESS);

    address[] memory hosts = new address[](2);
    hosts[0] = HOST_1;
    hosts[1] = HOST_2;

    IERC721[] memory preciousTokens = new IERC721[](1);
    preciousTokens[0] = IERC721(MINTABLE_NFT_ADDRESS);

    uint256[] memory preciousTokenIds = new uint256[](1);
    preciousTokenIds[0] = nftTokenId;

    PartyGovernance.GovernanceOpts memory govOpts = PartyGovernance.GovernanceOpts({
      hosts: hosts,
      voteDuration: VOTE_DURATION,
      executionDelay: EXECUTION_DELAY,
      passThresholdBps: PASS_THRESHOLD_BPS,
      totalVotingPower: 100e18
    });
    Party.PartyOptions memory opts = Party.PartyOptions({
      governance: govOpts,
      name: 'First Party',
      symbol: 'FIRST'
    });
    console.log('creating party...');
    Party party = partyFactory.createParty(tx.origin, opts, preciousTokens, preciousTokenIds);
    console.log('created party');
    console.log(address(party));

    // send NFT
    console.log('sending nft....');
    nftContract.safeTransferFrom(tx.origin, address(party), nftTokenId);
    console.log('sent NFT');

    console.log('minting governance NFTs....');
    // mint governance NFTs
    partyFactory.mint(party, RECIP_1, 5e18, RECIP_1);
    partyFactory.mint(party, RECIP_2, 5e18, RECIP_2);
    partyFactory.mint(party, RECIP_3, 1e18, RECIP_3);
    partyFactory.mint(party, RECIP_4, 15e18, RECIP_4);
    partyFactory.mint(party, RECIP_5, 20e18, RECIP_5);
    partyFactory.mint(party, RECIP_6, 35e18, RECIP_6);
    partyFactory.mint(party, RECIP_7, 5e18, RECIP_7);
    partyFactory.mint(party, RECIP_8, 14e18, RECIP_8);
    console.log('minted governance NFTs');


    address partyAddress = address(party);
    PartyGovernance partyGov = PartyGovernance(partyAddress);
    IERC721 nft = IERC721(MINTABLE_NFT_ADDRESS);
    if (nft.ownerOf(nftTokenId) != address(partyGov)) {
      revert("party doesnt have NFT");
    }



    if (createZora) {
      // ---- create zora proposal -----
      ListOnZoraProposal.ZoraProposalData memory zpd = ListOnZoraProposal.ZoraProposalData({
        listPrice: 4.269 ether,
        duration: 48 hours,
        timeout: 48 hours,
        token: nft,
        tokenId: nftTokenId
      });
      bytes memory proposalData = abi.encodeWithSelector(
          bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnZora)),
          zpd
      );
      PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
        maxExecutableTime: uint40(block.timestamp + 10000 hours),
        nonce: 1,
        proposalData: proposalData
      });

      uint256 proposalId = partyGov.propose(proposal);
      console.log('created zora proposal');
      console.log(proposalId);
    }

    if (createOs) {
      uint256[] memory fees = new uint256[](1);
      fees[0] = FEE_PRICE;

      address payable[] memory feeRecipients = new address payable[](1);
      feeRecipients[0] = OS_FEE_RECIP;

      ListOnSeaportProposal.SeaportProposalData memory opd = ListOnOpenSeaportProposal.OpenSeaportProposalData({
        listPrice: LIST_PRICE,
        duration: DURATION,
        token: IERC721(MINTABLE_NFT_ADDRESS),
        tokenId: nftTokenId,
        fees: fees,
        feeRecipients: feeRecipients
      });
      bytes memory proposalData = abi.encodeWithSelector(
          bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnOpenSea)),
          opd
      );
      PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
        maxExecutableTime: uint40(block.timestamp + 10000 hours),
        nonce: 1,
        proposalData: proposalData
      });
      uint256 proposalId = partyGov.propose(proposal);
      console.log('created openseaport proposal');
      console.log(proposalId);
    }

    console.log('party created');
    console.log(address(partyGov));

    vm.stopBroadcast();
  }
}
