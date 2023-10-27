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
import "contracts/renderers/MetadataProvider.sol";

import "forge-std/Test.sol";
import "../TestUtils.sol";

contract CrowdfundFactoryTest is Test, TestUtils {
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
    ReraiseETHCrowdfund reraiseETHCrowdfund = new ReraiseETHCrowdfund(globals);
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

    function testCreateAuctionCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomBps <= 1e4);

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
                name: randomStr,
                symbol: randomStr,
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId,
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                maximumBid: randomUint96,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                onlyHostCanBid: false,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: randomBool,
                    allowArbCallsToSpendPartyEth: randomBool,
                    allowOperators: randomBool,
                    distributionsRequireVote: randomBool
                })
            });

        vm.deal(address(this), randomUint40);
        AuctionCrowdfund inst = partyCrowdfundFactory.createAuctionCrowdfund{ value: randomUint40 }(
            auctionCrowdfund,
            opts,
            createGateCallData
        );

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
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateRollingAuctionCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomBps <= 1e4);

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
                name: randomStr,
                symbol: randomStr,
                customizationPresetId: 0,
                auctionId: auctionId,
                market: IMarketWrapper(market),
                nftContract: nftContract,
                nftTokenId: tokenId,
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                maximumBid: randomUint96,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                onlyHostCanBid: false,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: randomBool,
                    allowArbCallsToSpendPartyEth: randomBool,
                    allowOperators: randomBool,
                    distributionsRequireVote: randomBool
                })
            });

        vm.deal(address(this), randomUint40);
        RollingAuctionCrowdfund inst = partyCrowdfundFactory.createRollingAuctionCrowdfund{
            value: randomUint40
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
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
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

    function testCreateBuyCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps
    ) external {
        vm.assume(randomBps <= 1e4);

        // Create an NFT.
        DummyERC721 nftContract = new DummyERC721();
        uint256 tokenId = nftContract.mint(address(this));

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts;
        BuyCrowdfund.BuyCrowdfundOptions memory opts = BuyCrowdfund.BuyCrowdfundOptions({
            name: randomStr,
            symbol: randomStr,
            customizationPresetId: 0,
            nftContract: nftContract,
            nftTokenId: tokenId,
            // This is to avoid overflows when adding to `block.timestamp`.
            duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
            maximumPrice: randomUint96,
            splitRecipient: payable(_randomAddress()),
            splitBps: randomBps,
            initialContributor: _randomAddress(),
            initialDelegate: _randomAddress(),
            minContribution: 0,
            maxContribution: type(uint96).max,
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId,
            onlyHostCanBuy: false,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: proposalEngineOpts
        });

        vm.deal(address(this), randomUint40);
        BuyCrowdfund inst = partyCrowdfundFactory.createBuyCrowdfund{ value: randomUint40 }(
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
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateCollectionBuyCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomBps <= 1e4);

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
                name: randomStr,
                symbol: randomStr,
                customizationPresetId: 0,
                nftContract: nftContract,
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                maximumPrice: randomUint96,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: randomBool,
                    allowArbCallsToSpendPartyEth: randomBool,
                    allowOperators: randomBool,
                    distributionsRequireVote: randomBool
                })
            });

        vm.deal(address(this), randomUint40);
        CollectionBuyCrowdfund inst = partyCrowdfundFactory.createCollectionBuyCrowdfund{
            value: randomUint40
        }(collectionBuyCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateCollectionBatchBuyCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomBps <= 1e4);

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
                name: randomStr,
                symbol: randomStr,
                customizationPresetId: 0,
                nftContract: nftContract,
                nftTokenIdsMerkleRoot: keccak256(abi.encodePacked(_randomUint256())),
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                maximumPrice: randomUint96,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                    enableAddAuthorityProposal: randomBool,
                    allowArbCallsToSpendPartyEth: randomBool,
                    allowOperators: randomBool,
                    distributionsRequireVote: randomBool
                })
            });

        vm.deal(address(this), randomUint40);
        CollectionBatchBuyCrowdfund inst = partyCrowdfundFactory.createCollectionBatchBuyCrowdfund{
            value: randomUint40
        }(collectionBatchBuyCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
    }

    function testCreateInitialETHCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomUint40 != type(uint40).max); // Prevent overflow.
        vm.assume(randomUint96 != type(uint96).max); // Prevent overflow.
        vm.assume(randomUint96 != 0);
        vm.assume(randomBps <= 1e4);

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        uint96 initialContribution;
        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        {
            uint16 exchangeRateBps = randomBps != 0 ? randomBps : 1;
            // Only pass in initial contribution amount if it will not overflow.
            if (randomUint40 > type(uint96).max / exchangeRateBps) {
                // Only pass in initial contribution amount if results in non-zero voting power.
                if ((randomUint40 * exchangeRateBps) / 1e4 != 0) {
                    initialContribution = (randomUint40 * exchangeRateBps) / 1e4;
                }
            }

            crowdfundOpts = InitialETHCrowdfund.InitialETHCrowdfundOptions({
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                // Ensure that `minContribution` is less than initial contribution.
                minContribution: initialContribution < randomUint96
                    ? initialContribution
                    : randomUint96 - 1,
                // Ensure that `maxContribution` is greater than initial contribution.
                maxContribution: initialContribution > randomUint96
                    ? initialContribution
                    : randomUint96 + 1,
                disableContributingForExistingCard: randomBool,
                // Ensure that `minTotalContributions` is less than initial contribution.
                minTotalContributions: initialContribution < randomUint96
                    ? initialContribution
                    : randomUint96 - 1,
                // Ensure that `maxTotalContributions` is greater than initial contribution.
                maxTotalContributions: initialContribution > randomUint96
                    ? initialContribution + 1 // Ensure initial contribution does not finalize the crowdfund.
                    : randomUint96 + 1,
                exchangeRateBps: exchangeRateBps,
                fundingSplitBps: randomBps,
                fundingSplitRecipient: payable(_randomAddress()),
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId
            });
        }

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: randomStr,
            symbol: randomStr,
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: randomBool,
                allowArbCallsToSpendPartyEth: randomBool,
                allowOperators: randomBool,
                distributionsRequireVote: randomBool
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: new address[](0)
        });

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
        assertEq(inst.exchangeRateBps(), crowdfundOpts.exchangeRateBps);
        assertEq(inst.fundingSplitBps(), crowdfundOpts.fundingSplitBps);
        assertEq(inst.fundingSplitRecipient(), crowdfundOpts.fundingSplitRecipient);
        assertEq(inst.totalContributions(), initialContribution);
    }

    function testCreateInitialETHCrowdfundWithMetadata(
        bytes memory randomBytes,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomUint40 != type(uint40).max); // Prevent overflow.
        vm.assume(randomUint96 != type(uint96).max); // Prevent overflow.
        vm.assume(randomUint96 != 0);
        vm.assume(randomBps <= 1e4);

        uint96 initialContribution;
        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts;
        {
            uint16 exchangeRateBps = randomBps != 0 ? randomBps : 1;
            // Only pass in initial contribution amount if it will not overflow.
            if (randomUint40 > type(uint96).max / exchangeRateBps) {
                // Only pass in initial contribution amount if results in non-zero voting power.
                if ((randomUint40 * exchangeRateBps) / 1e4 != 0) {
                    initialContribution = (randomUint40 * exchangeRateBps) / 1e4;
                }
            }

            crowdfundOpts = InitialETHCrowdfund.InitialETHCrowdfundOptions({
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                // Ensure that `minContribution` is less than initial contribution.
                minContribution: initialContribution < randomUint96
                    ? initialContribution
                    : randomUint96 - 1,
                // Ensure that `maxContribution` is greater than initial contribution.
                maxContribution: initialContribution > randomUint96
                    ? initialContribution
                    : randomUint96 + 1,
                disableContributingForExistingCard: randomBool,
                // Ensure that `minTotalContributions` is less than initial contribution.
                minTotalContributions: initialContribution < randomUint96
                    ? initialContribution
                    : randomUint96 - 1,
                // Ensure that `maxTotalContributions` is greater than initial contribution.
                maxTotalContributions: initialContribution > randomUint96
                    ? initialContribution + 1 // Ensure initial contribution does not finalize the crowdfund.
                    : randomUint96 + 1,
                exchangeRateBps: exchangeRateBps,
                fundingSplitBps: randomBps,
                fundingSplitRecipient: payable(_randomAddress()),
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0
            });
        }

        InitialETHCrowdfund.ETHPartyOptions memory partyOpts = InitialETHCrowdfund.ETHPartyOptions({
            name: "Party",
            symbol: "PRTY",
            customizationPresetId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                partyImpl: party,
                partyFactory: partyFactory,
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngineOpts: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: randomBool,
                allowArbCallsToSpendPartyEth: randomBool,
                allowOperators: randomBool,
                distributionsRequireVote: randomBool
            }),
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0),
            rageQuitTimestamp: 0,
            authorities: new address[](0)
        });

        vm.deal(address(this), initialContribution);
        InitialETHCrowdfund inst = partyCrowdfundFactory.createInitialETHCrowdfundWithMetadata{
            value: initialContribution
        }(initialETHCrowdfund, crowdfundOpts, partyOpts, metadataProvider, randomBytes, "");

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
        assertEq(inst.exchangeRateBps(), crowdfundOpts.exchangeRateBps);
        assertEq(inst.fundingSplitBps(), crowdfundOpts.fundingSplitBps);
        assertEq(inst.fundingSplitRecipient(), crowdfundOpts.fundingSplitRecipient);
        assertEq(inst.totalContributions(), initialContribution);
        if (randomBytes.length != 0) {
            assertEq(
                address(metadataRegistry.getProvider(address(inst.party()))),
                address(metadataProvider)
            );
            assertEq(metadataProvider.getMetadata(address(inst.party()), 0), randomBytes);
        }
    }

    function testCreateReraiseETHCrowdfund(
        uint40 randomUint40,
        uint96 randomUint96,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomUint40 != type(uint40).max); // Prevent overflow.
        vm.assume(randomUint96 != type(uint96).max); // Prevent overflow.
        vm.assume(randomUint96 != 0);
        vm.assume(randomBps <= 1e4);

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        uint16 exchangeRateBps = randomBps != 0 ? randomBps : 1;
        uint96 initialContribution;
        // Only pass in initial contribution amount if it will not overflow.
        if (randomUint40 > type(uint96).max / exchangeRateBps) {
            // Only pass in initial contribution amount if results in non-zero voting power.
            if ((randomUint40 * exchangeRateBps) / 1e4 != 0) {
                initialContribution = (randomUint40 * exchangeRateBps) / 1e4;
            }
        }

        ETHCrowdfundBase.ETHCrowdfundOptions memory opts = ETHCrowdfundBase.ETHCrowdfundOptions({
            party: Party(payable(address(new MockParty()))),
            initialContributor: _randomAddress(),
            initialDelegate: _randomAddress(),
            // Ensure that `minContribution` is less than initial contribution.
            minContribution: initialContribution < randomUint96
                ? initialContribution
                : randomUint96 - 1,
            disableContributingForExistingCard: randomBool,
            // Ensure that `maxContribution` is greater than initial contribution.
            maxContribution: initialContribution > randomUint96
                ? initialContribution
                : randomUint96 + 1,
            // Ensure that `minTotalContributions` is less than initial contribution.
            minTotalContributions: initialContribution < randomUint96
                ? initialContribution
                : randomUint96 - 1,
            // Ensure that `maxTotalContributions` is greater than initial contribution.
            maxTotalContributions: initialContribution > randomUint96
                ? initialContribution + 1 // Ensure initial contribution does not finalize the crowdfund.
                : randomUint96 + 1,
            exchangeRateBps: exchangeRateBps,
            fundingSplitBps: randomBps,
            fundingSplitRecipient: payable(_randomAddress()),
            // This is to avoid overflows when adding to `block.timestamp`.
            duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId
        });

        vm.deal(address(this), initialContribution);
        ReraiseETHCrowdfund inst = partyCrowdfundFactory.createReraiseETHCrowdfund{
            value: initialContribution
        }(reraiseETHCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(address(inst.party()), address(opts.party));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.minContribution(), opts.minContribution);
        assertEq(inst.maxContribution(), opts.maxContribution);
        assertEq(
            inst.disableContributingForExistingCard(),
            opts.disableContributingForExistingCard
        );
        assertEq(inst.minTotalContributions(), opts.minTotalContributions);
        assertEq(inst.maxTotalContributions(), opts.maxTotalContributions);
        assertEq(inst.exchangeRateBps(), opts.exchangeRateBps);
        assertEq(inst.fundingSplitBps(), opts.fundingSplitBps);
        assertEq(inst.fundingSplitRecipient(), opts.fundingSplitRecipient);
        assertEq(inst.totalContributions(), initialContribution);
    }

    function testCreateCollectionBatchBuyCrowdfund(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps
    ) external {
        vm.assume(randomBps <= 1e4);

        // Create an NFT.
        DummyERC721 nftContract = new DummyERC721();

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts;
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions
            memory opts = CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions({
                name: randomStr,
                symbol: randomStr,
                customizationPresetId: 0,
                nftContract: nftContract,
                nftTokenIdsMerkleRoot: keccak256(abi.encodePacked(_randomUint256())),
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                maximumPrice: randomUint96,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    partyImpl: party,
                    partyFactory: partyFactory,
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                }),
                proposalEngineOpts: proposalEngineOpts
            });

        vm.deal(address(this), randomUint40);
        CollectionBatchBuyCrowdfund inst = partyCrowdfundFactory.createCollectionBatchBuyCrowdfund{
            value: randomUint40
        }(collectionBatchBuyCrowdfund, opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , , ) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId : bytes12(uint96(1))
        );
        assertEq(inst.partyOptsHash(), _hashOpts(opts.governanceOpts, opts.proposalEngineOpts));
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
}

contract MockRendererStorage {
    /// @notice Customization preset used by a crowdfund or party instance.
    mapping(address => uint256) public getPresetFor;
}
