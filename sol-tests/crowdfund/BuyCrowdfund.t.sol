// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/BuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/gatekeepers/AllowListGateKeeper.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./TestERC721Vault.sol";

contract BuyCrowdfundTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    event MockMint(address caller, address owner, uint256 amount, address delegate);

    event Contributed(
        address sender,
        address contributor,
        uint256 amount,
        address delegate,
        uint256 previousTotalContributions
    );
    event DelegateUpdated(
        address sender,
        address contributor,
        address oldDelegate,
        address newDelegate
    );
    event Lost();

    string defaultName = "BuyCrowdfund";
    string defaultSymbol = "PBID";
    uint40 defaultDuration = 60 * 60;
    uint96 defaultMaxPrice = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    Crowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    TestERC721Vault erc721Vault = new TestERC721Vault();
    BuyCrowdfund buyCrowdfundImpl;
    MockParty party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();
        buyCrowdfundImpl = new BuyCrowdfund(globals);
    }

    function setUp() public {}

    function _createCrowdfund(
        uint256 tokenId,
        uint96 initialContribution,
        bool onlyHostCanBuy,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        address[] memory hosts
    ) private returns (BuyCrowdfund cf) {
        defaultGovernanceOpts.hosts = hosts;
        cf = BuyCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        buyCrowdfundImpl,
                        abi.encodeCall(
                            BuyCrowdfund.initialize,
                            BuyCrowdfund.BuyCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
                                nftContract: erc721Vault.token(),
                                nftTokenId: tokenId,
                                duration: defaultDuration,
                                maximumPrice: defaultMaxPrice,
                                splitRecipient: defaultSplitRecipient,
                                splitBps: defaultSplitBps,
                                initialContributor: address(this),
                                initialDelegate: defaultInitialDelegate,
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: gateKeeper,
                                gateKeeperId: gateKeeperId,
                                onlyHostCanBuy: onlyHostCanBuy,
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function _createCrowdfund(
        uint256 tokenId,
        uint96 initialContribution
    ) private returns (BuyCrowdfund cf) {
        return
            _createCrowdfund(
                tokenId,
                initialContribution,
                false,
                defaultGateKeeper,
                defaultGateKeeperId,
                defaultGovernanceOpts.hosts
            );
    }

    function _createExpectedPartyOptions(
        uint256 finalPrice
    ) private view returns (Party.PartyOptions memory opts) {
        return
            Party.PartyOptions({
                name: defaultName,
                symbol: defaultSymbol,
                customizationPresetId: 0,
                governance: PartyGovernance.GovernanceOpts({
                    hosts: defaultGovernanceOpts.hosts,
                    voteDuration: defaultGovernanceOpts.voteDuration,
                    executionDelay: defaultGovernanceOpts.executionDelay,
                    passThresholdBps: defaultGovernanceOpts.passThresholdBps,
                    totalVotingPower: uint96(finalPrice),
                    feeBps: defaultGovernanceOpts.feeBps,
                    feeRecipient: defaultGovernanceOpts.feeRecipient
                })
            });
    }

    function testHappyPath() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Buy the token.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(0.5e18),
            _toERC721Array(erc721Vault.token()),
            _toUint256Array(tokenId)
        );
        Party party_ = cf.buy(
            payable(address(erc721Vault)),
            0.5e18,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            defaultGovernanceOpts,
            0
        );
        assertEq(address(party), address(party_));
        // Burn contributor's NFT, mock minting governance tokens and returning
        // unused contribution.
        vm.expectEmit(false, false, false, true);
        emit MockMint(address(cf), contributor, 0.5e18, delegate);
        cf.burn(contributor);
        assertEq(contributor.balance, 0.5e18);
    }

    // The call to buy() does not transfer the token.
    function testBuyDoesNotTransferToken() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Pretend to buy the token.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.FailedToBuyNFTError.selector,
                erc721Vault.token(),
                tokenId
            )
        );
        cf.buy(
            _randomAddress(), // Call random EOA, which will succeed but do nothing
            0.5e18,
            "",
            defaultGovernanceOpts,
            0
        );
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Active);
    }

    function testOnlyHostCanBuy() public {
        // Create a BuyCrowdfund instance with `onlyHost` enabled.
        address host = _randomAddress();
        address contributor = _randomAddress();

        BuyCrowdfund cf = _createCrowdfund(
            0,
            0,
            true,
            IGateKeeper(address(0)),
            0,
            _toAddressArray(host)
        );

        assertEq(cf.onlyHostCanBuy(), true);

        // Contributor contributes.
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, abi.encode(new bytes32[](0)));

        // Buy the token and expect revert because we are not a host.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.buy(payable(address(0)), 0, "", defaultGovernanceOpts, 0);

        // Now as the host, but this will fail with another error because
        // we are trying to call the CF itself in buy().
        vm.prank(host);
        vm.expectRevert(
            abi.encodeWithSelector(BuyCrowdfundBase.CallProhibitedError.selector, address(cf), "")
        );
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);

        // Buy as a contributor, but this will fail because only the host can
        // call buy().
        vm.prank(contributor);
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);
    }

    function testOnlyHostCanBuy_CannotFakeGovernanceOpts() public {
        // Create a BuyCrowdfund instance with `onlyHost` enabled.
        address host = _randomAddress();

        BuyCrowdfund cf = _createCrowdfund(
            0,
            0,
            true,
            IGateKeeper(address(0)),
            0,
            _toAddressArray(host)
        );

        // Buy as the host, but pass in wrong governanceOpts.
        vm.prank(host);
        vm.expectRevert(Crowdfund.InvalidGovernanceOptionsError.selector);
        defaultGovernanceOpts.voteDuration += 1;
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);
    }

    function testOnlyContributorCanBuy() public {
        address host = _randomAddress();
        address contributor = _randomAddress();

        // Create a BuyCrowdfund instance with a gatekeeper enabled.
        AllowListGateKeeper gateKeeper = new AllowListGateKeeper();
        bytes32 contributorHash = keccak256(abi.encodePacked(contributor));
        bytes12 gateKeeperId = gateKeeper.createGate(contributorHash);
        BuyCrowdfund cf = _createCrowdfund(
            0,
            0,
            false,
            gateKeeper,
            gateKeeperId,
            _toAddressArray(host)
        );

        // Contributor contributes.
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, abi.encode(new bytes32[](0)));

        // Buy the token, expect revert because we are not a contributor or host.
        vm.expectRevert(Crowdfund.OnlyContributorError.selector);
        cf.buy(payable(address(0)), 0, "", defaultGovernanceOpts, 0);

        // Now as the host, but this will fail because the host is not a contributor.
        vm.prank(host);
        vm.expectRevert(Crowdfund.OnlyContributorError.selector);
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);

        // Buy as a contributor, but this will fail with another error because
        // we are trying to call the CF itself in buy().
        vm.prank(contributor);
        vm.expectRevert(
            abi.encodeWithSelector(BuyCrowdfundBase.CallProhibitedError.selector, address(cf), "")
        );
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);
    }

    function testOnlyHostOrCanBuy_withGatekeeperSet() public {
        address host = _randomAddress();
        address contributor = _randomAddress();

        // Create a BuyCrowdfund instance with onlyHostCanBuy and a gatekeeper enabled.
        AllowListGateKeeper gateKeeper = new AllowListGateKeeper();
        bytes32 contributorHash = keccak256(abi.encodePacked(contributor));
        bytes12 gateKeeperId = gateKeeper.createGate(contributorHash);
        BuyCrowdfund cf = _createCrowdfund(
            0,
            0,
            true,
            gateKeeper,
            gateKeeperId,
            _toAddressArray(host)
        );

        // Contributor contributes.
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, abi.encode(new bytes32[](0)));

        // Buy the token, expect revert because we are not a contributor or host.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.buy(payable(address(0)), 0, "", defaultGovernanceOpts, 0);

        // Now as the host, but this will fail with another error because
        // we are trying to call the CF itself in buy().
        vm.prank(host);
        vm.expectRevert(
            abi.encodeWithSelector(BuyCrowdfundBase.CallProhibitedError.selector, address(cf), "")
        );
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);

        // Buy as a contributor, but this will fail because onlyHost is on.
        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(Crowdfund.OnlyPartyHostError.selector));
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);
    }

    function testOnlyHostOrContributorCanBuy_CannotFakeGovernanceOpts() public {
        // Create a BuyCrowdfund instance with `onlyHost` enabled.
        address host = _randomAddress();

        // Create a BuyCrowdfund instance with onlyHostCanBuy and a gatekeeper enabled.
        AllowListGateKeeper gateKeeper = new AllowListGateKeeper();
        bytes12 gateKeeperId = gateKeeper.createGate(0);
        BuyCrowdfund cf = _createCrowdfund(
            0,
            0,
            true,
            gateKeeper,
            gateKeeperId,
            _toAddressArray(host)
        );

        // Buy as the host, but pass in wrong governanceOpts.
        vm.prank(host);
        vm.expectRevert(Crowdfund.InvalidGovernanceOptionsError.selector);
        defaultGovernanceOpts.voteDuration += 1;
        cf.buy(payable(address(cf)), 0, "", defaultGovernanceOpts, 0);
    }

    function testBuyCannotExceedTotalContributions() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        // Contribute.
        address payable contributor = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, "");
        // Transfer ETH to the crowdfund (not through contribution).
        uint96 totalContributions = cf.totalContributions();
        vm.deal(address(cf), totalContributions + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.ExceedsTotalContributionsError.selector,
                totalContributions + 1,
                totalContributions
            )
        );
        cf.buy(
            payable(address(erc721Vault)),
            totalContributions + 1,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            defaultGovernanceOpts,
            0
        );
    }

    function testBuyCannotReenter() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        // Contribute.
        address payable contributor = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, "");
        bytes memory callData = abi.encodeCall(cf.contribute, (contributor, ""));
        // Attempt reentering back into the crowdfund directly.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.CallProhibitedError.selector,
                address(cf),
                callData
            )
        );
        cf.buy(payable(address(cf)), 1e18, callData, defaultGovernanceOpts, 0);
        ReenteringContract reenteringContract = new ReenteringContract();
        // Attempt reentering back into the crowdfund via a proxy.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                uint8(Crowdfund.CrowdfundLifecycle.Busy)
            )
        );
        cf.buy(
            payable(address(reenteringContract)),
            1e18,
            abi.encodeCall(reenteringContract.reenter, (cf)),
            defaultGovernanceOpts,
            0
        );
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Active);
    }

    function testBuyCannotApprove() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        // Contribute.
        address payable contributor = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, "");
        // Attempt calling `approve()`.
        bytes memory callData = abi.encodeCall(IERC721.approve, (contributor, tokenId));
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.CallProhibitedError.selector,
                address(cf),
                callData
            )
        );
        cf.buy(payable(address(cf)), 1e18, callData, defaultGovernanceOpts, 0);
        // Attempt calling `setApprovalForAll()`.
        callData = abi.encodeCall(IERC721.setApprovalForAll, (contributor, true));
        IERC721 token = erc721Vault.token();
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.CallProhibitedError.selector,
                address(token),
                callData
            )
        );
        cf.buy(payable(address(token)), 1e18, callData, defaultGovernanceOpts, 0);
    }

    function testGettingNFTForFreeTriggersLostToRefund() public {
        DummyERC721 token = erc721Vault.token();
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        // Acquire NFT for free.
        vm.prank(address(cf));
        erc721Vault.claim(tokenId);
        _expectEmit0();
        emit Lost();
        cf.buy(
            payable(address(token)),
            0,
            abi.encodeCall(token.mint, (address(cf))),
            defaultGovernanceOpts,
            0
        );
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Lost);
    }

    function testCannotReinitialize() public {
        uint256 tokenId = erc721Vault.mint();
        BuyCrowdfund cf = _createCrowdfund(tokenId, 0);
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        BuyCrowdfund.BuyCrowdfundOptions memory opts;
        cf.initialize(opts);
    }

    function test_creation_initialContribution() public {
        uint256 tokenId = erc721Vault.mint();
        uint256 initialContribution = _randomRange(1, 1 ether);
        address initialContributor = _randomAddress();
        address initialDelegate = _randomAddress();
        _expectEmit0();
        emit Contributed(
            address(this),
            initialContributor,
            initialContribution,
            initialDelegate,
            0
        );
        BuyCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        buyCrowdfundImpl,
                        abi.encodeCall(
                            BuyCrowdfund.initialize,
                            BuyCrowdfund.BuyCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
                                nftContract: erc721Vault.token(),
                                nftTokenId: tokenId,
                                duration: defaultDuration,
                                maximumPrice: defaultMaxPrice,
                                splitRecipient: defaultSplitRecipient,
                                splitBps: defaultSplitBps,
                                initialContributor: initialContributor,
                                initialDelegate: initialDelegate,
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: defaultGateKeeper,
                                gateKeeperId: defaultGateKeeperId,
                                onlyHostCanBuy: false,
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }
}

contract ReenteringContract is Test {
    function reenter(BuyCrowdfund cf) external payable {
        cf.contribute{ value: msg.value }(address(this), "");
    }
}
