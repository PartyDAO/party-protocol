// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/Crowdfund.sol";
import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/PartyNFTRenderer.sol";
import "../../contracts/renderers/RendererStorage.sol";
import "../../contracts/renderers/MetadataRegistry.sol";
import "../../contracts/renderers/MetadataProvider.sol";
import "../../contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC20.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";
import "../TestUtils.sol";
import { LintJSON } from "../utils/LintJSON.sol";

contract PartyGovernanceNFTTestBase is LintJSON, TestUtils {
    Party partyImpl;
    PartyFactory partyFactory;
    DummySimpleProposalEngineImpl eng;
    PartyNFTRenderer nftRenderer;
    MetadataRegistry metadataRegistry;
    MetadataProvider metadataProvider;
    RendererStorage nftRendererStorage;
    TestTokenDistributor tokenDistributor;
    Globals globals;
    PartyParticipant john;
    DummyERC721 toadz;
    PartyAdmin partyAdmin;
    address globalDaoWalletAddress = address(420);

    uint40 constant ENABLE_RAGEQUIT_PERMANENTLY = 0x6b5b567bfe;
    uint40 constant DISABLE_RAGEQUIT_PERMANENTLY = 0xab2cb21860;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {
        GlobalsAdmin globalsAdmin = new GlobalsAdmin();
        globals = globalsAdmin.globals();
        partyImpl = new Party(globals);
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        tokenDistributor = new TestTokenDistributor();
        globalsAdmin.setTokenDistributor(address(tokenDistributor));

        eng = new DummySimpleProposalEngineImpl();
        globalsAdmin.setProposalEng(address(eng));

        partyFactory = new PartyFactory(globals);

        john = new PartyParticipant();
        partyAdmin = new PartyAdmin(partyFactory);

        address[] memory registrars = new address[](0);
        metadataRegistry = new MetadataRegistry(globals, registrars);
        metadataProvider = new MetadataProvider(globals);
        globalsAdmin.setMetadataRegistry(address(metadataRegistry));

        // Upload font on-chain
        PixeldroidConsoleFont font = new PixeldroidConsoleFont();
        nftRendererStorage = new RendererStorage(address(this));
        nftRenderer = new PartyNFTRenderer(
            globals,
            nftRendererStorage,
            font,
            address(0),
            "https://party.app/party/"
        );
        globalsAdmin.setGovernanceNftRendererAddress(address(nftRenderer));
        globalsAdmin.setRendererStorage(address(nftRendererStorage));

        // Generate customization options.
        uint256 versionId = 1;
        uint256 numOfColors = uint8(type(Color).max) + 1;
        for (uint256 i; i < numOfColors; ++i) {
            // Generate customization options for all colors w/ each mode (light and dark).
            nftRendererStorage.createCustomizationPreset(
                // Preset ID 0 is reserved. It is used to indicates to party instances
                // to use the same customization preset as the crowdfund.
                i + 1,
                abi.encode(versionId, false, Color(i))
            );
            nftRendererStorage.createCustomizationPreset(
                i + 1 + numOfColors,
                abi.encode(versionId, true, Color(i))
            );
        }

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }
}

contract PartyGovernanceNFTTest is PartyGovernanceNFTTestBase {
    function testMint() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);
        assertEq(party.ownerOf(tokenId), recipient);
        assertEq(party.votingPowerByTokenId(tokenId), 10);
        assertEq(party.mintedVotingPower(), 10);
    }

    function testMint_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address notAuthority = _randomAddress();
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        vm.prank(notAuthority);
        party.mint(_randomAddress(), 1, _randomAddress());
    }

    function testMint_cannotMintBeyondTotalVotingPower() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(recipient, 101, recipient);
        assertEq(party.getVotingPowerAt(recipient, uint40(block.timestamp)), 100);
    }

    function testMint_cannotMintBeyondTotalVotingPower_twoMints() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(recipient, 99, recipient);
        assertEq(party.getVotingPowerAt(recipient, uint40(block.timestamp)), 99);
        recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(recipient, 2, recipient);
        assertEq(party.getVotingPowerAt(recipient, uint40(block.timestamp)), 1);
    }

    function testIncreaseTotalVotingPower_works() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        uint96 votingPower = 10;

        address authority = address(partyAdmin);
        vm.prank(authority);
        party.increaseTotalVotingPower(votingPower);

        assertEq(party.getGovernanceValues().totalVotingPower, 110);
    }

    function testIncreaseTotalVotingPower_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        uint96 votingPower = 10;

        address notAuthority = _randomAddress();
        vm.prank(notAuthority);
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.increaseTotalVotingPower(votingPower);
    }

    function testDecreaseTotalVotingPower_works() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        uint96 votingPower = 10;

        address authority = address(partyAdmin);
        vm.prank(authority);
        party.decreaseTotalVotingPower(votingPower);

        assertEq(party.getGovernanceValues().totalVotingPower, 90);
    }

    function testDecreaseTotalVotingPower_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        uint96 votingPower = 10;

        address notAuthority = _randomAddress();
        vm.prank(notAuthority);
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.decreaseTotalVotingPower(votingPower);
    }

    function testIncreaseVotingPower_works() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        uint40 timestampBefore = uint40(block.timestamp);
        skip(10);
        uint40 timestampAfter = uint40(block.timestamp);

        uint96 votingPower = 10;

        address authority = address(partyAdmin);
        vm.prank(authority);
        party.increaseVotingPower(tokenId, votingPower);

        assertEq(party.votingPowerByTokenId(tokenId), 20);
        assertEq(party.mintedVotingPower(), 20);
        assertEq(party.getVotingPowerAt(recipient, timestampAfter), 20);
        assertEq(party.getVotingPowerAt(recipient, timestampBefore), 10);
    }

    function testIncreaseVotingPower_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        uint96 votingPower = 10;

        address notAuthority = _randomAddress();
        vm.prank(notAuthority);
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.increaseVotingPower(tokenId, votingPower);
    }

    function testIncreaseVotingPower_cannotIncreaseBeyondTotalVotingPower() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: uint16(0),
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        uint96 votingPower = 100;

        address authority = address(partyAdmin);
        vm.prank(authority);
        party.increaseVotingPower(tokenId, votingPower);

        assertEq(party.votingPowerByTokenId(tokenId), 100);
        assertEq(party.mintedVotingPower(), 100);
        assertEq(party.getGovernanceValues().totalVotingPower, 100);
    }

    function testDecreaseVotingPower_works() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 20, recipient);

        uint40 timestampBefore = uint40(block.timestamp);
        skip(10);
        uint40 timestampAfter = uint40(block.timestamp);

        uint96 votingPower = 10;

        address authority = address(partyAdmin);
        vm.prank(authority);
        party.decreaseVotingPower(tokenId, votingPower);

        assertEq(party.votingPowerByTokenId(tokenId), 10);
        assertEq(party.mintedVotingPower(), 10);
        assertEq(party.getVotingPowerAt(recipient, timestampAfter), 10);
        assertEq(party.getVotingPowerAt(recipient, timestampBefore), 20);
    }

    function testDecreaseVotingPower_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 20, recipient);

        uint96 votingPower = 10;

        address notAuthority = _randomAddress();
        vm.prank(notAuthority);
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.decreaseVotingPower(tokenId, votingPower);
    }

    function testBurn_works() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.prank(address(partyAdmin));
        party.burn(tokenId);

        // Check token burned
        vm.expectRevert("NOT_MINTED");
        party.ownerOf(tokenId);

        assertEq(party.votingPowerByTokenId(tokenId), 0);
        assertEq(party.mintedVotingPower(), 0);
    }

    function testBurn_beforePartyStarted() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 0,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.prank(address(partyAdmin));
        party.burn(tokenId);
    }

    function testBurn_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.prank(_randomAddress());
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.burn(tokenId);
    }

    function testSetRageQuit() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        uint40 newTimestamp = uint40(block.timestamp + 1);
        vm.prank(address(this));
        party.setRageQuit(newTimestamp);
        assertEq(party.rageQuitTimestamp(), newTimestamp);
    }

    function testSetRageQuit_revertsIfNotHost() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address notHost = _randomAddress();
        vm.prank(notHost);
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.setRageQuit(0);
    }

    function testSetRageQuit_revertsIfRageQuitPermenantlyEnabled() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(ENABLE_RAGEQUIT_PERMANENTLY);

        vm.prank(address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.FixedRageQuitTimestampError.selector,
                ENABLE_RAGEQUIT_PERMANENTLY
            )
        );
        party.setRageQuit(0);
    }

    function testSetRageQuit_revertsIfRageQuitPermanentlyDisabled() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: DISABLE_RAGEQUIT_PERMANENTLY,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.FixedRageQuitTimestampError.selector,
                DISABLE_RAGEQUIT_PERMANENTLY
            )
        );
        party.setRageQuit(0);
    }

    function testSetRageQuit_cannotDisableRageQuitAfterInitializationError() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        vm.expectRevert(PartyGovernanceNFT.CannotDisableRageQuitAfterInitializationError.selector);
        party.setRageQuit(DISABLE_RAGEQUIT_PERMANENTLY);
    }

    function testRageQuit_single() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);

        // Check token burned and voting power removed.
        assertEq(party.votingPowerByTokenId(tokenId), 0);
        assertEq(party.mintedVotingPower(), 0);
        assertEq(party.getGovernanceValues().totalVotingPower, 90);

        // Check that ETH has been moved correctly.
        assertEq(payable(recipient).balance, 0.1 ether);
        assertEq(payable(address(party)).balance, 0.9 ether);

        // Checks that all tokens have been moved correctly.
        for (uint256 i; i < balances.length; ++i) {
            uint256 balance = balances[i];
            uint256 expectedRecipientBalance = balance / 10;

            // Check the balances of the recipient and the party contract.
            assertEq(tokens[i].balanceOf(address(party)), balance - expectedRecipientBalance);
            assertEq(tokens[i].balanceOf(recipient), expectedRecipientBalance);
        }
    }

    function testRageQuit_multiple() external {
        uint256 totalVotingPower = 1e18;
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: uint96(totalVotingPower),
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address[] memory members = new address[](3);
        uint256[] memory shareOfBalances = new uint256[](3);

        members[0] = _randomAddress();
        shareOfBalances[0] = 0.3e18;
        vm.prank(address(partyAdmin));
        party.mint(members[0], shareOfBalances[0], members[0]);

        members[1] = _randomAddress();
        shareOfBalances[1] = 0.2e18;
        vm.prank(address(partyAdmin));
        party.mint(members[1], shareOfBalances[1], members[1]);

        members[2] = _randomAddress();
        shareOfBalances[2] = 0.5e18;
        vm.prank(address(partyAdmin));
        party.mint(members[2], shareOfBalances[2], members[2]);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        for (uint256 i; i < members.length; ++i) {
            uint256 tokenId = i + 1;
            address member = members[i];

            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = tokenId;

            vm.prank(member);
            party.rageQuit(tokenIds, tokens, minWithdrawAmounts, member);

            // Check token burned and member voting power updated.
            assertEq(party.votingPowerByTokenId(tokenId), 0);

            // Check that ETH has been moved correctly.
            assertApproxEqRel(
                payable(member).balance,
                (shareOfBalances[i] * 1 ether) / totalVotingPower,
                1e6 // 0.0000000001%
            );

            // Checks that all tokens have been moved correctly.
            for (uint256 j; j < balances.length; ++j) {
                uint256 balance = balances[j];
                uint256 expectedRecipientBalance = (shareOfBalances[i] * balance) /
                    totalVotingPower;

                // Check the balances of the members
                assertApproxEqRel(
                    tokens[j].balanceOf(member),
                    expectedRecipientBalance,
                    1e6 // 0.0000000001%
                );
            }
        }

        // Check party balance of ETH.
        assertEq(payable(address(party)).balance, 0 ether);

        // Check the balances of all tokens in the party contract.
        for (uint256 i; i < balances.length; ++i) {
            assertEq(tokens[i].balanceOf(address(party)), 0);
        }

        // Check global voting power updated.
        assertEq(party.mintedVotingPower(), 0);
        assertEq(party.getGovernanceValues().totalVotingPower, 0);
    }

    function testRageQuit_withFee() external {
        address payable feeRecipient = payable(_randomAddress());
        uint16 feeBps = 0.1e4;

        uint256 totalVotingPower = 1e18;
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: uint96(totalVotingPower),
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: feeBps,
                feeRecipient: feeRecipient
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address member = _randomAddress();

        vm.prank(address(partyAdmin));
        party.mint(member, 1e18, member);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(ETH_ADDRESS);

        DummyERC20(address(tokens[0])).deal(address(party), 1e18);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.prank(member);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, member);

        // Check balances received by member.
        assertEq(payable(member).balance, 0.9 ether);
        assertEq(tokens[0].balanceOf(member), 0.9e18);

        // Check balances received by fee recipient.
        assertEq(payable(feeRecipient).balance, 0.1 ether);
        assertEq(tokens[0].balanceOf(address(feeRecipient)), 0.1e18);
    }

    function testRageQuit_cannotQuitAndAcceptInSameBlock() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 20, recipient);

        address delegator = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(delegator, 10, delegator);

        vm.prank(delegator);
        party.delegateVotingPower(recipient);

        skip(1);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);

        vm.prank(recipient);
        vm.expectRevert(PartyGovernance.CannotRageQuitAndAcceptError.selector);
        party.propose(
            PartyGovernance.Proposal({
                maxExecutableTime: uint40(type(uint40).max),
                cancelDelay: uint40(1 days),
                proposalData: abi.encode(0)
            }),
            0
        );
    }

    function testRageQuit_revertsIfNotOwner() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        address notOwner = _randomAddress();
        vm.prank(notOwner);
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testRageQuit_ifNotOwner_butAuthority() public {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        address authority = address(partyAdmin);
        vm.prank(authority);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testRageQuit_revertIfBelowMinWithdrawAmount() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](3);
        // Cause the last token to be below the min withdraw amount.
        minWithdrawAmounts[2] = type(uint256).max;

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.BelowMinWithdrawAmountError.selector,
                balances[2] / 10,
                type(uint256).max
            )
        );
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testRageQuit_enableRageQuit() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(ENABLE_RAGEQUIT_PERMANENTLY);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);

        // Check token burned and voting power removed.
        assertEq(party.votingPowerByTokenId(tokenId), 0);
        assertEq(party.mintedVotingPower(), 0);
        assertEq(party.getGovernanceValues().totalVotingPower, 90);

        // Check that ETH has been moved correctly.
        assertEq(payable(recipient).balance, 0.1 ether);
        assertEq(payable(address(party)).balance, 0.9 ether);

        // Checks that all tokens have been moved correctly.
        for (uint256 i; i < balances.length; ++i) {
            uint256 balance = balances[i];
            uint256 expectedRecipientBalance = balance / 10;

            // Check the balances of the recipient and the party contract.
            assertEq(tokens[i].balanceOf(address(party)), balance - expectedRecipientBalance);
            assertEq(tokens[i].balanceOf(recipient), expectedRecipientBalance);
        }
    }

    function testRageQuit_disableRageQuit() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: DISABLE_RAGEQUIT_PERMANENTLY,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.CannotRageQuitError.selector,
                DISABLE_RAGEQUIT_PERMANENTLY
            )
        );
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testRageQuit_expiredRageQuitTimestamp() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(0);

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = IERC20(address(new DummyERC20()));
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(PartyGovernanceNFT.CannotRageQuitError.selector, 0));
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testRageQuit_revertIfDuplicateTokens() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp + 1));

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 10, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](4);
        tokens[0] = IERC20(address(new DummyERC20()));
        tokens[1] = IERC20(address(new DummyERC20()));
        tokens[2] = tokens[1];
        tokens[3] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](4);

        uint96[] memory balances = new uint96[](3);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = uint96(_randomRange(10, type(uint96).max));
            DummyERC20(address(tokens[i])).deal(address(party), balances[i]);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        vm.expectRevert(PartyGovernanceNFT.InvalidTokenOrderError.selector);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testRageQuit_cannotReenter() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        vm.prank(address(this));
        party.setRageQuit(uint40(block.timestamp) + 1);

        ReenteringContract reenteringContract = new ReenteringContract(party, 1);

        // Set reentering contract as the host for exploit to allow reentering
        // contract to attempt to `setRageQuit` to get past the reentrancy
        // guard.
        vm.prank(address(this));
        party.abdicateHost(address(reenteringContract));

        vm.prank(address(partyAdmin));
        party.mint(address(reenteringContract), 50, address(reenteringContract));

        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        uint256 tokenId = party.mint(recipient, 50, recipient);

        vm.deal(address(party), 1 ether);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(reenteringContract));
        tokens[1] = IERC20(ETH_ADDRESS);

        // Sort the addresses from lowest to highest.
        for (uint256 i; i < tokens.length; ++i) {
            for (uint256 j = 0; j < tokens.length - i - 1; j++) {
                if (address(tokens[j]) > address(tokens[j + 1])) {
                    IERC20 temp = tokens[j];
                    tokens[j] = tokens[j + 1];
                    tokens[j + 1] = temp;
                }
            }
        }

        uint256[] memory minWithdrawAmounts = new uint256[](2);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(recipient);
        // Should revert caused by `CannotRageQuitError(0)`
        vm.expectRevert(
            abi.encodeWithSelector(
                LibERC20Compat.TokenTransferFailedError.selector,
                IERC20(address(reenteringContract)),
                recipient,
                668
            )
        );
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
    }

    function testAbdicate() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        assertTrue(party.isAuthority(address(partyAdmin)));
        vm.prank(address(partyAdmin));
        party.abdicateAuthority();
        assertFalse(party.isAuthority(address(partyAdmin)));
    }

    function testAbdicate_onlyAuthority() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address notAuthority = _randomAddress();
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        vm.prank(notAuthority);
        party.abdicateAuthority();
    }

    function test_supportsInterface() external {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        assertTrue(party.supportsInterface(0x01ffc9a7)); // EIP165
        assertTrue(party.supportsInterface(0x2a55205a)); // ERC2981
        assertTrue(party.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(party.supportsInterface(0x150b7a02)); // ERC721Receiver
        assertTrue(party.supportsInterface(0x4e2312e0)); // ERC1155Receiver
    }

    function testGenerateSVG_works() public {
        PartyGovernance.ProposalStatus[4] memory proposalStatuses = [
            PartyGovernance.ProposalStatus.Voting,
            PartyGovernance.ProposalStatus.Defeated,
            PartyGovernance.ProposalStatus.Passed,
            PartyGovernance.ProposalStatus.Invalid // Should not be rendered.
        ];

        string memory svg = nftRenderer.generateSVG(
            "Test",
            "10.32",
            proposalStatuses,
            3,
            420,
            Color.CYAN,
            true
        );

        // Uncomment for testing rendering:
        // console.log(svg);

        assertTrue(bytes(svg).length > 0);
    }

    function testTokenURI_works() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option
        party.useCustomizationPreset(16); // Should make card red w/ dark mode.

        // Create proposals
        party.createMockProposal(PartyGovernance.ProposalStatus.Complete);
        party.createMockProposal(PartyGovernance.ProposalStatus.Voting);
        party.createMockProposal(PartyGovernance.ProposalStatus.Ready);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set voting power percentage
        party.setVotingPowerPercentage(tokenId, 0.42069e18);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    // Test rendering using a preset ID 0, which is reserved to indicate to
    // parties to use the same preset as the crowdfund that created it (or of
    // whatever `authority()` chose if created outside the conventional flow).
    function testTokenURI_usingReservedPresetId() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option.
        nftRendererStorage.useCustomizationPreset(5); // Should make card purple w/ light mode.

        // Setting to preset ID 0 should cause `tokenURI()` to use the
        // customization option of the `authority()` (which for this test is
        // the caller).
        party.useCustomizationPreset(0);

        // Create proposals
        party.createMockProposal(PartyGovernance.ProposalStatus.Complete);
        party.createMockProposal(PartyGovernance.ProposalStatus.Voting);
        party.createMockProposal(PartyGovernance.ProposalStatus.Ready);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set voting power percentage
        party.setVotingPowerPercentage(tokenId, 0.42069e18);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testTokenURI_nonexistentPresetId() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option
        party.useCustomizationPreset(999); // Should fallback to default card since doesn't exist.

        // Create proposals
        party.createMockProposal(PartyGovernance.ProposalStatus.Complete);
        party.createMockProposal(PartyGovernance.ProposalStatus.Voting);
        party.createMockProposal(PartyGovernance.ProposalStatus.Ready);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set voting power percentage
        party.setVotingPowerPercentage(tokenId, 0.42069e18);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testTokenURI_customMetadata() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set custom metadata
        PartyNFTRenderer.Metadata memory metadata = PartyNFTRenderer.Metadata({
            name: "CUSTOM_NAME",
            description: "CUSTOM_DESCRIPTION",
            externalURL: "CUSTOM_EXTERNAL_URL",
            image: "CUSTOM_IMAGE",
            banner: "CUSTOM_BANNER",
            animationURL: "CUSTOM_ANIMATION_URL",
            collectionName: "CUSTOM_COLLECTION_NAME",
            collectionDescription: "CUSTOM_COLLECTION_DESCRIPTION",
            collectionExternalURL: "CUSTOM_COLLECTION_EXTERNAL_URL",
            royaltyReceiver: _randomAddress(),
            royaltyAmount: _randomUint256(),
            renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
        });

        vm.startPrank(address(party));
        metadataProvider.setMetadata(address(party), abi.encode(metadata));
        metadataRegistry.setProvider(address(party), metadataProvider);
        vm.stopPrank();

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testContractURI() external {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option
        party.useCustomizationPreset(1);

        string memory contractURI = party.contractURI();

        _lintEncodedJSON(contractURI);

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function testContractURI_customMetadata() external {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set custom metadata
        PartyNFTRenderer.Metadata memory metadata = PartyNFTRenderer.Metadata({
            name: "CUSTOM_NAME",
            description: "CUSTOM_DESCRIPTION",
            externalURL: "CUSTOM_EXTERNAL_URL",
            image: "CUSTOM_IMAGE",
            banner: "CUSTOM_BANNER",
            animationURL: "CUSTOM_ANIMATION_URL",
            collectionName: "CUSTOM_COLLECTION_NAME",
            collectionDescription: "CUSTOM_COLLECTION_DESCRIPTION",
            collectionExternalURL: "CUSTOM_COLLECTION_EXTERNAL_URL",
            royaltyReceiver: _randomAddress(),
            royaltyAmount: _randomUint256(),
            renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
        });

        vm.startPrank(address(party));
        metadataProvider.setMetadata(address(party), abi.encode(metadata));
        metadataRegistry.setProvider(address(party), metadataProvider);
        vm.stopPrank();

        string memory contractURI = party.contractURI();

        _lintEncodedJSON(contractURI);

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function testRoyaltyInfo() external {
        // Create party
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        (address receiver, uint256 royaltyAmount) = party.royaltyInfo(0, 0);
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function testRoyaltyInfo_withCustomMetadata() external {
        // Create party
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Set custom metadata
        PartyNFTRenderer.Metadata memory metadata = PartyNFTRenderer.Metadata({
            name: "CUSTOM_NAME",
            description: "CUSTOM_DESCRIPTION",
            externalURL: "CUSTOM_EXTERNAL_URL",
            image: "CUSTOM_IMAGE",
            banner: "CUSTOM_BANNER",
            animationURL: "CUSTOM_ANIMATION_URL",
            collectionName: "CUSTOM_COLLECTION_NAME",
            collectionDescription: "CUSTOM_COLLECTION_DESCRIPTION",
            collectionExternalURL: "CUSTOM_COLLECTION_EXTERNAL_URL",
            royaltyReceiver: _randomAddress(),
            royaltyAmount: _randomUint256(),
            renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
        });

        vm.startPrank(address(party));
        metadataProvider.setMetadata(address(party), abi.encode(metadata));
        metadataRegistry.setProvider(address(party), metadataProvider);
        vm.stopPrank();

        (address receiver, uint256 royaltyAmount) = party.royaltyInfo(0, 0);
        assertEq(receiver, metadata.royaltyReceiver);
        assertEq(royaltyAmount, metadata.royaltyAmount);
    }

    function _createMockProposal(DummyParty party) private {
        PartyGovernance.ProposalStatus status = PartyGovernance.ProposalStatus(
            _randomRange(1, uint8(type(PartyGovernance.ProposalStatus).max))
        );

        party.createMockProposal(status);
    }
}

contract DummyCrowdfund {
    uint256 public totalContributions;
    bytes32 public governanceOptsHash;

    function setGovernanceOptsHash(Crowdfund.FixedGovernanceOpts memory opts) external {
        governanceOptsHash = _hashFixedGovernanceOpts(opts);
    }
}

contract DummyParty is ReadOnlyDelegateCall {
    Globals immutable GLOBALS;

    constructor(address globals, string memory _name) {
        name = _name;
        GLOBALS = Globals(globals);
        _governanceValues.totalVotingPower = 1e18;
    }

    bool public emergencyExecuteDisabled;
    uint16 public feeBps;
    address payable public feeRecipient;
    bytes32 public preciousListHash;
    uint256 public lastProposalId;
    mapping(address => bool) public isHost;
    mapping(address => address) public delegationsByVoter;
    PartyGovernance.GovernanceValues private _governanceValues;
    mapping(uint256 => PartyGovernance.ProposalState) private _proposalStateByProposalId;
    mapping(address => PartyGovernance.VotingPowerSnapshot[]) private _votingPowerSnapshotsByVoter;
    string public name;
    string public symbol;
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    address public authority;
    uint256 public tokenCount;
    mapping(uint256 => uint256) public votingPowerByTokenId;

    mapping(uint256 => PartyGovernance.ProposalStatus) _proposalStatuses;
    uint256 votingPowerPercentage; // 1e18 == 100%

    function useCustomizationPreset(uint256 customizationPresetId) external {
        if (customizationPresetId != 0) {
            RendererStorage(GLOBALS.getAddress(LibGlobals.GLOBAL_RENDERER_STORAGE))
                .useCustomizationPreset(customizationPresetId);
        } else {
            authority = msg.sender;
        }
    }

    function tokenURI(uint256) public view returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    function contractURI() public view returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    function mint(uint256 tokenId) external {
        _balanceOf[msg.sender]++;
        ownerOf[tokenId] = msg.sender;
    }

    function createMockProposal(PartyGovernance.ProposalStatus status) external {
        _proposalStatuses[++lastProposalId] = status;
    }

    function getProposalStateInfo(
        uint256 proposalId
    )
        external
        view
        returns (
            PartyGovernance.ProposalStatus status,
            PartyGovernance.ProposalStateValues memory values
        )
    {
        status = _proposalStatuses[proposalId];
        values;
    }

    function getGovernanceValues()
        external
        view
        returns (PartyGovernance.GovernanceValues memory gv)
    {
        return _governanceValues;
    }

    function setTokenCount(uint256 count) external {
        tokenCount = count;
    }

    function setVotingPowerPercentage(uint256 tokenId, uint256 votingPower) external {
        votingPowerByTokenId[tokenId] = votingPower;
    }

    function _delegateToRenderer() private view {
        _readOnlyDelegateCall(
            // Instance of IERC721Renderer.
            GLOBALS.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL),
            msg.data
        );
        assert(false); // Will not be reached.
    }
}

contract PartyGovernanceNFTForkedTest is PartyGovernanceNFTTestBase {
    function testTokenURI_withFixedCrowdfundType() public onlyForked {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Setup party as fixed membership mint party
        party.setTokenCount(100);
        party.mint(33);
        party.setVotingPowerPercentage(33, 0.1e18);
        party.mint(66);
        party.setVotingPowerPercentage(66, 0.1e18);
        party.mint(99);
        party.setVotingPowerPercentage(99, 0.1e18);

        // Get token URI
        string memory tokenURI = party.tokenURI(33);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }
}

contract TestTokenDistributor {
    mapping(Party => uint256) public lastDistributionIdPerParty;
    bool private _hasClaimed;

    function setHasClaimed(address party, bool hasClaimed) external {
        lastDistributionIdPerParty[Party(payable(party))] = 1;
        _hasClaimed = hasClaimed;
    }

    function hasPartyTokenIdClaimed(Party, uint256, uint256) external view returns (bool) {
        return _hasClaimed;
    }
}

contract ReenteringContract is ERC721Receiver {
    Party party;
    uint256 tokenId;

    constructor(Party _party, uint256 _tokenId) {
        party = _party;
        tokenId = _tokenId;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1337;
    }

    function transfer(address, uint256) external returns (bool) {
        // Attempt to get past reentrancy guard.
        party.setRageQuit(type(uint40).max);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        uint256[] memory minWithdrawAmounts = new uint256[](1);
        party.rageQuit(tokenIds, tokens, minWithdrawAmounts, address(this));

        return true;
    }
}
