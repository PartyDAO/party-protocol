// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/ERC721Renderer.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";
import "../TestUtils.sol";

contract PartyGovernanceNFTTest is Test, TestUtils {
    PartyFactory partyFactory;
    DummySimpleProposalEngineImpl eng;
    ERC721Renderer nftRenderer;
    PartyParticipant john;
    PartyParticipant danny;
    PartyParticipant steve;
    PartyParticipant nicholas;
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

        nftRenderer = new ERC721Renderer(globals);
        globalsAdmin.setGovernanceNftRendererAddress(address(nftRenderer));

        partyFactory = new PartyFactory(globals);

        john = new PartyParticipant();
        danny = new PartyParticipant();
        steve = new PartyParticipant();
        nicholas = new PartyParticipant();
        partyAdmin = new PartyAdmin(partyFactory);

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }

    function testTokenURI() public {
        // Create party
        (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
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

        // console.log(party.name());

        console.log(party.tokenURI(1));
        
        assertEq(true, true);
    }
}