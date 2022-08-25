// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "contracts/crowdfund/PartyCrowdfundFactory.sol";
import "contracts/crowdfund/PartyBid.sol";
import "contracts/crowdfund/IMarketWrapper.sol";
import "contracts/crowdfund/PartyCrowdfund.sol";
import "contracts/gatekeepers/AllowListGateKeeper.sol";
import "contracts/gatekeepers/TokenGateKeeper.sol";
import "contracts/tokens/IERC721.sol";
import "./MockMarketWrapper.sol";
import "contracts/globals/Globals.sol";
import "contracts/globals/LibGlobals.sol";

import "forge-std/Test.sol";
import "../TestUtils.sol";

contract PartyCrowdfundFactoryTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    PartyCrowdfundFactory partyCrowdfundFactory = new PartyCrowdfundFactory(globals);
    MockMarketWrapper market = new MockMarketWrapper();
    PartyBid partyBid = new PartyBid(globals);
    PartyBuy partyBuy = new PartyBuy(globals);
    PartyCollectionBuy partyCollectionBuy = new PartyCollectionBuy(globals);
    AllowListGateKeeper allowListGateKeeper = new AllowListGateKeeper();
    TokenGateKeeper tokenGateKeeper = new TokenGateKeeper();

    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_BID_IMPL, address(partyBid));
        globals.setAddress(LibGlobals.GLOBAL_PARTY_BUY_IMPL, address(partyBuy));
        globals.setAddress(LibGlobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL, address(partyCollectionBuy));
    }

    function _hashFixedGovernanceOpts(PartyCrowdfund.FixedGovernanceOpts memory opts)
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
        returns (IGateKeeper, bytes12, bytes memory createGateCallData)
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

    function testCreatePartyBid(
        string memory randomStr,
        uint128 randomUint128,
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

        PartyBid.PartyBidOptions memory opts = PartyBid.PartyBidOptions({
            name: randomStr,
            symbol: randomStr,
            auctionId: auctionId,
            market: IMarketWrapper(market),
            nftContract: nftContract,
            nftTokenId: tokenId,
            duration: randomUint40,
            maximumBid: randomUint128,
            splitRecipient: payable(_randomAddress()),
            splitBps: randomBps,
            initialContributor: _randomAddress(),
            initialDelegate: _randomAddress(),
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId,
            governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            })
        });

        PartyBid inst = partyCrowdfundFactory.createPartyBid(opts, createGateCallData);

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
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId :  bytes12(uint96(1))
        );
        assertEq(inst.governanceOptsHash(), _hashFixedGovernanceOpts(opts.governanceOpts));
    }

    function testCreatePartyBidWithInvalidAuctionId() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        PartyBid.PartyBidOptions memory opts = PartyBid.PartyBidOptions({
            name: "name",
            symbol: "symbol",
            auctionId: auctionId + 1,
            market: IMarketWrapper(market),
            nftContract: nftContract,
            nftTokenId: tokenId,
            duration: 7 days,
            maximumBid: type(uint128).max,
            splitRecipient: payable(address(0)),
            splitBps: 0,
            initialContributor: address(0),
            initialDelegate: address(0),
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 51e2,
                feeBps: 0,
                feeRecipient: payable(address(0))
            })
        });

        vm.expectRevert(PartyBid.InvalidAuctionIdError.selector);
        PartyBid inst = partyCrowdfundFactory.createPartyBid(opts, "");
    }

    function testCreatePartyBidWithInvalidNftContract() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);

        PartyBid.PartyBidOptions memory opts = PartyBid.PartyBidOptions({
            name: "name",
            symbol: "symbol",
            auctionId: auctionId,
            market: IMarketWrapper(market),
            nftContract: IERC721(address(0)),
            nftTokenId: tokenId,
            duration: 7 days,
            maximumBid: type(uint128).max,
            splitRecipient: payable(address(0)),
            splitBps: 0,
            initialContributor: address(0),
            initialDelegate: address(0),
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 51e2,
                feeBps: 0,
                feeRecipient: payable(address(0))
            })
        });

        vm.expectRevert(PartyBid.InvalidAuctionIdError.selector);
        PartyBid inst = partyCrowdfundFactory.createPartyBid(opts, "");
    }

    function testCreatePartyBidWithInvalidTokenId() external {
        // Create an auction.
        (uint256 auctionId, uint256 tokenId)  = market.createAuction(0);
        IERC721 nftContract = IERC721(market.nftContract());

        PartyBid.PartyBidOptions memory opts = PartyBid.PartyBidOptions({
            name: "name",
            symbol: "symbol",
            auctionId: auctionId,
            market: IMarketWrapper(market),
            nftContract: nftContract,
            nftTokenId: tokenId + 1,
            duration: 7 days,
            maximumBid: type(uint128).max,
            splitRecipient: payable(address(0)),
            splitBps: 0,
            initialContributor: address(0),
            initialDelegate: address(0),
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(address(this)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 51e2,
                feeBps: 0,
                feeRecipient: payable(address(0))
            })
        });

        vm.expectRevert(PartyBid.InvalidAuctionIdError.selector);
        PartyBid inst = partyCrowdfundFactory.createPartyBid(opts, "");
    }

    function testCreatePartyBuy(
        string memory randomStr,
        uint128 randomUint128,
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

        PartyBuy.PartyBuyOptions memory opts = PartyBuy.PartyBuyOptions({
            name: randomStr,
            symbol: randomStr,
            nftContract: nftContract,
            nftTokenId: tokenId,
            duration: randomUint40,
            maximumPrice: randomUint128,
            splitRecipient: payable(_randomAddress()),
            splitBps: randomBps,
            initialContributor: _randomAddress(),
            initialDelegate: _randomAddress(),
            gateKeeper: gateKeeper,
            gateKeeperId: gateKeeperId,
            governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            })
        });

        PartyBuy inst = partyCrowdfundFactory.createPartyBuy(opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.nftTokenId(), opts.nftTokenId);
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
        assertEq(address(inst.gateKeeper()), address(opts.gateKeeper));
        assertEq(
            inst.gateKeeperId(),
            address(opts.gateKeeper) == address(0) ? gateKeeperId :  bytes12(uint96(1))
        );
        assertEq(inst.governanceOptsHash(), _hashFixedGovernanceOpts(opts.governanceOpts));
    }

    function testCreatePartyCollectionBuy(
        string memory randomStr,
        uint128 randomUint128,
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

        PartyCollectionBuy.PartyCollectionBuyOptions memory opts =
            PartyCollectionBuy.PartyCollectionBuyOptions({
                name: randomStr,
                symbol: randomStr,
                nftContract: nftContract,
                duration: randomUint40,
                maximumPrice: randomUint128,
                splitRecipient: payable(_randomAddress()),
                splitBps: randomBps,
                initialContributor: _randomAddress(),
                initialDelegate: _randomAddress(),
                gateKeeper: gateKeeper,
                gateKeeperId: gateKeeperId,
                governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
                    hosts: _toAddressArray(_randomAddress()),
                    voteDuration: randomUint40,
                    executionDelay: randomUint40,
                    passThresholdBps: randomBps,
                    feeBps: randomBps,
                    feeRecipient: payable(_randomAddress())
                })
            });

        PartyCollectionBuy inst = partyCrowdfundFactory.createPartyCollectionBuy(opts, createGateCallData);

        // Check that value are initialized to what we expect.
        assertEq(inst.name(), opts.name);
        assertEq(inst.symbol(), opts.symbol);
        assertEq(address(inst.nftContract()), address(opts.nftContract));
        assertEq(inst.expiry(), uint40(block.timestamp + opts.duration));
        assertEq(inst.maximumPrice(), opts.maximumPrice);
        assertEq(inst.splitRecipient(), opts.splitRecipient);
        assertEq(inst.splitBps(), opts.splitBps);
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

        PartyBid.PartyBidOptions memory opts = PartyBid.PartyBidOptions({
            name: "name",
            symbol: "symbol",
            auctionId: auctionId,
            market: IMarketWrapper(market),
            nftContract: nftContract,
            nftTokenId: tokenId,
            duration: 7 days,
            maximumBid: type(uint128).max,
            splitRecipient: payable(address(0)),
            splitBps: splitBps,
            initialContributor: address(0),
            initialDelegate: address(0),
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: 0,
            governanceOpts: PartyCrowdfund.FixedGovernanceOpts({
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
        vm.expectRevert(abi.encodeWithSelector(PartyCrowdfund.InvalidBpsError.selector, invalidBps));
        PartyBid inst = partyCrowdfundFactory.createPartyBid(opts, "");
    }
}