// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "./MockPartyFactory.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../proposals/OpenseaTestUtils.sol";
import "../../contracts/crowdfund/BuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

contract OpenseaFulfillOrderTest is Test, TestUtils, OpenseaTestUtils {
    BuyCrowdfund cf;
    Crowdfund.FixedGovernanceOpts govOpts;
    DummyERC721 token;
    uint256 tokenId;

    uint256 sellerPrivateKey = 0xDEADBEEF;
    address payable seller = payable(vm.addr(sellerPrivateKey));

    IOpenseaExchange SEAPORT = IOpenseaExchange(0x00000000006c3852cbEf3e08E8dF289169EdE581);

    constructor() OpenseaTestUtils(SEAPORT) {
        token = new DummyERC721();
        tokenId = token.mint(seller);

        Globals globals = new Globals(address(this));
        MockPartyFactory partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));

        BuyCrowdfund buyCrowdfundImpl = new BuyCrowdfund(globals);
        govOpts.hosts = new address[](1);
        govOpts.hosts[0] = address(this);

        // Create a BuyCrowdfund
        cf = BuyCrowdfund(
            payable(
                address(
                    new Proxy(
                        buyCrowdfundImpl,
                        abi.encodeCall(
                            BuyCrowdfund.initialize,
                            BuyCrowdfund.BuyCrowdfundOptions({
                                name: "Test",
                                symbol: "TEST",
                                customizationPresetId: 0,
                                nftContract: token,
                                nftTokenId: tokenId,
                                duration: 7 days,
                                maximumPrice: type(uint96).max,
                                splitRecipient: payable(address(0)),
                                splitBps: 0,
                                initialContributor: address(0),
                                initialDelegate: address(0),
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: IGateKeeper(address(0)),
                                gateKeeperId: 0,
                                onlyHostCanBuy: false,
                                governanceOpts: govOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function testForked_canBuyDutchAuctionListingFromOS() public onlyForked {
        uint256 startPrice = 3e18;
        uint256 endPrice = 1e18;
        uint256 duration = 7 days;

        // Create OpenSea dutch auction listing
        vm.startPrank(seller);
        token.setApprovalForAll(address(SEAPORT), true);
        IOpenseaExchange.Order memory order = _createOpenseaDutchAuctionOrderParams(
            DutchAuctionOpenseaListingParams({
                maker: seller,
                token: IERC721(address(token)),
                tokenId: tokenId,
                startPrice: startPrice,
                endPrice: endPrice,
                startTime: block.timestamp,
                duration: duration,
                zone: address(0),
                conduitKey: bytes32(0)
            })
        );
        vm.stopPrank();

        bytes32 orderHash = SEAPORT.getOrderHash(
            IOpenseaExchange.OrderComponents({
                offerer: order.parameters.offerer,
                zone: order.parameters.zone,
                offer: order.parameters.offer,
                consideration: order.parameters.consideration,
                orderType: order.parameters.orderType,
                startTime: order.parameters.startTime,
                endTime: order.parameters.endTime,
                zoneHash: order.parameters.zoneHash,
                salt: order.parameters.salt,
                conduitKey: order.parameters.conduitKey,
                nonce: 0
            })
        );

        // Generate signature for order
        bytes32 domainSeparator = 0xb50c8913581289bd2e066aeef89fceb9615d490d673131fd1a7047436706834e;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            sellerPrivateKey,
            keccak256(abi.encodePacked(bytes2(0x1901), domainSeparator, orderHash))
        );
        order.signature = abi.encodePacked(r, s, v);

        // Skip half-way through dutch auction
        skip(duration / 2);
        uint96 currentPrice = 2e18; // Half-way between start and end price

        // Buy OpenSea listing
        vm.deal(address(this), currentPrice);
        cf.contribute{ value: currentPrice }(address(this), "");
        Party party = cf.buy(
            payable(address(SEAPORT)),
            currentPrice,
            abi.encodeCall(SEAPORT.fulfillOrder, (order, bytes32(0))),
            govOpts,
            0
        );

        assertEq(token.ownerOf(tokenId), address(party));
        assertEq(address(cf).balance, 0);
    }
}
