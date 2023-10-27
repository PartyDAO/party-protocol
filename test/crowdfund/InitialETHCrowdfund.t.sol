// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import "../../contracts/crowdfund/InitialETHCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/party/PartyFactory.sol";
import "../../contracts/tokens/ERC721Receiver.sol";
import "../../contracts/renderers/PartyNFTRenderer.sol";
import "../../contracts/renderers/MetadataRegistry.sol";
import "../../contracts/renderers/RendererStorage.sol";
import "../../contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "../../contracts/distribution/TokenDistributor.sol";
import "../../contracts/gatekeepers/AllowListGateKeeper.sol";

import "../TestUtils.sol";
import { LintJSON } from "../utils/LintJSON.sol";

contract InitialETHCrowdfundTestBase is LintJSON, TestUtils, ERC721Receiver {
    using Clones for address;

    event Contributed(
        address indexed sender,
        address indexed contributor,
        uint256 amount,
        address delegate
    );
    event Refunded(address indexed contributor, uint256 indexed tokenId, uint256 amount);
    event PartyDelegateUpdated(address indexed owner, address indexed delegate);

    InitialETHCrowdfund initialETHCrowdfundImpl;
    Globals globals;
    Party partyImpl;
    PartyFactory partyFactory;

    PartyNFTRenderer nftRenderer;
    RendererStorage nftRendererStorage;
    TokenDistributor tokenDistributor;

    InitialETHCrowdfund.ETHPartyOptions partyOpts;
    InitialETHCrowdfund.InitialETHCrowdfundOptions crowdfundOpts;

    constructor() {
        globals = new Globals(address(this));
        partyImpl = new Party(globals);
        partyFactory = new PartyFactory(globals);

        initialETHCrowdfundImpl = new InitialETHCrowdfund(globals);

        MetadataRegistry metadataRegistry = new MetadataRegistry(globals, new address[](0));

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
        tokenDistributor = new TokenDistributor(globals, 0);

        globals.setAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL, address(nftRenderer));
        globals.setAddress(LibGlobals.GLOBAL_RENDERER_STORAGE, address(nftRendererStorage));
        globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor));
        globals.setAddress(LibGlobals.GLOBAL_METADATA_REGISTRY, address(metadataRegistry));

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
    }

    struct CreateCrowdfundArgs {
        uint96 initialContribution;
        address payable initialContributor;
        address initialDelegate;
        uint96 minContributions;
        uint96 maxContributions;
        bool disableContributingForExistingCard;
        uint96 minTotalContributions;
        uint96 maxTotalContributions;
        uint40 duration;
        uint16 exchangeRateBps;
        uint16 fundingSplitBps;
        address payable fundingSplitRecipient;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    function _createCrowdfund(
        CreateCrowdfundArgs memory args,
        bool initialize
    ) internal returns (InitialETHCrowdfund crowdfund) {
        crowdfundOpts.initialContributor = args.initialContributor;
        crowdfundOpts.initialDelegate = args.initialDelegate;
        crowdfundOpts.minContribution = args.minContributions;
        crowdfundOpts.maxContribution = args.maxContributions;
        crowdfundOpts.disableContributingForExistingCard = args.disableContributingForExistingCard;
        crowdfundOpts.minTotalContributions = args.minTotalContributions;
        crowdfundOpts.maxTotalContributions = args.maxTotalContributions;
        crowdfundOpts.duration = args.duration;
        crowdfundOpts.exchangeRateBps = args.exchangeRateBps;
        crowdfundOpts.fundingSplitBps = args.fundingSplitBps;
        crowdfundOpts.fundingSplitRecipient = args.fundingSplitRecipient;
        crowdfundOpts.gateKeeper = args.gateKeeper;
        crowdfundOpts.gateKeeperId = args.gateKeeperId;

        partyOpts.name = "Test Party";
        partyOpts.symbol = "TEST";
        partyOpts.governanceOpts.partyImpl = partyImpl;
        partyOpts.governanceOpts.partyFactory = partyFactory;
        partyOpts.governanceOpts.voteDuration = 7 days;
        partyOpts.governanceOpts.executionDelay = 1 days;
        partyOpts.governanceOpts.passThresholdBps = 0.5e4;
        partyOpts.governanceOpts.hosts = new address[](1);
        partyOpts.governanceOpts.hosts[0] = address(this);

        crowdfund = InitialETHCrowdfund(payable(address(initialETHCrowdfundImpl).clone()));
        if (initialize) {
            crowdfund.initialize{ value: args.initialContribution }(
                crowdfundOpts,
                partyOpts,
                MetadataProvider(address(0)),
                ""
            );
        }
    }

    function _createCrowdfund(
        CreateCrowdfundArgs memory args
    ) internal returns (InitialETHCrowdfund) {
        return _createCrowdfund(args, true);
    }
}

contract InitialETHCrowdfundTest is InitialETHCrowdfundTestBase {
    using Clones for address;

    function test_initialization_cannotReinitialize() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 0,
                maxTotalContributions: type(uint96).max,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory defaultCrowdfundOpts;
        InitialETHCrowdfund.ETHPartyOptions memory defaultPartyOpts;

        vm.expectRevert(Implementation.AlreadyInitialized.selector);
        crowdfund.initialize(
            defaultCrowdfundOpts,
            defaultPartyOpts,
            MetadataProvider(address(0)),
            ""
        );
    }

    function test_initialization_minTotalContributionsGreaterThanMax() public {
        uint96 minTotalContributions = 5 ether;
        uint96 maxTotalContributions = 3 ether;

        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: minTotalContributions,
                maxTotalContributions: maxTotalContributions,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            }),
            false
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.MinGreaterThanMaxError.selector,
                minTotalContributions,
                maxTotalContributions
            )
        );
        crowdfund.initialize(crowdfundOpts, partyOpts, MetadataProvider(address(0)), "");
    }

    function test_initialization_maxTotalContributionsZero() public {
        uint96 maxTotalContributions = 0;
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 0,
                maxTotalContributions: maxTotalContributions,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            }),
            false
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.MaxTotalContributionsCannotBeZeroError.selector,
                maxTotalContributions
            )
        );
        crowdfund.initialize(crowdfundOpts, partyOpts, MetadataProvider(address(0)), "");
    }

    function test_initialContribution_works() public {
        address payable initialContributor = payable(_randomAddress());
        address initialDelegate = _randomAddress();
        uint96 initialContribution = 1 ether;

        // Create crowdfund with initial contribution
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: initialContribution,
                initialContributor: initialContributor,
                initialDelegate: initialDelegate,
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        assertEq(initialContributor.balance, 0);
        assertEq(address(crowdfund).balance, initialContribution);
        assertEq(crowdfund.totalContributions(), initialContribution);
        assertEq(party.tokenCount(), 1);
        assertEq(party.ownerOf(1), initialContributor);
        assertEq(party.votingPowerByTokenId(1), initialContribution);
        assertEq(
            party.getVotingPowerAt(initialDelegate, uint40(block.timestamp)),
            initialContribution
        );
    }

    function test_initialContribution_aboveMaxTotalContribution() public {
        address payable initialContributor = payable(_randomAddress());
        address initialDelegate = _randomAddress();
        uint96 initialContribution = 1 ether;

        // Create crowdfund with initial contribution
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: initialContribution,
                initialContributor: initialContributor,
                initialDelegate: initialDelegate,
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: initialContribution,
                maxTotalContributions: initialContribution,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );
        assertEq(party.getGovernanceValues().totalVotingPower, initialContribution);
        assertEq(address(party).balance, initialContribution);
    }

    function test_contribute_mintNewCard() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1 ether, member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        uint256 tokenId = 1;
        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 1 ether);

        assertEq(address(member).balance, 0);
        assertEq(address(crowdfund).balance, 1 ether);
        assertEq(crowdfund.totalContributions(), 1 ether);
        assertEq(crowdfund.delegationsByContributor(member), member);
    }

    function test_contribute_mintNewCard_withDisableContributingForExistingCard() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: true,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        uint256 tokenId = 1;
        vm.prank(member);
        vm.expectRevert(ETHCrowdfundBase.ContributingForExistingCardDisabledError.selector);
        crowdfund.contribute{ value: 1 ether }(tokenId, member, "");
    }

    function test_contribute_increaseVotingPowerToExistingCard() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1 ether, member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        uint256 tokenId = 1;
        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 1 ether);

        // Contribute again
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(tokenId, member, "");
        assertEq(party.votingPowerByTokenId(tokenId), 2 ether);
    }

    function test_contribute_smallAmountWithFundingSplit() public {
        address payable fundingSplitRecipient = payable(_randomAddress());

        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.5e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1234);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1234, member);
        crowdfund.contribute{ value: 1234 }(member, "");

        uint256 tokenId = 1;
        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 1234 / 2);
    }

    function test_contribute_noContribution() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();

        // Contribute, should be allowed to update delegate
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 0, member);
        crowdfund.contribute(member, "");
    }

    function test_contribute_noVotingPower() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 1);

        // Contribute, should result in 0 voting power
        vm.prank(member);
        vm.expectRevert(ETHCrowdfundBase.ZeroVotingPowerError.selector);
        crowdfund.contribute{ value: 1 }(member, "");
    }

    function test_contribute_afterLost() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 1);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Try to contribute
        vm.prank(member);
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.WrongLifecycleError.selector,
                ETHCrowdfundBase.CrowdfundLifecycle.Lost
            )
        );
        crowdfund.contribute{ value: 1 }(member, "");
    }

    function test_contribute_aboveMaxTotalContribution() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 0,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        assertEq(address(member).balance, 1 ether); // Check refunded amount
        assertEq(address(party).balance, 1 ether);
        assertEq(crowdfund.totalContributions(), 1 ether);
        assertEq(party.getGovernanceValues().totalVotingPower, 1 ether);
    }

    function test_contribute_aboveMaxTotalContributionWhenWhenContributionBelowMinContributionAfterRefund()
        public
    {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 1 ether,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 0,
                maxTotalContributions: 2 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 3 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1.5 ether }(member, "");

        // Contribute again but amount after refund (0.5 ether) is below min contribution
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.BelowMinimumContributionsError.selector,
                0.5 ether,
                1 ether
            )
        );
        vm.prank(member);
        crowdfund.contribute{ value: 1.5 ether }(member, "");
    }

    function test_contribute_aboveMaxContribution() public {
        uint96 maxContribution = 1 ether;
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: maxContribution,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        uint96 contribution = maxContribution + 1;
        vm.deal(member, contribution);

        // Contribute
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.AboveMaximumContributionsError.selector,
                contribution,
                maxContribution
            )
        );
        vm.prank(member);
        crowdfund.contribute{ value: contribution }(member, "");
    }

    function test_contribute_belowMinContribution() public {
        uint96 minContribution = 1 ether;
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: minContribution,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        uint96 contribution = minContribution - 1;
        vm.deal(member, contribution);

        // Contribute
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.BelowMinimumContributionsError.selector,
                contribution,
                minContribution
            )
        );
        vm.prank(member);
        crowdfund.contribute{ value: contribution }(member, "");
    }

    function test_contribute_gatekeeperChecksSender() public {
        address member = _randomAddress();

        // Create allowlist gatekeeper with only member allowed
        AllowListGateKeeper gatekeeper = new AllowListGateKeeper(address(0));
        bytes12 gateId = gatekeeper.createGate(keccak256(abi.encodePacked(member)));

        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: gatekeeper,
                gateKeeperId: gateId
            })
        );

        vm.deal(member, 2 ether);

        // Contribute as non-member (should fail)
        address payable nonMember = _randomAddress();
        vm.prank(nonMember);
        vm.deal(nonMember, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.NotAllowedByGateKeeperError.selector,
                nonMember,
                gatekeeper,
                gateId,
                abi.encode(new bytes32[](0))
            )
        );
        crowdfund.contribute{ value: 1 ether }(member, abi.encode(new bytes32[](0)));

        // Contribute as member (should succeed)
        vm.prank(member);
        vm.expectEmit(true, true, true, true);
        emit Contributed(member, member, 1 ether, member);
        crowdfund.contribute{ value: 1 ether }(member, abi.encode(new bytes32[](0)));

        // Contribute as member on behalf of non-member (should succeed)
        vm.prank(member);
        vm.expectEmit(true, true, true, true);
        emit Contributed(member, nonMember, 1 ether, member);
        vm.expectEmit(true, true, true, true);
        emit PartyDelegateUpdated(nonMember, member);

        crowdfund.contributeFor{ value: 1 ether }(
            0,
            nonMember,
            member,
            abi.encode(new bytes32[](0))
        );
    }

    function test_contribute_withFundingSplit() public {
        address payable fundingSplitRecipient = payable(_randomAddress());

        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1 ether, member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        uint256 tokenId = 1;
        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 0.8 ether); // 80% of 1 ETH
    }

    function test_contribute_cannotDelegateToZeroAddress() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        vm.expectRevert(ETHCrowdfundBase.InvalidDelegateError.selector);
        crowdfund.contribute{ value: 1 ether }(address(0), "");
    }

    function test_batchContribute_works() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 4 ether);

        // Batch contribute
        vm.prank(member);
        uint256[] memory tokenIds = new uint256[](3);
        uint96[] memory values = new uint96[](3);
        for (uint256 i; i < 3; ++i) {
            values[i] = 1 ether;
        }
        bytes[] memory gateDatas = new bytes[](3);
        uint96[] memory votingPowers = crowdfund.batchContribute{ value: 4 ether }(
            InitialETHCrowdfund.BatchContributeArgs({
                tokenIds: tokenIds,
                delegate: member,
                values: values,
                gateDatas: gateDatas
            })
        );

        assertEq(address(member).balance, 1 ether); // Should be refunded 1 ETH
        for (uint256 i; i < values.length; ++i) {
            assertEq(votingPowers[i], 1 ether);
        }
        for (uint256 i = 1; i < 4; ++i) {
            assertEq(party.ownerOf(i), member);
            assertEq(party.votingPowerByTokenId(i), 1 ether);
        }
    }

    function test_contributeFor_works() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        address payable recipient = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, recipient, 1 ether, delegate);
        crowdfund.contributeFor{ value: 1 ether }(0, recipient, delegate, "");

        uint256 tokenId = 1;
        assertEq(party.ownerOf(tokenId), recipient);
        assertEq(party.votingPowerByTokenId(tokenId), 1 ether);

        assertEq(address(recipient).balance, 0);
        assertEq(address(crowdfund).balance, 1 ether);
        assertEq(crowdfund.delegationsByContributor(recipient), delegate);
        assertEq(crowdfund.totalContributions(), 1 ether);
    }

    function test_contributeFor_doesNotUpdateExistingDelegation() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        crowdfund.party();

        address member = _randomAddress();
        address payable recipient = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute to set initial delegation
        vm.prank(recipient);
        vm.expectEmit(true, false, false, true);
        emit Contributed(recipient, recipient, 0, recipient);
        crowdfund.contribute(recipient, "");

        // Contribute to try update delegation (should not work)
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, recipient, 1 ether, recipient);
        crowdfund.contributeFor{ value: 1 ether }(0, recipient, delegate, "");

        assertEq(crowdfund.delegationsByContributor(recipient), recipient);
    }

    function test_batchContributeFor_works() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 1 ether,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address sender = _randomAddress();
        vm.deal(sender, 4 ether);

        // Batch contribute for
        vm.prank(sender);
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory recipients = new address payable[](3);
        address[] memory delegates = new address[](3);
        uint96[] memory values = new uint96[](3);
        bytes[] memory gateDatas = new bytes[](3);
        for (uint256 i; i < 3; ++i) {
            recipients[i] = _randomAddress();
            delegates[i] = _randomAddress();
            values[i] = 1 ether;
        }
        uint96[] memory votingPowers = crowdfund.batchContributeFor{ value: 3 ether }(
            InitialETHCrowdfund.BatchContributeForArgs({
                tokenIds: tokenIds,
                recipients: recipients,
                initialDelegates: delegates,
                values: values,
                gateDatas: gateDatas
            })
        );

        assertEq(address(sender).balance, 1 ether);
        for (uint256 i; i < 3; ++i) {
            assertEq(votingPowers[i], 1 ether);
            assertEq(crowdfund.delegationsByContributor(recipients[i]), delegates[i]);

            uint256 tokenId = i + 1;
            assertEq(party.ownerOf(tokenId), recipients[i]);
            assertEq(party.votingPowerByTokenId(tokenId), 1 ether);
        }
        // Should not have minted for failed contribution
        assertEq(party.votingPowerByTokenId(4), 0);
    }

    function test_batchContributeFor_works_invalidMessageValue() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 1 ether,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address sender = _randomAddress();
        vm.deal(sender, 4 ether);

        // Batch contribute for
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory recipients = new address payable[](3);
        address[] memory delegates = new address[](3);
        uint96[] memory values = new uint96[](3);
        bytes[] memory gateDatas = new bytes[](3);
        for (uint256 i; i < 3; ++i) {
            recipients[i] = _randomAddress();
            delegates[i] = _randomAddress();
            values[i] = 1 ether;
        }
        vm.expectRevert(ETHCrowdfundBase.InvalidMessageValue.selector);
        vm.prank(sender);
        uint96[] memory votingPowers = crowdfund.batchContributeFor{ value: 3 ether - 100 }(
            InitialETHCrowdfund.BatchContributeForArgs({
                tokenIds: tokenIds,
                recipients: recipients,
                initialDelegates: delegates,
                values: values,
                gateDatas: gateDatas
            })
        );
    }

    function test_finalize_works() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 3 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 3 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        // Finalize
        crowdfund.finalize();

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );
        assertEq(party.getGovernanceValues().totalVotingPower, 3 ether);
        assertEq(address(party).balance, 3 ether);
    }

    function test_finalize_onlyHostCanFinalizeEarlyWhenActive() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 3 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 3 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        // Try to finalize as non-host
        address nonHost = _randomAddress();
        vm.expectRevert(ETHCrowdfundBase.OnlyPartyHostError.selector);
        vm.prank(nonHost);
        crowdfund.finalize();
    }

    function test_finalize_anyoneCanFinalizeWhenExpired() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 3 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 3 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        skip(7 days);

        // Try to finalize as rando
        vm.prank(_randomAddress());
        crowdfund.finalize();
    }

    function test_finalize_belowMinTotalContributions() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        // Try to finalize
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.NotEnoughContributionsError.selector,
                2 ether,
                3 ether
            )
        );
        crowdfund.finalize();
    }

    function test_finalize_withFundingSplit() public {
        address payable fundingSplitRecipient = payable(_randomAddress());

        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 6 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 5 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        // Finalize
        crowdfund.finalize();

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        assertEq(party.getGovernanceValues().totalVotingPower, 4 ether); // 80% of 5 ETH
        assertEq(address(party).balance, 4 ether); // 80% of 5 ETH
    }

    function test_expiry_won() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        address member = _randomAddress();
        vm.deal(member, 4 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 4 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Won);
    }

    function test_expiry_lost() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);
    }

    function test_refund_works() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");
        assertEq(address(member).balance, 0);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Claim refund
        vm.prank(member);
        uint256 tokenId = 1;
        vm.expectEmit(true, true, false, true);
        emit Refunded(member, tokenId, 2 ether);
        crowdfund.refund(tokenId);
        vm.expectRevert("NOT_MINTED"); // Check token burned
        party.ownerOf(tokenId);
        assertEq(address(member).balance, 2 ether);
    }

    function test_refund_notLost() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 5 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        // Try to claim refund
        vm.prank(member);
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.WrongLifecycleError.selector,
                ETHCrowdfundBase.CrowdfundLifecycle.Active
            )
        );
        uint256 tokenId = 1;
        crowdfund.refund(tokenId);

        // Contribute again to win
        vm.prank(member);
        crowdfund.contribute{ value: 3 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Try to claim refund
        vm.prank(member);
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.WrongLifecycleError.selector,
                ETHCrowdfundBase.CrowdfundLifecycle.Finalized
            )
        );
        crowdfund.refund(tokenId);
    }

    function test_refund_twice() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");
        assertEq(address(member).balance, 0);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Claim refund
        vm.prank(member);
        uint256 tokenId = 1;
        crowdfund.refund(tokenId);
        assertEq(address(member).balance, 2 ether);
        assertEq(address(party).balance, 0);

        // Try to claim refund again
        vm.prank(member);
        crowdfund.refund(tokenId);
        // Check balance unchanged
        assertEq(address(member).balance, 2 ether);
        assertEq(address(party).balance, 0);
    }

    function test_batchRefund_works() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 4 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        // Contribute
        address[] memory members = new address[](3);
        for (uint256 i = 0; i < members.length; i++) {
            members[i] = _randomAddress();
            vm.deal(members[i], 1 ether);
            vm.prank(members[i]);
            crowdfund.contribute{ value: 1 ether }(members[i], "");
        }

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Batch refund
        address sender = _randomAddress();
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = i + 1;
        }
        vm.prank(sender);
        crowdfund.batchRefund(tokenIds, true);

        for (uint256 i = 0; i < members.length; i++) {
            assertEq(address(members[i]).balance, 1 ether);
        }
    }

    function test_fundingSplit_contributionAndRefund() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");
        uint256 tokenId = 1;
        assertEq(address(member).balance, 0);
        assertEq(party.votingPowerByTokenId(tokenId), 0.8 ether);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Claim refund
        vm.prank(member);
        crowdfund.refund(tokenId);
        assertEq(address(member).balance, 1 ether);
        assertEq(address(party).balance, 0);
    }

    function test_sendFundingSplit_works() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        assertEq(address(party).balance, 0.8 ether);

        // Send funding split
        crowdfund.sendFundingSplit();

        assertEq(fundingSplitRecipient.balance, 0.2 ether);
    }

    function test_sendFundingSplit_canOnlySendWhenFinalized() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        // Send funding split before finalized (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.WrongLifecycleError.selector,
                ETHCrowdfundBase.CrowdfundLifecycle.Active
            )
        );
        crowdfund.sendFundingSplit();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Send funding split after finalized (should work)
        crowdfund.sendFundingSplit();
    }

    function test_sendFundingSplit_cannotSendTwice() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Send funding split
        crowdfund.sendFundingSplit();

        // Send funding split again (should fail)
        vm.expectRevert(ETHCrowdfundBase.FundingSplitAlreadyPaidError.selector);
        crowdfund.sendFundingSplit();
    }

    function test_sendFundingSplit_cannotSendIfNoFundingSplit() public {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Send funding split
        vm.expectRevert(ETHCrowdfundBase.FundingSplitNotConfiguredError.selector);
        crowdfund.sendFundingSplit();
    }

    function test_initialization_multipleAuthorities() public {
        uint96 initialContribution = 1 ether;
        address[] memory authorities = new address[](4);
        for (uint256 i = 0; i < authorities.length; i++) {
            authorities[i] = _randomAddress();
        }

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts = InitialETHCrowdfund
            .InitialETHCrowdfundOptions({
                initialContributor: payable(address(this)),
                initialDelegate: address(this),
                minContribution: 1,
                maxContribution: 2 ether,
                disableContributingForExistingCard: true,
                minTotalContributions: 0,
                maxTotalContributions: 10 ether,
                exchangeRateBps: 10000,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(0),
                duration: 1 days,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0
            });

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: "Test Party",
            symbol: "TPARTY",
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: partyImpl,
                partyFactory: partyFactory,
                hosts: new address[](0),
                voteDuration: 1 days,
                executionDelay: 1,
                passThresholdBps: 1000,
                feeBps: 0,
                feeRecipient: payable(0)
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: true,
                allowArbCallsToSpendPartyEth: true,
                allowOperators: true,
                distributionsRequireVote: true
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: authorities
        });

        vm.deal(address(this), initialContribution);
        InitialETHCrowdfund crowdfund = InitialETHCrowdfund(
            payable(address(initialETHCrowdfundImpl).clone())
        );

        crowdfund.initialize{ value: initialContribution }(
            crowdfundOpts,
            partyOpts,
            MetadataProvider(address(0)),
            ""
        );

        Party party_ = crowdfund.party();
        for (uint i = 0; i < authorities.length; i++) {
            assertTrue(party_.isAuthority(authorities[i]));
        }
    }
}

contract InitialETHCrowdfundForkedTest is InitialETHCrowdfundTestBase {
    function testForked_partyCardTokenURI_whileCrowdfundActive() public onlyForked {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        string memory tokenURI = party.tokenURI(1);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testForked_partyCardTokenURI_whileCrowdfundWon() public onlyForked {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Won);

        string memory tokenURI = party.tokenURI(1);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testForked_partyCardTokenURI_whileCrowdfundLost() public onlyForked {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 5 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        string memory tokenURI = party.tokenURI(1);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testForked_partyCardTokenURI_whileCrowdfundFinalized() public onlyForked {
        InitialETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 1 ether,
                maxTotalContributions: 1 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0,
                fundingSplitRecipient: payable(address(0)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );
        Party party = crowdfund.party();

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        string memory tokenURI = party.tokenURI(1);

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }
}
