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

    constructor() {
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

    function testMint() external {
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
        vm.prank(address(partyAdmin));
        party.mint(_randomAddress(), 1, _randomAddress());
    }

    function testMint_onlyMinter() external {
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
        address notAuthority = _randomAddress();
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernanceNFT.OnlyMintAuthorityError.selector,
            notAuthority,
            address(partyAdmin)
        ));
        vm.prank(notAuthority);
        party.mint(_randomAddress(), 1, _randomAddress());
    }

    function testAbdicate() external {
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
        assertEq(party.mintAuthority(), address(partyAdmin));
        vm.prank(address(partyAdmin));
        party.abdicate();
        assertEq(party.mintAuthority(), address(0));
    }

    function testAbdicate_onlyMinter() external {
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
        address notAuthority = _randomAddress();
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernanceNFT.OnlyMintAuthorityError.selector,
            notAuthority,
            address(partyAdmin)
        ));
        vm.prank(notAuthority);
        party.abdicate();
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

        string memory tokenURI = party.tokenURI(1);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

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

    function testContractURI() external {
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

        string memory contractURI = party.contractURI();

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function testRoyaltyInfo() external {
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

        (address receiver, uint256 royaltyAmount) = party.royaltyInfo(0, 0);
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }
}
