// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

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

import "forge-std/Test.sol";
import "../TestUtils.sol";

contract CrowdfundFactoryTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    CrowdfundFactory partyCrowdfundFactory = new CrowdfundFactory(globals);
    MockMarketWrapper market = new MockMarketWrapper();
    AuctionCrowdfund auctionCrowdfund = new AuctionCrowdfund(globals);
    BuyCrowdfund buyCrowdfund = new BuyCrowdfund(globals);
    CollectionBuyCrowdfund collectionBuyCrowdfund = new CollectionBuyCrowdfund(globals);
    AllowListGateKeeper allowListGateKeeper = new AllowListGateKeeper();
    TokenGateKeeper tokenGateKeeper = new TokenGateKeeper();

    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_AUCTION_CF_IMPL, address(auctionCrowdfund));
        globals.setAddress(LibGlobals.GLOBAL_BUY_CF_IMPL, address(buyCrowdfund));
        globals.setAddress(LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL, address(collectionBuyCrowdfund));
    }

    function _hashFixedGovernanceOpts(Crowdfund.FixedGovernanceOpts memory opts)
        internal
        pure
        returns (bytes16 h)
    {
        // Hash in place.
        assembly {
            // Replace the address[] hosts field with its hash temporarily.
            let oldHostsFieldValue := mload(opts)
            mstore(opts, keccak256(add(mload(opts), 0x20), mul(mload(mload(opts)), 32)))
            // Hash the entire struct.
            h := and(keccak256(opts, 0xC0), 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000)
            // Restore old hosts field value.
            mstore(opts, oldHostsFieldValue)
        }
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
            createGateCallData = abi.encodeCall(TokenGateKeeper.createGate, (Token(_randomAddress()), _randomUint256()));
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
        uint16 randomBps
    ) external {
        vm.assume(randomBps <= 1e4);

        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        // Generate random gatekeeper.
        (
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId,
            bytes memory createGateCallData
        ) = _randomGateKeeper();

        AuctionCrowdfund.AuctionCrowdfundOptions memory opts = AuctionCrowdfund.AuctionCrowdfundOptions({
            name: randomStr,
            symbol: randomStr,
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
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            })
        });

        vm.deal(address(this), randomUint40);
        AuctionCrowdfund inst = partyCrowdfundFactory.createAuctionCrowdfund{ value: randomUint40 }(opts, createGateCallData);

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
        (uint256 ethContributed, , ,) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId :  bytes12(uint96(1))
        );
        assertEq(inst.governanceOptsHash(), _hashFixedGovernanceOpts(opts.governanceOpts));
    }

    function testCreateAuctionCrowdfundWithInvalidAuctionId() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        AuctionCrowdfund.AuctionCrowdfundOptions memory opts = AuctionCrowdfund.AuctionCrowdfundOptions({
            name: "name",
            symbol: "symbol",
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
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 51e2,
                feeBps: 0,
                feeRecipient: payable(address(0))
            })
        });

        vm.expectRevert(AuctionCrowdfund.InvalidAuctionIdError.selector);
        partyCrowdfundFactory.createAuctionCrowdfund(opts, "");
    }

    function testCreateAuctionCrowdfundWithInvalidNftContract() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);

        AuctionCrowdfund.AuctionCrowdfundOptions memory opts = AuctionCrowdfund.AuctionCrowdfundOptions({
            name: "name",
            symbol: "symbol",
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
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 51e2,
                feeBps: 0,
                feeRecipient: payable(address(0))
            })
        });

        vm.expectRevert(AuctionCrowdfund.InvalidAuctionIdError.selector);
        partyCrowdfundFactory.createAuctionCrowdfund(opts, "");
    }

    function testCreateAuctionCrowdfundWithInvalidTokenId() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        AuctionCrowdfund.AuctionCrowdfundOptions memory opts = AuctionCrowdfund.AuctionCrowdfundOptions({
            name: "name",
            symbol: "symbol",
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
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 51e2,
                feeBps: 0,
                feeRecipient: payable(address(0))
            })
        });

        vm.expectRevert(AuctionCrowdfund.InvalidAuctionIdError.selector);
        partyCrowdfundFactory.createAuctionCrowdfund(opts, "");
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

        BuyCrowdfund.BuyCrowdfundOptions memory opts = BuyCrowdfund.BuyCrowdfundOptions({
            name: randomStr,
            symbol: randomStr,
            nftContract: nftContract,
            nftTokenId: tokenId,
            // This is to avoid overflows when adding to `block.timestamp`.
            duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
            maximumPrice: randomUint96,
            splitRecipient: payable(_randomAddress()),
            splitBps: randomBps,
            initialContributor: _randomAddress(),
            initialDelegate: _randomAddress(),
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            })
        });

        vm.deal(address(this), randomUint40);
        BuyCrowdfund inst = partyCrowdfundFactory.createBuyCrowdfund{ value: randomUint40 }(opts, createGateCallData);

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
        (uint256 ethContributed, , ,) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId :  bytes12(uint96(1))
        );
        assertEq(inst.governanceOptsHash(), _hashFixedGovernanceOpts(opts.governanceOpts));
    }

    function testCreateCollectionBuyCrowdfund(
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

        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions memory opts =
            CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions({
                name: randomStr,
                symbol: randomStr,
                nftContract: nftContract,
                // This is to avoid overflows when adding to `block.timestamp`.
                duration: uint40(_randomRange(1, type(uint40).max - block.timestamp)),
                maximumPrice: randomUint96,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: Crowdfund.FixedGovernanceOpts({
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                })
            });

        vm.deal(address(this), randomUint40);
        CollectionBuyCrowdfund inst = partyCrowdfundFactory.
            createCollectionBuyCrowdfund{ value: randomUint40 }(opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(inst.totalContributions(), uint96(randomUint40));
        (uint256 ethContributed, , ,) = inst.getContributorInfo(opts.initialContributor);
        assertEq(ethContributed, randomUint40);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId :  bytes12(uint96(1))
        );
        assertEq(inst.governanceOptsHash(), _hashFixedGovernanceOpts(opts.governanceOpts));
    }

    function testCreatePartyWithInvalidBps(
        uint16 splitBps,
        uint16 passThresholdBps,
        uint16 feeBps
    ) external {
        // At least one of the BPs must be invalid for this test to work.
        vm.assume(splitBps > 1e4 || passThresholdBps > 1e4 || feeBps > 1e4);

        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        AuctionCrowdfund.AuctionCrowdfundOptions memory opts = AuctionCrowdfund.AuctionCrowdfundOptions({
            name: "name",
            symbol: "symbol",
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
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: Crowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: passThresholdBps,
                feeBps: feeBps,
                feeRecipient: payable(address(0))
            })
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
        partyCrowdfundFactory.createAuctionCrowdfund(opts, "");
    }
}