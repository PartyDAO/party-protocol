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
        PartyHelpers ph = new PartyHelpers(address(party));

        // test getCurrentDelegates
        address[] memory members = new address[](4);
        members[0] = address(john);
        members[1] = address(steve);
        members[2] = address(lawrence);
        members[3] = address(anna);
        address[] memory currDelegates = ph.getCurrentDelegates(members);
        assertTrue(currDelegates.length == 4);
        assertTrue(currDelegates[0] == address(john));
        assertTrue(currDelegates[1] == address(john));
        assertTrue(currDelegates[2] == address(anna));
        assertTrue(currDelegates[3] == address(lawrence));
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
        PartyHelpers ph = new PartyHelpers(address(party));

        // test getVotingPowersAt
        address[] memory voters = new address[](4);
        voters[0] = address(john);
        voters[1] = address(steve);
        voters[2] = address(lawrence);
        voters[3] = address(anna);
        uint96[] memory votingPowers = ph.getVotingPowersAt(voters, uint40(block.timestamp));
        assertTrue(votingPowers.length == 4);
        assertTrue(votingPowers[0] == 30);
        assertTrue(votingPowers[1] == 15);
        assertTrue(votingPowers[2] == 20);
        assertTrue(votingPowers[3] == 35);
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
        PartyHelpers ph = new PartyHelpers(address(party));

        // test edge startIndex = 0 and endIndex > tokenCount
        PartyHelpers.NftInfo[] memory nftInfos = ph.getNftInfos(0, 6);
        assertTrue(nftInfos.length == 4);
        assertTrue(nftInfos[0].tokenId == 1);
        assertTrue(nftInfos[0].owner == address(john));
        assertTrue(nftInfos[0].intrinsicVotingPower == 30);
        assertTrue(nftInfos[1].intrinsicVotingPower == 15);
        assertTrue(nftInfos[2].intrinsicVotingPower == 20);
        assertTrue(nftInfos[3].tokenId == 4);
        assertTrue(nftInfos[3].owner == address(anna));
        assertTrue(nftInfos[3].intrinsicVotingPower == 35);

        // test startIndex > endIndex
        PartyHelpers.NftInfo[] memory nftInfos2 = ph.getNftInfos(3, 0);
        assertTrue(nftInfos2.length == 3);

        // test expected startIndex and endIndex
        PartyHelpers.NftInfo[] memory nftInfos3 = ph.getNftInfos(1, 4);
        assertTrue(nftInfos3.length == 4);
    }
}
