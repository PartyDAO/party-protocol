// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/party/PartyHelpers.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/PartyGovernanceNFTRenderer.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";
import "../TestUtils.sol";

contract PartyHelpersTest is Test, TestUtils {
    PartyFactory partyFactory;
    DummySimpleProposalEngineImpl eng;
    PartyGovernanceNFTRenderer nftRenderer;
    PartyParticipant john;
    PartyParticipant steve;
    PartyParticipant lawrence;
    PartyParticipant anna;
    DummyERC721 toadz;
    PartyAdmin partyAdmin;
    address globalDaoWalletAddress = address(420);

    function setUp() public {
        GlobalsAdmin globalsAdmin = new GlobalsAdmin();
        Globals globals = globalsAdmin.globals();
        Party partyImpl = new Party(globals);
        globalsAdmin.setPartyImpl(address(partyImpl));
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        eng = new DummySimpleProposalEngineImpl();
        globalsAdmin.setProposalEng(address(eng));

        nftRenderer = new PartyGovernanceNFTRenderer(globals);
        globalsAdmin.setGovernanceNftRendererAddress(address(nftRenderer));

        partyFactory = new PartyFactory(globals);

        john = new PartyParticipant();
        steve = new PartyParticipant();
        lawrence = new PartyParticipant();
        anna = new PartyParticipant();

        partyAdmin = new PartyAdmin(partyFactory);

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }

    ///////////////////////////////////
    // PartyGovernance helpers tests //
    ///////////////////////////////////
    function testGetCurrDelegates() public {
        // Create party
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Mint first governance NFTs
        partyAdmin.mintGovNft(party, address(john), 30, address(john));
        partyAdmin.mintGovNft(party, address(steve), 15, address(john));
        partyAdmin.mintGovNft(party, address(lawrence), 20, address(anna));
        partyAdmin.mintGovNft(party, address(anna), 35, address(lawrence));

        // create party helpers
        PartyHelpers ph = new PartyHelpers();

        // test getCurrentDelegates
        address[] memory members = new address[](4);
        members[0] = address(john);
        members[1] = address(steve);
        members[2] = address(lawrence);
        members[3] = address(anna);
        PartyHelpers.MemberAndDelegate[] memory membersAndDelegates = ph.getCurrentDelegates(address(party), members);
        assertTrue(membersAndDelegates.length == 4);
        assertTrue(membersAndDelegates[0].member == address(john));
        assertTrue(membersAndDelegates[0].delegate == address(john));
        assertTrue(membersAndDelegates[1].member == address(steve));
        assertTrue(membersAndDelegates[1].delegate == address(john));
        assertTrue(membersAndDelegates[2].member == address(lawrence));
        assertTrue(membersAndDelegates[2].delegate == address(anna));
        assertTrue(membersAndDelegates[3].member == address(anna));
        assertTrue(membersAndDelegates[3].delegate == address(lawrence));
    }

    function testGetVotingPowersAt() public {
        // Create party
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Mint first governance NFTs
        partyAdmin.mintGovNft(party, address(john), 30, address(john));
        partyAdmin.mintGovNft(party, address(steve), 15, address(steve));
        partyAdmin.mintGovNft(party, address(lawrence), 20, address(lawrence));
        partyAdmin.mintGovNft(party, address(anna), 35, address(anna));

        // create party helpers
        PartyHelpers ph = new PartyHelpers();

        // test getVotingPowersAt
        address[] memory voters = new address[](4);
        voters[0] = address(john);
        voters[1] = address(steve);
        voters[2] = address(lawrence);
        voters[3] = address(anna);
        PartyHelpers.MemberAndVotingPower[] memory membersAndVotingPowers = ph.getVotingPowersAt(address(party), voters, uint40(block.timestamp));
        assertTrue(membersAndVotingPowers.length == 4);
        assertTrue(membersAndVotingPowers[0].member == address(john));
        assertTrue(membersAndVotingPowers[0].votingPower == 30);
        assertTrue(membersAndVotingPowers[1].member == address(steve));
        assertTrue(membersAndVotingPowers[1].votingPower == 15);
        assertTrue(membersAndVotingPowers[2].member == address(lawrence));
        assertTrue(membersAndVotingPowers[2].votingPower == 20);
        assertTrue(membersAndVotingPowers[3].member == address(anna));
        assertTrue(membersAndVotingPowers[3].votingPower == 35);
    }

    //////////////////////////////////////
    // PartyGovernanceNFT helpers tests //
    //////////////////////////////////////
    function testGetNftInfos() public {
        // Create party
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Mint first governance NFTs
        partyAdmin.mintGovNft(party, address(john), 30, address(john));
        partyAdmin.mintGovNft(party, address(steve), 15, address(steve));
        partyAdmin.mintGovNft(party, address(lawrence), 20, address(lawrence));
        partyAdmin.mintGovNft(party, address(anna), 35, address(anna));

        // create party helpers
        PartyHelpers ph = new PartyHelpers();

        // test endIndex > tokenCount
        PartyHelpers.NftInfo[] memory nftInfos = ph.getNftInfos(address(party), 1, 6);
        assertTrue(nftInfos.length == 4);
        assertTrue(nftInfos[0].tokenId == 1);
        assertTrue(nftInfos[0].owner == address(john));
        assertTrue(nftInfos[0].intrinsicVotingPower == 30);
        assertTrue(nftInfos[1].intrinsicVotingPower == 15);
        assertTrue(nftInfos[2].intrinsicVotingPower == 20);
        assertTrue(nftInfos[3].tokenId == 4);
        assertTrue(nftInfos[3].owner == address(anna));
        assertTrue(nftInfos[3].intrinsicVotingPower == 35);

        // test expected startIndex and endIndex
        PartyHelpers.NftInfo[] memory nftInfos2 = ph.getNftInfos(address(party), 1, 4);
        assertTrue(nftInfos2.length == 4);

        // test startIndex > 1
        PartyHelpers.NftInfo[] memory nftInfos3 = ph.getNftInfos(address(party), 2, 4);
        assertTrue(nftInfos3.length == 3);
    }
}
