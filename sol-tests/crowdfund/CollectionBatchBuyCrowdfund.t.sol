// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/CollectionBatchBuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "./TestERC721Vault.sol";

contract CollectionBatchBuyCrowdfundTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    CollectionBatchBuyCrowdfund cf;
    DummyERC721 nftContract;
    MockParty party;

    uint96 maximumPrice = 100e18;
    Crowdfund.FixedGovernanceOpts govOpts;

    constructor() {
        Globals globals = new Globals(address(this));
        MockPartyFactory partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();

        nftContract = new DummyERC721();

        govOpts.hosts.push(address(this));

        cf = CollectionBatchBuyCrowdfund(
            payable(
                address(
                    new Proxy(
                        new CollectionBatchBuyCrowdfund(globals),
                        abi.encodeCall(
                            CollectionBatchBuyCrowdfund.initialize,
                            CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions({
                                name: "Crowdfund",
                                symbol: "CF",
                                customizationPresetId: 0,
                                nftContract: nftContract,
                                duration: 1 days,
                                maximumPrice: maximumPrice,
                                splitRecipient: payable(address(0)),
                                splitBps: 0,
                                initialContributor: address(0),
                                initialDelegate: address(0),
                                gateKeeper: IGateKeeper(address(0)),
                                gateKeeperId: 0,
                                governanceOpts: govOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function test_cannotReinitialize() public {
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions memory opts;
        cf.initialize(opts);
    }

    function test_happyPath() public {
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        IERC721[] memory tokens = new IERC721[](3);
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
            callTargets[i] = payable(address(nftContract));
            callValues[i] = 1;
            callDatas[i] = abi.encodeCall(nftContract.mint, (address(cf)));
        }
        // Buy the tokens.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            Party.PartyOptions({
                name: "Crowdfund",
                symbol: "CF",
                customizationPresetId: 0,
                governance: PartyGovernance.GovernanceOpts({
                    hosts: govOpts.hosts,
                    voteDuration: govOpts.voteDuration,
                    executionDelay: govOpts.executionDelay,
                    passThresholdBps: govOpts.passThresholdBps,
                    totalVotingPower: 3,
                    feeBps: govOpts.feeBps,
                    feeRecipient: govOpts.feeRecipient
                })
            }),
            tokens,
            tokenIds
        );
        Party party_ = cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
        assertEq(address(party_), address(party));
    }

    function test_batchBuy_cannotTriggerLostByNotBuyingAnything() public {
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](0);
        address payable[] memory callTargets = new address payable[](0);
        uint96[] memory callValues = new uint96[](0);
        bytes[] memory callDatas = new bytes[](0);
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.NothingBoughtError.selector);
        cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
    }

    function test_batchBuy_cannotTriggerLostByBuyingFreeNFTs() public {
        // Setup parameters to batch buy.
        IERC721[] memory tokens = new IERC721[](3);
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
            // Mint tokens to crowdfund for free.
            nftContract.mint(address(cf));
        }
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.NothingBoughtError.selector);
        Party party_ = cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
    }

    function test_batchBuy_failedToBuy() public {
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.FailedToBuyNFTError.selector,
                address(nftContract),
                0
            )
        );
        cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
    }

    function test_batchBuy_aboveMaximumPrice() public {
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        callValues[0] = maximumPrice + 1;
        bytes[] memory callDatas = new bytes[](3);
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.MaximumPriceError.selector,
                maximumPrice + 1,
                maximumPrice
            )
        );
        cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
    }

    function test_batchBuy_onlyHost() public {
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        // Buy the tokens.
        vm.prank(_randomAddress());
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
    }

    function test_batchBuy_invalidGovOpts() public {
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        // Mutate governance options
        govOpts.hosts.push(_randomAddress());
        // Buy the tokens.
        vm.expectRevert(Crowdfund.InvalidGovernanceOptionsError.selector);
        cf.batchBuy(tokenIds, callTargets, callValues, callDatas, govOpts, 0);
    }
}
