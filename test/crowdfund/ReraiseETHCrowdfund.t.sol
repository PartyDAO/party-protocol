// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import "../../contracts/crowdfund/ReraiseETHCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/party/PartyFactory.sol";
import "../../contracts/tokens/ERC721Receiver.sol";
import "../../contracts/renderers/CrowdfundNFTRenderer.sol";
import "../../contracts/renderers/RendererStorage.sol";
import "../../contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "../../contracts/distribution/TokenDistributor.sol";
import "../../contracts/gatekeepers/AllowListGateKeeper.sol";
import { LintJSON } from "../utils/LintJSON.sol";
import "../TestUtils.sol";

contract ReraiseETHCrowdfundTest is LintJSON, TestUtils, ERC721Receiver {
    using Clones for address;

    event Transfer(address indexed owner, address indexed to, uint256 indexed tokenId);
    event Contributed(
        address indexed sender,
        address indexed contributor,
        uint256 amount,
        address delegate
    );
    event Refunded(address indexed contributor, uint256 amount);
    event Claimed(address indexed contributor, uint256 indexed tokenId, uint256 votingPower);

    Party party;
    ReraiseETHCrowdfund reraiseETHCrowdfundImpl;

    CrowdfundNFTRenderer nftRenderer;
    RendererStorage nftRendererStorage;
    TokenDistributor tokenDistributor;

    ETHCrowdfundBase.ETHCrowdfundOptions opts;

    constructor() {
        Globals globals = new Globals(address(this));

        reraiseETHCrowdfundImpl = new ReraiseETHCrowdfund(globals);

        // Upload font on-chain
        PixeldroidConsoleFont font = new PixeldroidConsoleFont();
        nftRendererStorage = new RendererStorage(address(this));
        nftRenderer = new CrowdfundNFTRenderer(globals, nftRendererStorage, font);
        tokenDistributor = new TokenDistributor(globals, 0);

        globals.setAddress(LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL, address(nftRenderer));
        globals.setAddress(LibGlobals.GLOBAL_RENDERER_STORAGE, address(nftRendererStorage));
        globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor));

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

        Party.PartyInitData memory partyOpts;
        partyOpts.options.name = "Test Party";
        partyOpts.options.symbol = "TEST";
        partyOpts.options.governance.voteDuration = 7 days;
        partyOpts.options.governance.executionDelay = 1 days;
        partyOpts.options.governance.passThresholdBps = 0.5e4;
        partyOpts.options.governance.hosts = new address[](1);
        partyOpts.options.governance.hosts[0] = address(this);

        party = Party(payable(address(new Party(globals)).clone()));
        party.initialize(partyOpts);
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
    ) private returns (ReraiseETHCrowdfund crowdfund) {
        opts.party = party;
        opts.initialContributor = args.initialContributor;
        opts.initialDelegate = args.initialDelegate;
        opts.minContribution = args.minContributions;
        opts.maxContribution = args.maxContributions;
        opts.disableContributingForExistingCard = args.disableContributingForExistingCard;
        opts.minTotalContributions = args.minTotalContributions;
        opts.maxTotalContributions = args.maxTotalContributions;
        opts.duration = args.duration;
        opts.exchangeRateBps = args.exchangeRateBps;
        opts.fundingSplitBps = args.fundingSplitBps;
        opts.fundingSplitRecipient = args.fundingSplitRecipient;
        opts.gateKeeper = args.gateKeeper;
        opts.gateKeeperId = args.gateKeeperId;

        crowdfund = ReraiseETHCrowdfund(address(reraiseETHCrowdfundImpl).clone());

        if (initialize) {
            crowdfund.initialize{ value: args.initialContribution }(opts);

            vm.prank(address(party));
            party.addAuthority(address(crowdfund));
        }
    }

    function _createCrowdfund(
        CreateCrowdfundArgs memory args
    ) private returns (ReraiseETHCrowdfund crowdfund) {
        return _createCrowdfund(args, true);
    }

    function test_initialization_cannotReinitialize() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        ETHCrowdfundBase.ETHCrowdfundOptions memory emptyOpts;

        vm.expectRevert(Implementation.AlreadyInitialized.selector);
        crowdfund.initialize(emptyOpts);
    }

    function test_initialization_minTotalContributionsGreaterThanMax() public {
        uint96 minTotalContributions = 5 ether;
        uint96 maxTotalContributions = 3 ether;

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.initialize(opts);
    }

    function test_initialization_maxTotalContributionsZero() public {
        uint96 maxTotalContributions = 0;

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.initialize(opts);
    }

    function test_initialContribution_works() public {
        address payable initialContributor = payable(_randomAddress());
        address initialDelegate = _randomAddress();
        uint96 initialContribution = 1 ether;

        // Create crowdfund with initial contribution
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        assertEq(initialContributor.balance, 0);
        assertEq(address(crowdfund).balance, initialContribution);
        assertEq(crowdfund.totalContributions(), initialContribution);
        assertEq(crowdfund.pendingVotingPower(initialContributor), initialContribution);
    }

    function test_initialContribution_aboveMaxTotalContribution() public {
        address payable initialContributor = payable(_randomAddress());
        address initialDelegate = _randomAddress();
        uint96 initialContribution = 1 ether;

        // Create crowdfund with initial contribution
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
            }),
            false
        );

        // Will fail because initial contribution should trigger crowdfund to
        // try to finalize a win but it will fail because it is not yet set as
        // an authority on the party
        vm.expectRevert(PartyGovernance.NotAuthorized.selector);
        crowdfund.initialize{ value: initialContribution }(opts);
    }

    function test_contribute_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        uint256 tokenId = uint256(uint160(member));
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1 ether, member);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), member, tokenId);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertEq(member.balance, 0);
        assertEq(address(crowdfund).balance, 1 ether);
        assertEq(crowdfund.totalContributions(), 1 ether);
        assertEq(crowdfund.pendingVotingPower(member), 1 ether);
        assertEq(crowdfund.ownerOf(tokenId), member);
        assertEq(crowdfund.delegationsByContributor(member), member);
    }

    function test_contribute_twiceDoesNotMintAnotherCrowdfundNFT() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        vm.startPrank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");
        crowdfund.contribute{ value: 1 ether }(member, "");
        vm.stopPrank();

        assertEq(crowdfund.balanceOf(member), 1);
        assertEq(crowdfund.pendingVotingPower(member), 2 ether);
    }

    function test_contribute_smallAmountWithFundingSplit() public {
        address payable fundingSplitRecipient = payable(_randomAddress());

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address member = _randomAddress();
        vm.deal(member, 1234);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1234, member);
        crowdfund.contribute{ value: 1234 }(member, "");

        assertEq(crowdfund.pendingVotingPower(member), 1234 / 2);
    }

    function test_contribute_noContribution() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1, member);
        crowdfund.contribute{ value: 1 }(member, "");
    }

    function test_contribute_aboveMaxTotalContribution() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address member = _randomAddress();
        vm.deal(member, 2 ether);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 2 ether, member);
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, contribution, member);
        crowdfund.contribute{ value: contribution }(member, "");
    }

    function test_contribute_belowMinContribution() public {
        uint96 minContribution = 1 ether;
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, contribution, member);
        crowdfund.contribute{ value: contribution }(member, "");
    }

    function test_contribute_gatekeeperChecksSender() public {
        address member = _randomAddress();

        // Create allowlist gatekeeper with only member allowed
        AllowListGateKeeper gatekeeper = new AllowListGateKeeper(address(0));
        bytes12 gateId = gatekeeper.createGate(keccak256(abi.encodePacked(member)));
        bytes memory gateData = abi.encode(new bytes32[](0));

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
                gateData
            )
        );
        crowdfund.contribute{ value: 1 ether }(member, gateData);

        // Contribute as member (should succeed)
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1 ether, member);
        crowdfund.contribute{ value: 1 ether }(member, gateData);

        // Contribute as member on behalf of non-member (should succeed)
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, nonMember, 1 ether, member);
        crowdfund.contributeFor{ value: 1 ether }(nonMember, member, gateData);
    }

    function test_contribute_withFundingSplit() public {
        address payable fundingSplitRecipient = payable(_randomAddress());

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, member, 1 ether, member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertEq(crowdfund.pendingVotingPower(member), 0.8 ether); // 80% of 1 ETH
    }

    function test_contribute_cannotDelegateToZeroAddress() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        // Batch contribute
        vm.prank(member);
        uint96[] memory values = new uint96[](3);
        for (uint256 i; i < 3; ++i) {
            values[i] = 1 ether;
        }
        bytes[] memory gateDatas = new bytes[](3);
        uint96[] memory votingPowers = crowdfund.batchContribute{ value: 4 ether }(
            ReraiseETHCrowdfund.BatchContributeArgs({
                delegate: member,
                values: values,
                gateDatas: gateDatas
            })
        );

        assertEq(address(member).balance, 1 ether); // Should be refunded 1 ETH
        assertEq(crowdfund.ownerOf(uint256(uint160(member))), member);
        for (uint256 i; i < values.length; ++i) {
            assertEq(votingPowers[i], 1 ether);
        }
    }

    function test_contributeFor_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        // Contribute
        vm.prank(member);
        vm.expectEmit(true, false, false, true);
        emit Contributed(member, recipient, 1 ether, delegate);
        crowdfund.contributeFor{ value: 1 ether }(recipient, delegate, "");

        assertEq(address(recipient).balance, 0);
        assertEq(address(crowdfund).balance, 1 ether);
        assertEq(crowdfund.delegationsByContributor(recipient), delegate);
        assertEq(crowdfund.totalContributions(), 1 ether);
    }

    function test_contributeFor_doesNotUpdateExistingDelegation() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contributeFor{ value: 1 ether }(recipient, delegate, "");

        assertEq(crowdfund.delegationsByContributor(recipient), recipient);
    }

    function test_batchContributeFor_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address sender = _randomAddress();
        vm.deal(sender, 4 ether);

        // Batch contribute for
        vm.prank(sender);
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
            ReraiseETHCrowdfund.BatchContributeForArgs({
                recipients: recipients,
                initialDelegates: delegates,
                values: values,
                gateDatas: gateDatas
            })
        );

        assertEq(address(sender).balance, 1 ether); // Should be refunded 1 ETH
        for (uint256 i; i < 3; ++i) {
            assertEq(votingPowers[i], 1 ether);
            assertEq(crowdfund.delegationsByContributor(recipients[i]), delegates[i]);
            assertEq(crowdfund.pendingVotingPower(recipients[i]), 1 ether);
        }
    }

    function test_batchContributeFor_works_invalidMessageValue() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address sender = _randomAddress();
        vm.deal(sender, 4 ether);

        // Batch contribute for
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
            ReraiseETHCrowdfund.BatchContributeForArgs({
                recipients: recipients,
                initialDelegates: delegates,
                values: values,
                gateDatas: gateDatas
            })
        );
    }

    function test_finalize_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        // Finalize
        crowdfund.finalize();

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );
        assertEq(party.getGovernanceValues().totalVotingPower, 3 ether);
        assertEq(address(party).balance, 3 ether);
    }

    function test_finalize_onlyHostCanFinalizeEarlyWhenActive() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

    function test_claim_mintNewCard() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        uint256 tokenId = 1;
        vm.expectEmit(true, true, true, true);
        emit Transfer(member, address(0), uint256(uint160(member)));
        vm.expectEmit(true, true, false, true);
        emit Claimed(member, tokenId, 5 ether);
        crowdfund.claim(member);

        // Should have burned the crowdfund NFT
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundNFT.InvalidTokenError.selector,
                uint256(uint160(member))
            )
        );
        crowdfund.ownerOf(uint256(uint160(member)));

        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 5 ether);
    }

    function test_claim_aboveMax() public {
        address payable fundingSplitRecipient = payable(_randomAddress());

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: 2 ether,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 4 ether,
                duration: 7 days,
                exchangeRateBps: 1e4,
                fundingSplitBps: 0.2e4,
                fundingSplitRecipient: fundingSplitRecipient,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: bytes12(0)
            })
        );

        address member = _randomAddress();
        vm.deal(member, 4 ether);

        // Contribute, twice
        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");

        vm.prank(member);
        crowdfund.contribute{ value: 2 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.AboveMaximumContributionsError.selector,
                4 ether,
                2 ether
            )
        );
        crowdfund.claim(member);
    }

    function test_claim_mintNewCard_withDisableContributingForExistingCard() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        vm.deal(member, 5 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        uint256 tokenId = 1;
        vm.prank(member);
        vm.expectRevert(ETHCrowdfundBase.ContributingForExistingCardDisabledError.selector);
        crowdfund.claim(tokenId, member);
    }

    function test_claim_increaseVotingPowerToExistingCard() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        // Mint (empty) card for member
        vm.prank(address(crowdfund));
        party.mint(member, 0, member);

        uint256 tokenId = 1;
        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 0);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card and add voting power to existing card
        vm.expectEmit(true, true, true, true);
        emit Transfer(member, address(0), uint256(uint160(member)));
        vm.expectEmit(true, true, false, true);
        emit Claimed(member, tokenId, 5 ether);
        crowdfund.claim(tokenId, member);

        // Should have burned the crowdfund NFT
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundNFT.InvalidTokenError.selector,
                uint256(uint160(member))
            )
        );
        crowdfund.ownerOf(uint256(uint160(member)));

        assertEq(party.ownerOf(tokenId), member);
        assertEq(party.votingPowerByTokenId(tokenId), 5 ether);
    }

    function test_batchClaim_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 3 ether,
                maxTotalContributions: 3 ether,
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

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Batch claim
        uint256[] memory tokenIds = new uint256[](3);
        crowdfund.batchClaim(tokenIds, members, true);

        for (uint256 i = 0; i < members.length; i++) {
            uint256 tokenId = i + 1;
            assertEq(party.ownerOf(tokenId), members[i]);
            assertEq(party.votingPowerByTokenId(tokenId), 1 ether);
        }
    }

    function test_claimMultiple_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        uint96[] memory votingPowerByCard = new uint96[](5);
        uint256[] memory tokenIds = new uint256[](5);
        for (uint256 i; i < votingPowerByCard.length; ++i) {
            votingPowerByCard[i] = 1 ether;

            if (i == 4) {
                // For last claim, add voting power to recently minted card
                tokenIds[i] = 1;

                vm.expectEmit(true, true, false, true);
                emit Claimed(member, 1, 1 ether);
            } else {
                vm.expectEmit(true, true, false, true);
                emit Claimed(member, i + 1, 1 ether);
            }
        }

        crowdfund.claimMultiple(votingPowerByCard, tokenIds, member);

        for (uint256 i; i < votingPowerByCard.length; ++i) {
            uint256 tokenId = i + 1;

            if (tokenId == 1) {
                assertEq(party.ownerOf(tokenId), member);
                assertEq(party.votingPowerByTokenId(tokenId), 2 ether);
            } else if (tokenId == 5) {
                assertEq(party.votingPowerByTokenId(tokenId), 0);
            } else {
                assertEq(party.ownerOf(tokenId), member);
                assertEq(party.votingPowerByTokenId(tokenId), 1 ether);
            }
        }
    }

    function test_claimMultiple_cannotClaimMoreThanVotingPower() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        uint96[] memory votingPowerByCard = new uint96[](6);
        uint256[] memory tokenIds = new uint256[](6);
        for (uint256 i; i < votingPowerByCard.length; ++i) {
            votingPowerByCard[i] = 1 ether;
        }

        vm.expectRevert(stdError.arithmeticError);
        crowdfund.claimMultiple(votingPowerByCard, tokenIds, member);
    }

    function test_claimMultiple_cannotHaveRemainingVotingPowerAfterClaim() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        uint96[] memory votingPowerByCard = new uint96[](4);
        uint256[] memory tokenIds = new uint256[](4);
        for (uint256 i; i < votingPowerByCard.length; ++i) {
            votingPowerByCard[i] = 1 ether;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                ReraiseETHCrowdfund.RemainingVotingPowerAfterClaimError.selector,
                1 ether // 4 ether of voting power claimed, 1 ether remaining
            )
        );
        crowdfund.claimMultiple(votingPowerByCard, tokenIds, member);
    }

    function test_claimMultiple_votingPowerOfCardBelowMin() public {
        uint96 minContributions = 1 ether;

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: minContributions,
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
        crowdfund.contribute{ value: 5 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Claim card
        uint96[] memory votingPowerByCard = new uint96[](1);
        uint256[] memory tokenIds = new uint256[](1);
        votingPowerByCard[0] = minContributions - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.BelowMinimumContributionsError.selector,
                votingPowerByCard[0],
                minContributions
            )
        );
        crowdfund.claimMultiple(votingPowerByCard, tokenIds, member);
    }

    function test_claimMultiple_votingPowerOfCardAboveMax() public {
        uint96 maxContributions = 1 ether;

        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: maxContributions,
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

        // Claim card
        uint96[] memory votingPowerByCard = new uint96[](1);
        uint256[] memory tokenIds = new uint256[](1);
        votingPowerByCard[0] = maxContributions + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.AboveMaximumContributionsError.selector,
                votingPowerByCard[0],
                maxContributions
            )
        );
        crowdfund.claimMultiple(votingPowerByCard, tokenIds, member);
    }

    function test_batchClaimMultiple_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
            CreateCrowdfundArgs({
                initialContribution: 0,
                initialContributor: payable(address(0)),
                initialDelegate: address(0),
                minContributions: 0,
                maxContributions: type(uint96).max,
                disableContributingForExistingCard: false,
                minTotalContributions: 6 ether,
                maxTotalContributions: 6 ether,
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
            vm.deal(members[i], 2 ether);
            vm.prank(members[i]);
            crowdfund.contribute{ value: 2 ether }(members[i], "");
        }

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        // Batch claim cards
        uint96[][] memory votingPowerByCards = new uint96[][](3);
        uint256[][] memory tokenIds = new uint256[][](3);
        for (uint256 i = 0; i < votingPowerByCards.length; i++) {
            votingPowerByCards[i] = new uint96[](2);
            votingPowerByCards[i][0] = votingPowerByCards[i][1] = 1 ether;
            tokenIds[i] = new uint256[](2);
        }

        crowdfund.batchClaimMultiple(votingPowerByCards, tokenIds, members, true);

        for (uint256 i = 0; i < members.length; i++) {
            for (uint256 j = 1; j < 3; ++j) {
                assertEq(party.ownerOf(i * 2 + j), members[i]);
                assertEq(party.votingPowerByTokenId(i * 2 + j), 1 ether);
            }
        }
    }

    function test_refund_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        assertEq(address(member).balance, 0);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Claim refund
        vm.expectEmit(true, false, false, true);
        emit Transfer(member, address(0), uint256(uint160(member)));
        vm.expectEmit(true, true, true, true);
        emit Refunded(member, 2 ether);
        vm.prank(member);
        crowdfund.refund(payable(member));

        // Should have burned the crowdfund NFT
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundNFT.InvalidTokenError.selector,
                uint256(uint160(member))
            )
        );
        crowdfund.ownerOf(uint256(uint160(member)));

        assertEq(address(member).balance, 2 ether);
    }

    function test_refund_notLost() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.refund(payable(member));

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
        crowdfund.refund(payable(member));
    }

    function test_refund_twice() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        assertEq(address(member).balance, 0);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Claim refund
        vm.prank(member);
        crowdfund.refund(payable(member));
        assertEq(address(member).balance, 2 ether);
        assertEq(address(party).balance, 0);

        // Try to claim refund again
        vm.prank(member);
        crowdfund.refund(payable(member));
        // Check balance unchanged
        assertEq(address(member).balance, 2 ether);
        assertEq(address(party).balance, 0);
    }

    function test_batchRefund_works() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        address payable[] memory members = new address payable[](3);
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
        vm.prank(sender);
        crowdfund.batchRefund(members, true);

        for (uint256 i = 0; i < members.length; i++) {
            assertEq(address(members[i]).balance, 1 ether);
        }
    }

    function test_fundingSplit_contributionAndRefund() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");
        assertEq(address(member).balance, 0);
        assertEq(crowdfund.pendingVotingPower(member), 0.8 ether);

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        // Claim refund
        vm.prank(member);
        crowdfund.refund(payable(member));
        assertEq(address(member).balance, 1 ether);
        assertEq(address(party).balance, 0);
    }

    function test_sendFundingSplit_works() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        assertEq(address(party).balance, 0.8 ether);

        // Send funding split
        crowdfund.sendFundingSplit();

        assertEq(fundingSplitRecipient.balance, 0.2 ether);
    }

    function test_sendFundingSplit_canOnlySendWhenFinalized() public {
        address payable fundingSplitRecipient = payable(_randomAddress());
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

    function test_crowdfundCardTokenURI_whileCrowdfundActive() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

        string memory tokenURI = crowdfund.tokenURI(uint256(uint160(member)));

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function test_crowdfundCardTokenURI_whileCrowdfundWon() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Won);

        string memory tokenURI = crowdfund.tokenURI(uint256(uint160(member)));

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function test_crowdfundCardTokenURI_whileCrowdfundLost() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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
        crowdfund.contribute{ value: 1 ether }(member, "");

        skip(7 days);

        assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Lost);

        string memory tokenURI = crowdfund.tokenURI(uint256(uint160(member)));

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function test_crowdfundCardTokenURI_whileCrowdfundFinalized() public {
        ReraiseETHCrowdfund crowdfund = _createCrowdfund(
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

        address member = _randomAddress();
        vm.deal(member, 1 ether);

        // Contribute
        vm.prank(member);
        crowdfund.contribute{ value: 1 ether }(member, "");

        assertTrue(
            crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Finalized
        );

        string memory tokenURI = crowdfund.tokenURI(uint256(uint160(member)));

        _lintEncodedJSON(tokenURI);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }
}
