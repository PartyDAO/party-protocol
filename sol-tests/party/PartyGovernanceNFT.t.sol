// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/PartyGovernanceNFTRenderer.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";
import "../TestUtils.sol";

contract PartyGovernanceNFTTest is Test, TestUtils {
    PartyFactory partyFactory;
    DummySimpleProposalEngineImpl eng;
    PartyGovernanceNFTRenderer nftRenderer;
    PartyParticipant john;
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
        partyAdmin = new PartyAdmin(partyFactory);

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }

    function testTokenURI() public {
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

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 49, address(john));

        // Uncomment for testing rendering
        // console.log(party.tokenURI(1));

        string memory tokenURI = party.tokenURI(1);
        assertTrue(bytes(tokenURI).length > 0);
    }

    function testTokenURIWithNotMintedTokenId() public {
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

        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernanceNFTRenderer.InvalidTokenIdError.selector
        ));
        party.tokenURI(1);
    }

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

        PartyParticipant steve = new PartyParticipant();
        PartyParticipant lawrence = new PartyParticipant();
        PartyParticipant anna = new PartyParticipant();

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 30, address(john));
        partyAdmin.mintGovNft(party, address(steve), 15, address(steve));
        partyAdmin.mintGovNft(party, address(lawrence), 20, address(lawrence));
        partyAdmin.mintGovNft(party, address(anna), 35, address(anna));

        Party.NftInfo[] memory nftInfos = party.getNftInfos(0, 6);
        assertTrue(nftInfos.length == 4);
        assertTrue(nftInfos[0].intrinsicVotingPower == 30);
        assertTrue(nftInfos[1].intrinsicVotingPower == 15);
        assertTrue(nftInfos[2].intrinsicVotingPower == 20);
        assertTrue(nftInfos[3].intrinsicVotingPower == 35);
    }
}
