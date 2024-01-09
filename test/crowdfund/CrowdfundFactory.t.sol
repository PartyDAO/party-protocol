// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/party/Party.sol";
import "contracts/party/PartyFactory.sol";
import "contracts/crowdfund/CrowdfundFactory.sol";
import "contracts/crowdfund/AuctionCrowdfund.sol";
import "contracts/market-wrapper/IMarketWrapper.sol";
import "contracts/crowdfund/Crowdfund.sol";
import "contracts/gatekeepers/AllowListGateKeeper.sol";
import "contracts/gatekeepers/TokenGateKeeper.sol";
import "contracts/tokens/IERC721.sol";
import "./MockMarketWrapper.sol";
import "contracts/globals/Globals.sol";
import "contracts/globals/LibGlobals.sol";
import "contracts/renderers/MetadataRegistry.sol";
import { ProposalStorage } from "contracts/proposals/ProposalStorage.sol";
import "contracts/renderers/MetadataProvider.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { LibSafeCast } from "contracts/utils/LibSafeCast.sol";

import "forge-std/Test.sol";
import "../TestUtils.sol";

contract CrowdfundFactoryTest is Test, TestUtils {
    using FixedPointMathLib for uint40;
    using FixedPointMathLib for uint256;
    using LibSafeCast for uint256;

    Globals globals = new Globals(address(this));
    CrowdfundFactory partyCrowdfundFactory = new CrowdfundFactory();
    PartyFactory partyFactory = new PartyFactory(globals);
    Party party = new Party(globals);
    MockMarketWrapper market = new MockMarketWrapper();
    AuctionCrowdfund auctionCrowdfund = new AuctionCrowdfund(globals);
    RollingAuctionCrowdfund rollingAuctionCrowdfund = new RollingAuctionCrowdfund(globals);
    BuyCrowdfund buyCrowdfund = new BuyCrowdfund(globals);
    CollectionBuyCrowdfund collectionBuyCrowdfund = new CollectionBuyCrowdfund(globals);
    CollectionBatchBuyCrowdfund collectionBatchBuyCrowdfund =
        new CollectionBatchBuyCrowdfund(globals);
    InitialETHCrowdfund initialETHCrowdfund = new InitialETHCrowdfund(globals);
    AllowListGateKeeper allowListGateKeeper = new AllowListGateKeeper(address(0));
    TokenGateKeeper tokenGateKeeper = new TokenGateKeeper(address(0));
    MetadataRegistry metadataRegistry =
        new MetadataRegistry(globals, _toAddressArray(address(partyFactory)));
    MetadataProvider metadataProvider = new MetadataProvider(globals);

    event Contributed(
        address sender,
        address contributor,
        uint256 amount,
        uint256 previousTotalContributions
    );
    event DelegateUpdated(
        address sender,
        address contributor,
        address oldDelegate,
        address newDelegate
    );

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_METADATA_REGISTRY, address(metadataRegistry));
        globals.setAddress(LibGlobals.GLOBAL_RENDERER_STORAGE, address(new MockRendererStorage()));
    }

    function _hashOpts(
        Crowdfund.FixedGovernanceOpts memory govOpts,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts
    ) internal pure returns (bytes32 h) {
        return keccak256(abi.encode(govOpts, proposalEngineOpts));
    }

    function _randomGateKeeper()
        internal
        view
        returns (IGateKeeper gk, bytes12 gkId, bytes memory createGateCallData)
    {
        uint256 x = _randomRange(0, 2);

        if (x == 0) {
            // Use `AllowListGateKeeper`.
            createGateCallData = abi.encodeCall(AllowListGateKeeper.createGate, (_randomBytes32()));
            return (IGateKeeper(address(allowListGateKeeper)), bytes12(0), createGateCallData);
        }
        if (x == 1) {
            // Use `TokenGateKeeper`.
            createGateCallData = abi.encodeCall(
                TokenGateKeeper.createGate,
                (Token(_randomAddress()), _randomUint256())
            );
            return (IGateKeeper(address(tokenGateKeeper)), bytes12(0), createGateCallData);
        }
        if (x == 2) {
            // Use no gatekeeper.
            return (IGateKeeper(address(0)), bytes12(_randomBytes32()), createGateCallData);
        }
    }

    function testCreateAuctionCrowdfund() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts = AuctionCrowdfundBase
            .AuctionCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId,
                duration: 7 days,
                maximumBid: 10 ether,
                splitRecipient: payable(_randomAddress()),
                splitBps: 0.25e4,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0.01 ether,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                onlyHostCanBid: true,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: 2 days,
                    executionDelay: 1 days,
                    passThresholdBps: 0.5e4,
                    feeBps: 0.1e4,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: true,
                    allowArbCallsToSpendPartyEth: true,
                    allowOperators: true,
                    distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
                })
            });

        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        AuctionCrowdfund inst = partyCrowdfundFactory.createAuctionCrowdfund{
            value: initialContribution
        }(auctionCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(inst.auctionId(), opts.auctionId);
        assertEq(address(inst.market()), address(opts.market));
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.nftTokenId(), opts.nftTokenId);
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumBid(), opts.maximumBid);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(initialContribution));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, initialContribution);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateRollingAuctionCrowdfund() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts = AuctionCrowdfundBase
            .AuctionCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId,
                duration: 7 days,
                maximumBid: 10 ether,
                splitRecipient: payable(_randomAddress()),
                splitBps: 0.25e4,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0.01 ether,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                onlyHostCanBid: true,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: 2 days,
                    executionDelay: 1 days,
                    passThresholdBps: 0.5e4,
                    feeBps: 0.1e4,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: true,
                    allowArbCallsToSpendPartyEth: true,
                    allowOperators: true,
                    distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
                })
            });

        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        RollingAuctionCrowdfund inst = partyCrowdfundFactory.createRollingAuctionCrowdfund{
            value: initialContribution
        }(rollingAuctionCrowdfund, opts, _randomBytes32(), createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(inst.auctionId(), opts.auctionId);
        assertEq(address(inst.market()), address(opts.market));
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.nftTokenId(), opts.nftTokenId);
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumBid(), opts.maximumBid);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(initialContribution));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, initialContribution);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateAuctionCrowdfundWithInvalidAuctionId() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts;
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts = AuctionCrowdfundBase
            .AuctionCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                auctionId: auctionId + 1,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId,
                duration: 7 days,
                maximumBid: type(uint96).max,
                splitRecipient: payable(address(0)),
                splitBps: 0,
                initialContributor: address(0),
                initialDelegate: address(0),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0,
                onlyHostCanBid: false,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(address(this)),
                    voteDuration: 3 days,
                    executionDelay: 1 days,
                    passThresholdBps: 51e2,
                    feeBps: 0,
                    feeRecipient: payable(address(0))
                }),
                proposalEngineOpts: proposalEngineOpts
            });

        vm.expectRevert(AuctionCrowdfundBase.InvalidAuctionIdError.selector);
        partyCrowdfundFactory.createAuctionCrowdfund(auctionCrowdfund, opts, "");
    }

    function testCreateAuctionCrowdfundWithInvalidNftContract() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);

        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts;
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts = AuctionCrowdfundBase
            .AuctionCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: IERC721(address(0)),
                nftTokenId: tokenId,
                duration: 7 days,
                maximumBid: type(uint96).max,
                splitRecipient: payable(address(0)),
                splitBps: 0,
                initialContributor: address(0),
                initialDelegate: address(0),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0,
                onlyHostCanBid: false,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(address(this)),
                    voteDuration: 3 days,
                    executionDelay: 1 days,
                    passThresholdBps: 51e2,
                    feeBps: 0,
                    feeRecipient: payable(address(0))
                }),
                proposalEngineOpts: proposalEngineOpts
            });

        vm.expectRevert(AuctionCrowdfundBase.InvalidAuctionIdError.selector);
        partyCrowdfundFactory.createAuctionCrowdfund(auctionCrowdfund, opts, "");
    }

    function testCreateAuctionCrowdfundWithInvalidTokenId() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts;
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts = AuctionCrowdfundBase
            .AuctionCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId + 1,
                duration: 7 days,
                maximumBid: type(uint96).max,
                splitRecipient: payable(address(0)),
                splitBps: 0,
                initialContributor: address(0),
                initialDelegate: address(0),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0,
                onlyHostCanBid: false,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(address(this)),
                    voteDuration: 3 days,
                    executionDelay: 1 days,
                    passThresholdBps: 51e2,
                    feeBps: 0,
                    feeRecipient: payable(address(0))
                }),
                proposalEngineOpts: proposalEngineOpts
            });

        vm.expectRevert(AuctionCrowdfundBase.InvalidAuctionIdError.selector);
        partyCrowdfundFactory.createAuctionCrowdfund(auctionCrowdfund, opts, "");
    }

    function testCreateBuyCrowdfund() external {
        // Create an NFT.
        DummyERC721 nftContract = new DummyERC721();
        uint256 tokenId = nftContract.mint(address(this));

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        BuyCrowdfund.BuyCrowdfundOptions memory opts = BuyCrowdfund.BuyCrowdfundOptions({
            name: "name",
            symbol: "symbol",
            customizationPresetId: 0,
            nftContract: nftContract,
            nftTokenId: tokenId,
            duration: 7 days,
            maximumPrice: 10 ether,
            splitRecipient: payable(_randomAddress()),
            splitBps: 0.25e4,
            initialContributor: _randomAddress(),
            initialDelegate: _randomAddress(),
            minContribution: 0,
            maxContribution: type(uint96).max,
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId,
            onlyHostCanBuy: true,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: 2 days,
                executionDelay: 1 days,
                passThresholdBps: 0.5e4,
                feeBps: 0.1e4,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: true,
                allowArbCallsToSpendPartyEth: true,
                allowOperators: true,
                distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
            })
        });

        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        BuyCrowdfund inst = partyCrowdfundFactory.createBuyCrowdfund{ value: initialContribution }(
            buyCrowdfund,
            opts,
            createGateCallData
        );

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.nftTokenId(), opts.nftTokenId);
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(initialContribution));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, initialContribution);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateCollectionBuyCrowdfund() external {
        // Create an NFT.
        DummyERC721 nftContract = new DummyERC721();

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions memory opts = CollectionBuyCrowdfund
            .CollectionBuyCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                nftContract: nftContract,
                duration: 7 days,
                maximumPrice: 10 ether,
                splitRecipient: payable(_randomAddress()),
                splitBps: 0.25e4,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 1 ether,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: 2 days,
                    executionDelay: 1 days,
                    passThresholdBps: 0.5e4,
                    feeBps: 0.1e4,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: true,
                    allowArbCallsToSpendPartyEth: true,
                    allowOperators: true,
                    distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
                })
            });

        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        CollectionBuyCrowdfund inst = partyCrowdfundFactory.createCollectionBuyCrowdfund{
            value: initialContribution
        }(collectionBuyCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(initialContribution));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, initialContribution);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateCollectionBatchBuyCrowdfund() external {
        // Create an NFT.
        DummyERC721 nftContract = new DummyERC721();

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions
            memory opts = CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                nftContract: nftContract,
                nftTokenIdsMerkleRoot: keccak256(abi.encodePacked(_randomUint256())),
                duration: 7 days,
                maximumPrice: 10 ether,
                splitRecipient: payable(_randomAddress()),
                splitBps: 0.25e4,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 1 ether,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: 2 days,
                    executionDelay: 1 days,
                    passThresholdBps: 0.5e4,
                    feeBps: 0.1e4,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: true,
                    allowArbCallsToSpendPartyEth: true,
                    allowOperators: true,
                    distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
                })
            });

        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        CollectionBatchBuyCrowdfund inst = partyCrowdfundFactory.createCollectionBatchBuyCrowdfund{
            value: initialContribution
        }(collectionBatchBuyCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(initialContribution));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, initialContribution);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateInitialETHCrowdfund() external {
        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts = InitialETHCrowdfund
            .InitialETHCrowdfundOptions({
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 1 ether,
                maxContribution: type(uint96).max,
                disableContributingForExistingCard: true,
                minTotalContributions: 10 ether,
                maxTotalContributions: type(uint96).max,
                exchangeRate: 1e18,
                fundingSplitBps: 0.25e4,
                fundingSplitRecipient: payable(_randomAddress()),
                duration: 7 days,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId
            });

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: "name",
            symbol: "symbol",
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: 2 days,
                executionDelay: 1 days,
                passThresholdBps: 0.5e4,
                feeBps: 0.1e4,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: true,
                allowArbCallsToSpendPartyEth: true,
                allowOperators: true,
                distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: new address[](0)
        });

        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        InitialETHCrowdfund inst = partyCrowdfundFactory.createInitialETHCrowdfund{
            value: initialContribution
        }(initialETHCrowdfund, crowdfundOpts, partyOpts, createGateCallData);
        Party party_ = inst.party();

        // Check that value are initialized to what we expect.
        assertEq(party_.name(), partyOpts.name);
        assertEq(party_.symbol(), partyOpts.symbol);
        assertEq(inst.expiry(), uint40(block.timestamp + crowdfundOpts.duration));
        assertEq(inst.minContribution(), crowdfundOpts.minContribution);
        assertEq(inst.maxContribution(), crowdfundOpts.maxContribution);
        assertEq(
            inst.disableContributingForExistingCard(),
            crowdfundOpts.disableContributingForExistingCard
        );
        assertEq(inst.minTotalContributions(), crowdfundOpts.minTotalContributions);
        assertEq(inst.maxTotalContributions(), crowdfundOpts.maxTotalContributions);
        assertEq(inst.exchangeRate(), crowdfundOpts.exchangeRate);
        assertEq(inst.fundingSplitBps(), crowdfundOpts.fundingSplitBps);
        assertEq(inst.fundingSplitRecipient(), crowdfundOpts.fundingSplitRecipient);
        assertEq(inst.totalContributions(), initialContribution);
    }

    function testCreateInitialETHCrowdfundWithMetadata() external {
        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts = InitialETHCrowdfund
            .InitialETHCrowdfundOptions({
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 1 ether,
                maxContribution: type(uint96).max,
                disableContributingForExistingCard: true,
                minTotalContributions: 10 ether,
                maxTotalContributions: type(uint96).max,
                exchangeRate: 1e18,
                fundingSplitBps: 0.25e4,
                fundingSplitRecipient: payable(_randomAddress()),
                duration: 7 days,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId
            });

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: "name",
            symbol: "symbol",
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: 2 days,
                executionDelay: 1 days,
                passThresholdBps: 0.5e4,
                feeBps: 0.1e4,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: true,
                allowArbCallsToSpendPartyEth: true,
                allowOperators: true,
                distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: new address[](0)
        });

        bytes memory customMetadata = abi.encodePacked(_randomBytes32());
        uint256 initialContribution = 1 ether;
        vm.deal(address(this), initialContribution);
        InitialETHCrowdfund inst = partyCrowdfundFactory.createInitialETHCrowdfundWithMetadata{
            value: initialContribution
        }(
            initialETHCrowdfund,
            crowdfundOpts,
            partyOpts,
            metadataProvider,
            customMetadata,
            createGateCallData
        );

        // Check that value are initialized to what we expect.
        assertEq(inst.expiry(), uint40(block.timestamp + crowdfundOpts.duration));
        assertEq(inst.minContribution(), crowdfundOpts.minContribution);
        assertEq(inst.maxContribution(), crowdfundOpts.maxContribution);
        assertEq(
            inst.disableContributingForExistingCard(),
            crowdfundOpts.disableContributingForExistingCard
        );
        assertEq(inst.minTotalContributions(), crowdfundOpts.minTotalContributions);
        assertEq(inst.maxTotalContributions(), crowdfundOpts.maxTotalContributions);
        assertEq(inst.exchangeRate(), crowdfundOpts.exchangeRate);
        assertEq(inst.fundingSplitBps(), crowdfundOpts.fundingSplitBps);
        assertEq(inst.fundingSplitRecipient(), crowdfundOpts.fundingSplitRecipient);
        assertEq(inst.totalContributions(), initialContribution);
        assertEq(
            address(metadataRegistry.getProvider(address(inst.party()))),
            address(metadataProvider)
        );
        assertEq(metadataProvider.getMetadata(address(inst.party()), 0), customMetadata);
    }

    function testCreateInitialETHCrowdfundWithInvalidMinMaxTotalContributions() external {
        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        uint96 minTotalContributions = 9 ether;
        uint96 maxTotalContributions = 10 ether;
        uint96 minContribution = 2 ether;

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts = InitialETHCrowdfund
            .InitialETHCrowdfundOptions({
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: minContribution,
                maxContribution: type(uint96).max,
                disableContributingForExistingCard: true,
                minTotalContributions: minTotalContributions,
                maxTotalContributions: maxTotalContributions,
                exchangeRate: 1e18,
                fundingSplitBps: 0.25e4,
                fundingSplitRecipient: payable(_randomAddress()),
                duration: 7 days,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId
            });

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: "name",
            symbol: "symbol",
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: 2 days,
                executionDelay: 1 days,
                passThresholdBps: 0.5e4,
                feeBps: 0.1e4,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: true,
                allowArbCallsToSpendPartyEth: true,
                allowOperators: true,
                distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: new address[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ETHCrowdfundBase.MinMaxDifferenceTooSmall.selector,
                minTotalContributions,
                maxTotalContributions
            )
        );
        partyCrowdfundFactory.createInitialETHCrowdfund(
            initialETHCrowdfund,
            crowdfundOpts,
            partyOpts,
            createGateCallData
        );
    }

    function testCreateInitialETHCrowdfundWithInvalidMinContributions() external {
        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts = InitialETHCrowdfund
            .InitialETHCrowdfundOptions({
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 1,
                maxContribution: type(uint96).max,
                disableContributingForExistingCard: true,
                minTotalContributions: 10 ether,
                maxTotalContributions: type(uint96).max,
                exchangeRate: 1e18,
                fundingSplitBps: 0.25e4,
                fundingSplitRecipient: payable(_randomAddress()),
                duration: 7 days,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId
            });

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: "name",
            symbol: "symbol",
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: 2 days,
                executionDelay: 1 days,
                passThresholdBps: 0.5e4,
                feeBps: 0.1e4,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: true,
                allowArbCallsToSpendPartyEth: true,
                allowOperators: true,
                distributionsConfig: ProposalStorage.DistributionsConfig.AllowedWithVote
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: new address[](0)
        });

        vm.expectRevert(ETHCrowdfundBase.ZeroVotingPowerError.selector);
        partyCrowdfundFactory.createInitialETHCrowdfund(
            initialETHCrowdfund,
            crowdfundOpts,
            partyOpts,
            createGateCallData
        );
    }

    function testCreatePartyWithInvalidBps(
        uint16 splitBps,
        uint16 passThresholdBps,
        uint16 feeBps
    ) external {
        // At least one of the BPs must be invalid for this test to work.
        vm.assume(splitBps > 1e4 || passThresholdBps > 1e4 || feeBps > 1e4);

        // Create an auction.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts;
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts = AuctionCrowdfundBase
            .AuctionCrowdfundOptions({
                name: "name",
                symbol: "symbol",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId,
                duration: 7 days,
                maximumBid: type(uint96).max,
                splitRecipient: payable(address(0)),
                splitBps: splitBps,
                initialContributor: address(0),
                initialDelegate: address(0),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0,
                onlyHostCanBid: false,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(address(this)),
                    voteDuration: 3 days,
                    executionDelay: 1 days,
                    passThresholdBps: passThresholdBps,
                    feeBps: feeBps,
                    feeRecipient: payable(address(0))
                }),
                proposalEngineOpts: proposalEngineOpts
            });

        uint16 invalidBps;
        if (feeBps > 1e4) {
            invalidBps = feeBps;
        } else if (passThresholdBps > 1e4) {
            invalidBps = passThresholdBps;
        } else {
            invalidBps = splitBps;
        }
        vm.expectRevert(abi.encodeWithSelector(Crowdfund.InvalidBpsError.selector, invalidBps));
        partyCrowdfundFactory.createAuctionCrowdfund(auctionCrowdfund, opts, "");
    }
}

contract MockParty {
    string public name;
    string public symbol;

    function increaseTotalVotingPower(uint96 amount) external {}

    receive() external payable {}
}

contract MockRendererStorage {
    /// @notice Customization preset used by a crowdfund or party instance.
    mapping(address => uint256) public getPresetFor;
}
