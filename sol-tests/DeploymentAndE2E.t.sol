// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/party/PartyFactory.sol";
import "contracts/crowdfund/CrowdfundFactory.sol";
import "contracts/crowdfund/AuctionCrowdfund.sol";
import "contracts/market-wrapper/IMarketWrapper.sol";
import "contracts/crowdfund/Crowdfund.sol";
import "contracts/gatekeepers/AllowListGateKeeper.sol";
import "contracts/gatekeepers/TokenGateKeeper.sol";
import "contracts/tokens/IERC721.sol";
import "contracts/globals/Globals.sol";
import "contracts/globals/LibGlobals.sol";
import "contracts/proposals/ProposalExecutionEngine.sol";
import "contracts/vendor/markets/IFoundationMarket.sol";
import "contracts/vendor/markets/INounsAuctionHouse.sol";
import "./crowdfund/MockMarketWrapper.sol";

import "./TestUtils.sol";
import "../deploy/deploy.sol";
import "./proposals/OpenseaTestUtils.sol";

contract DeploymentAndE2ETest is Deploy, OpenseaTestUtils, TestUtils {
    enum CrowdfundType {
        None,
        Auction,
        Buy,
        CollectionBuy
    }

    enum MarketType {
        None,
        Nouns,
        Foundation,
        Zora
    }

    ICrowdfund crowdfund;
    CrowdfundType crowdfundType;
    MarketType marketType;
    Crowdfund.FixedGovernanceOpts govOpts;

    Party party;
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;
    DummyERC721 token;

    IMarketWrapper market;
    IERC721 nftContract;
    uint256 auctionId;
    uint256 tokenId;
    uint256 reservePrice;

    LibDeployConstants.DeployConstants deployConstants = LibDeployConstants.fork();

    INounsAuctionHouse nouns = INounsAuctionHouse(0x830BD73E4184ceF73443C15111a1DF14e495C706);
    IFoundationMarket foundation = IFoundationMarket(0xcDA72070E455bb31C7690a170224Ce43623d0B6f);
    IZoraAuctionHouse zora = IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    IFractionalV1VaultFactory fractional = IFractionalV1VaultFactory(0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63);

    address payable alice;
    address payable bob;
    address payable charlie;

    constructor() OpenseaTestUtils(IOpenseaExchange(deployConstants.seaportExchangeAddress)) {}

    function setUp() public onlyForked {
        // Setup deployed contracts on forked mainnet.
        run(deployConstants);

        // Setup governance options to use when creating crowdfunds.
        govOpts.hosts = _toAddressArray(alice);
        govOpts.voteDuration = 2 days;
        govOpts.executionDelay = 0;
        govOpts.passThresholdBps = 0.51e4;
        govOpts.feeBps = uint16(deployConstants.partyDaoDistributionSplitBps);
        govOpts.feeRecipient = payable(deployConstants.partyDaoMultisig);

        // Setup users.
        alice = payable(_randomAddress());
        bob = payable(_randomAddress());
        charlie = payable(_randomAddress());
        vm.label(address(alice), "alice");
        vm.label(address(bob), "bob");
        vm.label(address(charlie), "charlie");
        vm.label(address(proposalEngineImpl), "proposalEngine");
    }

    function testForked_withDeployedContracts_E2E() external onlyForked {
        // Go through full crowdfund lifecycle with every crowdfund type.
        for (uint256 c = 1; c < uint8(type(CrowdfundType).max) + 1; c++) {
            crowdfundType = CrowdfundType(c);

            if (crowdfundType == CrowdfundType.Auction) {
                // Win auction crowdfund on every supported market.
                for (uint256 m = 1; m < uint8(type(MarketType).max) + 1; m++) {
                    marketType = MarketType(m);

                    _createCrowdfund();

                    _winCrowdfundAndCreateParty();
                }
            } else {
                _createCrowdfund();

                _winCrowdfundAndCreateParty();
            }
        }

        // Have party go through full proposal lifecycle for every proposal type.
        // Then create and claim a distribution afterwards, if applicable, for every distribution type.
        for (uint256 p = 1; p < uint8(type(ProposalExecutionEngine.ProposalType).max); p++) {
            ProposalExecutionEngine.ProposalType proposalType =
                ProposalExecutionEngine.ProposalType(p);

            // Execute proposal from start to finish.
            address tokenToDistribute = _createAndExecuteProposal(proposalType);

            // Distribute token to party members and have each of them claim (including PartyDAO multisig).
            if (tokenToDistribute != address(0)) _distributeAndClaimTokens(tokenToDistribute);
        }
    }

    function _createCrowdfund() internal {
        string memory name = "Test Crowdfund";
        string memory symbol = "TEST";
        uint40 duration = 1 days;
        uint96 maximumPrice = type(uint96).max;
        address payable splitRecipient = payable(address(0));
        uint16 splitBps = 0;
        address initialContributor = address(this);
        address initialDelegate = address(this);
        IGateKeeper gateKeeper = IGateKeeper(address(0));
        bytes12 gateKeeperId = 0;

        if (crowdfundType == CrowdfundType.Auction) {
            // Create `AuctionCrowdfund`
            _createAuction();
            AuctionCrowdfund _crowdfund = partyCrowdfundFactory
                .createAuctionCrowdfund(
                    AuctionCrowdfund.AuctionCrowdfundOptions({
                        name: name,
                        symbol: symbol,
                        auctionId: auctionId,
                        market: market,
                        nftContract: nftContract,
                        nftTokenId: tokenId,
                        duration: duration,
                        maximumBid: maximumPrice,
                        splitRecipient: splitRecipient,
                        splitBps: splitBps,
                        initialContributor: initialContributor,
                        initialDelegate: initialDelegate,
                        gateKeeper: gateKeeper,
                        gateKeeperId: gateKeeperId,
                        governanceOpts: govOpts
                    }),
                    ""
                );
            crowdfund = ICrowdfund(address(_crowdfund));
        } else if (crowdfundType == CrowdfundType.Buy) {
            // Create `BuyCrowdfund`
            DummyERC721 _nftContract = new DummyERC721();
            tokenId = _nftContract.lastId() + 1;
            nftContract = IERC721(address(_nftContract));
            reservePrice = _randomRange(1 ether, 1000 ether);
            BuyCrowdfund _crowdfund = partyCrowdfundFactory.createBuyCrowdfund(
                BuyCrowdfund.BuyCrowdfundOptions({
                    name: name,
                    symbol: symbol,
                    nftContract: nftContract,
                    nftTokenId: tokenId,
                    duration: duration,
                    maximumPrice: maximumPrice,
                    splitRecipient: splitRecipient,
                    splitBps: splitBps,
                    initialContributor: initialContributor,
                    initialDelegate: initialDelegate,
                    gateKeeper: gateKeeper,
                    gateKeeperId: gateKeeperId,
                    governanceOpts: govOpts
                }),
                ""
            );
            crowdfund = ICrowdfund(address(_crowdfund));
        } else if (crowdfundType == CrowdfundType.CollectionBuy) {
            // Create `CollectionBuyCrowdfund`
            DummyERC721 _nftContract = new DummyERC721();
            tokenId = _nftContract.lastId() + 1;
            nftContract = IERC721(address(_nftContract));
            reservePrice = _randomRange(1 ether, 1000 ether);
            CollectionBuyCrowdfund _crowdfund = partyCrowdfundFactory
                .createCollectionBuyCrowdfund(
                    CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions({
                        name: name,
                        symbol: symbol,
                        nftContract: nftContract,
                        duration: duration,
                        maximumPrice: maximumPrice,
                        splitRecipient: splitRecipient,
                        splitBps: splitBps,
                        initialContributor: initialContributor,
                        initialDelegate: initialDelegate,
                        gateKeeper: gateKeeper,
                        gateKeeperId: gateKeeperId,
                        governanceOpts: govOpts
                    }),
                    ""
                );
            crowdfund = ICrowdfund(address(_crowdfund));
        } else {
            revert("Invalid crowdfund type");
        }

        vm.label(address(crowdfund), "crowdfund");

        // Users contribute to the crowdfund.
        _contribute(alice, _randomRange(0.1 ether, reservePrice * 2 / 3));
        _contribute(bob, _randomRange(0.1 ether, reservePrice - crowdfund.totalContributions()));
        _contribute(charlie, reservePrice - crowdfund.totalContributions() + 1 ether);

    }

    function _createAuction() internal {
        if (marketType == MarketType.Nouns) {
            // Create Nouns auction
            market = IMarketWrapper(0x9319DAd8736D752C5c72DB229f8e1b280DC80ab1);
            nftContract = nouns.nouns();
            (, uint256 amount, , , address payable bidder, ) = nouns.auction();
            reservePrice = bidder == address(0) ? nouns.reservePrice() : amount;
            (tokenId, , , , , ) = nouns.auction();
            auctionId = tokenId;
        } else if (marketType == MarketType.Foundation) {
            // Create Foundation auction
            market = IMarketWrapper(0x96e5b0519983f2f984324b926e6d28C3A4Eb92A1);
            DummyERC721 _nftContract = new DummyERC721();
            tokenId = _nftContract.mint(address(this));
            nftContract = IERC721(address(_nftContract));
            nftContract.approve(address(foundation), tokenId);
            reservePrice = _randomRange(1 ether, 1000 ether);
            foundation.createReserveAuction(
                address(nftContract),
                tokenId,
                reservePrice
            );
            auctionId = foundation.getReserveAuctionIdFor(
                address(nftContract),
                tokenId
            );
        } else if (marketType == MarketType.Zora) {
            // Create Zora auction
            market = IMarketWrapper(0x11c07cE1315a3b92C9755F90cDF40B04b88c5731);
            DummyERC721 _nftContract = new DummyERC721();
            tokenId = _nftContract.mint(address(this));
            nftContract = IERC721(address(_nftContract));
            nftContract.approve(address(zora), tokenId);
            reservePrice = _randomRange(1 ether, 1000 ether);
            auctionId = zora.createAuction(
                tokenId,
                nftContract,
                1 days, // Duration
                reservePrice,
                payable(address(0)), // Curator
                0, // Curator fee %
                IERC20(address(0)) // Indicates ETH sale
            );
        } else {
            revert("Invalid auction type");
        }
    }

    function _winCrowdfundAndCreateParty() internal {
        if (crowdfundType == CrowdfundType.Auction) {
            crowdfund.bid();

            // Skip to end of auction.
            skip(1 days + 1);

            party = crowdfund.finalize(govOpts);
        } else if (crowdfundType == CrowdfundType.Buy) {
            party = crowdfund.buy(
                payable(address(nftContract)),
                uint96(reservePrice),
                abi.encodeWithSelector(
                    DummyERC721.mint.selector,
                    address(crowdfund)
                ),
                govOpts
            );
        } else if (crowdfundType == CrowdfundType.CollectionBuy) {
            vm.prank(govOpts.hosts[0]);
            party = crowdfund.buy(
                tokenId,
                payable(address(nftContract)),
                uint96(reservePrice),
                abi.encodeWithSelector(
                    DummyERC721.mint.selector,
                    address(crowdfund)
                ),
                govOpts
            );
        }

        vm.label(address(party), "party");

        assertEq(nftContract.ownerOf(tokenId), address(party));
        assertEq(address(crowdfund.party()), address(party));

        // Set precious tokens list.
        IERC721[] memory _preciousTokens = new IERC721[](1);
        _preciousTokens[0] = nftContract;
        uint256[] memory _preciousTokenIds = new uint256[](1);
        _preciousTokenIds[0] = tokenId;
        preciousTokens = _preciousTokens;
        preciousTokenIds = _preciousTokenIds;

        // Burn all contributors' crowdfund NFTs for governance NFTs
        address payable[] memory contributors = new address payable[](3);
        contributors[0] = alice;
        contributors[1] = bob;
        contributors[2] = charlie;

        crowdfund.batchBurn(contributors);

        for (uint256 i; i < contributors.length; i++) {
            assertEq(party.balanceOf(contributors[i]), 1);
        }
    }

    function _contribute(address payable contributor, uint256 amount) internal {
        uint256 totalContributionsBefore = crowdfund.totalContributions();
        vm.deal(contributor, amount);
        vm.prank(contributor);
        crowdfund.contribute{ value: amount }(contributor, "");
        assertEq(crowdfund.totalContributions(), totalContributionsBefore + amount);
        assertEq(crowdfund.balanceOf(contributor), 1);
    }


    function _createAndExecuteProposal(ProposalExecutionEngine.ProposalType proposalType)
        internal
        returns (address tokenToDistribute)
    {
        bytes memory proposalData;
        if (proposalType == ProposalExecutionEngine.ProposalType.ListOnOpensea) {
            token = new DummyERC721();
            proposalData = abi.encodeWithSelector(
                bytes4(uint32(proposalType)),
                ListOnOpenseaProposal.OpenseaProposalData({
                    listPrice: 1 ether,
                    duration: 1 days,
                    token: token,
                    tokenId: token.mint(address(party)),
                    fees: new uint256[](0),
                    feeRecipients: new address payable[](0)
                })
            );
            // Used to indicate a native distribution (i.e. distribution of ETH).
            tokenToDistribute = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else if (proposalType == ProposalExecutionEngine.ProposalType.ListOnZora) {
            token = new DummyERC721();
            proposalData = abi.encodeWithSelector(
                bytes4(uint32(proposalType)),
                ListOnZoraProposal.ZoraProposalData({
                    listPrice: 1 ether,
                    timeout: 1 days,
                    duration: 1 days,
                    token: token,
                    tokenId: token.mint(address(party))
                })
            );
            // Used to indicate a native distribution (i.e. distribution of ETH).
            tokenToDistribute = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else if (proposalType == ProposalExecutionEngine.ProposalType.Fractionalize) {
            token = new DummyERC721();
            proposalData = abi.encodeWithSelector(
                bytes4(uint32(proposalType)),
                FractionalizeProposal.FractionalizeProposalData({
                    token: token,
                    tokenId: token.mint(address(party)),
                    listPrice: 1 ether
                })
            );
        } else if (proposalType == ProposalExecutionEngine.ProposalType.ArbitraryCalls) {
            ArbitraryCallsProposal.ArbitraryCall[] memory calls =
                new ArbitraryCallsProposal.ArbitraryCall[](2);

            // Mint an NFT.
            token = new DummyERC721();
            uint256 expectedTokenId = token.lastId() + 1;
            calls[0] = ArbitraryCallsProposal.ArbitraryCall({
                target: payable(address(token)),
                value: 0,
                data: abi.encodeWithSelector(
                    DummyERC721.mint.selector,
                    address(party)
                ),
                expectedResultHash: keccak256(abi.encode(expectedTokenId))
            });

            // Burn the NFT we just minted.
            calls[1] = ArbitraryCallsProposal.ArbitraryCall({
                target: payable(address(token)),
                value: 0,
                data: abi.encodeWithSelector(
                    DummyERC721.burn.selector,
                    expectedTokenId
                ),
                expectedResultHash: ""
            });

            proposalData = abi.encodeWithSelector(
                bytes4(uint32(proposalType)),
                calls
            );
        } else if (proposalType == ProposalExecutionEngine.ProposalType.UpgradeProposalEngineImpl) {
            proposalData = abi.encodeWithSelector(
                bytes4(uint32(proposalType)),
                address(proposalEngineImpl),
                ""
            );
        } else {
            revert("Invalid proposal type");
        }

        PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: proposalData
        });

        // Propose and pass the proposal (non-unanimously).
        vm.prank(alice);
        uint256 proposalId = party.propose(proposal, type(uint256).max);
        if (!_isProposalPassed(proposalId)) {
            vm.prank(bob);
            party.accept(proposalId, type(uint256).max);
        }
        if (!_isProposalPassed(proposalId)) {
            vm.prank(charlie);
            party.accept(proposalId, type(uint256).max);
        }

        // Execute a proposal until completion.
        bytes memory nextProgressData;
        do {
            vm.recordLogs();
            vm.prank(alice);
            party.execute(
                proposalId,
                proposal,
                preciousTokens,
                preciousTokenIds,
                nextProgressData,
                ""
            );

            Vm.Log[] memory entries = vm.getRecordedLogs();
            for (uint256 i; i < entries.length; i++) {
                Vm.Log memory entry = entries[i];
                if (entry.topics[0] == keccak256("ProposalExecuted(uint256,address,bytes)")) {
                    (, nextProgressData) = abi.decode(entry.data, (address, bytes));
                    break;
                }
            }

            if (proposalType == ProposalExecutionEngine.ProposalType.Fractionalize) {
                uint256 fractionId = fractional.vaultCount() - 1;
                tokenToDistribute = address(fractional.vaults(fractionId));
            }

            if (nextProgressData.length == 0) return tokenToDistribute;

            address buyer = _randomAddress();
            vm.label(buyer, "buyer");
            if (proposalType == ProposalExecutionEngine.ProposalType.ListOnOpensea) {
                // Buy Party's OpenSea listing.
                _buyOpenseaListing(BuyOpenseaListingParams({
                    maker: payable(address(party)),
                    buyer: buyer,
                    token: token,
                    tokenId: token.lastId(),
                    listPrice: 1 ether,
                    startTime: block.timestamp,
                    duration: 1 days,
                    zone: deployConstants.osZone,
                    conduitKey: deployConstants.osConduitKey
                }));
            } else if (proposalType == ProposalExecutionEngine.ProposalType.ListOnZora) {
                // Buy Party's Zora listing.
                (, ZoraHelpers.ZoraProgressData memory data) =
                    abi.decode(nextProgressData, (uint8, ZoraHelpers.ZoraProgressData));

                vm.prank(buyer);
                vm.deal(buyer, 1 ether);
                zora.createBid{value: 1 ether}(data.auctionId, 1 ether);
                skip(1 days);
            }
        } while (nextProgressData.length != 0);
    }

    function _isProposalPassed(uint256 proposalId) internal view returns (bool) {
        (PartyGovernance.ProposalStatus status,) = party.getProposalStateInfo(proposalId);
        return status == PartyGovernance.ProposalStatus.Passed;
    }


    function _distributeAndClaimTokens(address tokenToDistribute) internal {
        ITokenDistributor.TokenType tokenType =
            tokenToDistribute == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
            ? ITokenDistributor.TokenType.Native
            : ITokenDistributor.TokenType.Erc20;

        vm.prank(alice);
        ITokenDistributor.DistributionInfo memory distInfo =
            party.distribute(tokenType, tokenToDistribute, 0);

        vm.prank(alice);
        assertTrue(tokenDistributor.claim(distInfo, 1) > 0);

        vm.prank(bob);
        assertTrue(tokenDistributor.claim(distInfo, 2) > 0);

        vm.prank(charlie);
        assertTrue(tokenDistributor.claim(distInfo, 3) > 0);

        address payable partyMultisig = payable(deployConstants.partyDaoMultisig);
        uint256 multisigBalanceBefore = tokenType == ITokenDistributor.TokenType.Native
            ? partyMultisig.balance
            : IERC20(tokenToDistribute).balanceOf(partyMultisig);
        vm.prank(partyMultisig);
        tokenDistributor.claimFee(distInfo, partyMultisig);
        assertTrue(tokenType == ITokenDistributor.TokenType.Native
            ? partyMultisig.balance > multisigBalanceBefore
            : IERC20(tokenToDistribute).balanceOf(partyMultisig) > multisigBalanceBefore
        );
    }
}

interface ICrowdfund is IERC721 {
    function market() external view returns (IMarketWrapper);

    function nftContract() external view returns (IERC721);

    function nftTokenId() external view returns (uint256);

    function auctionId() external view returns (uint256);

    function totalContributions() external view returns (uint96);

    function party() external view returns (Party);

    function contribute(address delegate, bytes memory gateData) external payable;

    function batchBurn(address payable[] memory contributors) external;

    function bid() external;

    function finalize(Crowdfund.FixedGovernanceOpts memory govOpts)
        external
        returns (Party party);

    function buy(
        uint256 tokenId,
        address payable callTarget,
        uint96 callValue,
        bytes calldata callData,
        Crowdfund.FixedGovernanceOpts memory governanceOpts
    )
        external
        returns (Party party);

    function buy(
        address payable callTarget,
        uint96 callValue,
        bytes calldata callData,
        Crowdfund.FixedGovernanceOpts memory governanceOpts
    )
        external
        returns (Party party);

    function getContributorInfo(address contributor)
        external
        view
        returns (
            uint256 ethContributed,
            uint256 ethUsed,
            uint256 ethOwed,
            uint256 votingPower
        );
}
