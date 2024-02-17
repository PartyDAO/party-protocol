// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import { Party } from "../../contracts/party/Party.sol";
import { EZPartyBuilder } from "../../contracts/utils/EZPartyBuilder.sol";
import { BondingCurveAuthority } from "../../contracts/authorities/BondingCurveAuthority.sol";
import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { PartyNFTRenderer } from "contracts/renderers/PartyNFTRenderer.sol";
import { MetadataProvider } from "contracts/renderers/MetadataProvider.sol";

contract EZPartyBuilderTest is SetupPartyHelper {
    event EZPartyCreated(Party indexed party, address host, address[] initialMembers);

    EZPartyBuilder builder;
    BondingCurveAuthority bondingCurveAuthority;
    MetadataProvider metadataProvider;

    uint16 TREASURY_FEE_BPS = 0.1e4; // 10%
    uint16 PARTY_DAO_FEE_BPS = 0.025e4; // 2.5%
    uint16 CREATOR_FEE_BPS = 0.025e4; // 2.5%

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();

        bondingCurveAuthority = new BondingCurveAuthority(
            globalDaoWalletAddress,
            PARTY_DAO_FEE_BPS,
            TREASURY_FEE_BPS,
            CREATOR_FEE_BPS
        );
        metadataProvider = new MetadataProvider(globals);
        builder = new EZPartyBuilder(
            globalDaoWalletAddress,
            bondingCurveAuthority,
            partyFactory,
            partyImpl,
            metadataProvider
        );

        vm.deal(address(this), 100 ether);
    }

    function test_createPartyAndDistributeMemberships_works() public {
        address host = _randomAddress();

        address[] memory initialMembers = new address[](3);
        initialMembers[0] = _randomAddress();
        initialMembers[1] = _randomAddress();
        initialMembers[2] = _randomAddress();

        string memory partyName = "John John John";
        string memory partySymbol = "JJJ";
        string memory imageUri = "www.johnjohnjohn.com";

        uint256 initialPrice = bondingCurveAuthority.getPriceToBuy(
            0,
            4,
            50_000,
            uint80(0.001 ether),
            false
        );

        vm.expectEmit(true, true, true, true);
        emit EZPartyCreated(
            Party(payable(computeCreateAddress(address(partyFactory), 2))),
            host,
            initialMembers
        );
        Party party = builder.createPartyAndDistributeMemberships{ value: initialPrice }(
            host,
            initialMembers,
            partyName,
            partySymbol,
            imageUri
        );

        // Check host has already created a party
        assertEq(builder.hasAlreadyCreatedParty(host), true);

        // Check each member received a card
        assertEq(party.ownerOf(1), host);
        assertEq(party.ownerOf(2), initialMembers[0]);
        assertEq(party.ownerOf(3), initialMembers[1]);
        assertEq(party.ownerOf(4), initialMembers[2]);

        // Check custom metadata was set
        assertEq(party.name(), partyName);
        assertEq(party.symbol(), partySymbol);
        PartyNFTRenderer.Metadata memory metadata = abi.decode(
            metadataProvider.getMetadata(address(party), 0),
            (PartyNFTRenderer.Metadata)
        );
        assertEq(metadata.name, partyName);
        assertEq(metadata.collectionName, partyName);
        assertEq(metadata.image, imageUri);
        assertTrue(metadata.renderingMethod == PartyNFTRenderer.RenderingMethod.FixedCrowdfund);
    }

    function test_createPartyAndDistributeMemberships_revertsIfHostAlreadyCreatedParty() public {
        address host = _randomAddress();

        address[] memory initialMembers = new address[](3);
        initialMembers[0] = _randomAddress();
        initialMembers[1] = _randomAddress();
        initialMembers[2] = _randomAddress();

        string memory partyName = "John John John";
        string memory partySymbol = "JJJ";
        string memory imageUri = "www.johnjohnjohn.com";

        uint256 initialPrice = bondingCurveAuthority.getPriceToBuy(
            0,
            4,
            50_000,
            uint80(0.001 ether),
            true
        );

        builder.createPartyAndDistributeMemberships{ value: initialPrice }(
            host,
            initialMembers,
            partyName,
            partySymbol,
            imageUri
        );

        vm.expectRevert(abi.encodeWithSelector(EZPartyBuilder.PartyAlreadyCreated.selector));
        builder.createPartyAndDistributeMemberships{ value: initialPrice }(
            host,
            initialMembers,
            partyName,
            partySymbol,
            imageUri
        );
    }

    receive() external payable {}
}
