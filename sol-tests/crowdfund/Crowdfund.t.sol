// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/gatekeepers/AllowListGateKeeper.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/renderers/CrowdfundNFTRenderer.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/utils/EIP165.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "./TestableCrowdfund.sol";

contract CrowdfundTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    event MockMint(
        address caller,
        address owner,
        uint256 amount,
        address delegate
    );

    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);
    event Burned(address contributor, uint256 ethUsed, uint256 ethOwed, uint256 votingPower);

    string defaultName = 'AuctionCrowdfund';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint96 defaultMaxBid = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    Crowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockParty party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.voteDuration = 1 days;
        defaultGovernanceOpts.executionDelay = 0.5 days;
        defaultGovernanceOpts.passThresholdBps = 0.51e4;
    }

    function setUp() public {
        CrowdfundNFTRenderer nftRenderer = new CrowdfundNFTRenderer(globals);
        globals.setAddress(LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL, address(nftRenderer));
    }

    function _createTokens(address owner, uint256 count)
        private
        returns (IERC721[] memory tokens, uint256[] memory tokenIds)
    {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            DummyERC721 t = new DummyERC721();
            tokens[i] = IERC721(t);
            tokenIds[i] = t.mint(owner);
        }
    }

    function _createCrowdfund(uint96 initialContribution)
        private
        returns (TestableCrowdfund cf)
    {
        cf = new TestableCrowdfund{value: initialContribution }(
            globals,
            Crowdfund.CrowdfundOptions({
                name: defaultName,
                symbol: defaultSymbol,
                splitRecipient: defaultSplitRecipient,
                splitBps: defaultSplitBps,
                initialContributor: address(this),
                initialDelegate: defaultInitialDelegate,
                gateKeeper: defaultGateKeeper,
                gateKeeperId: defaultGateKeeperId,
                governanceOpts: defaultGovernanceOpts
            })
        );
    }

    function _createExpectedPartyOptions(TestableCrowdfund cf, uint256 finalPrice)
        private
        view
        returns (Party.PartyOptions memory opts)
    {
        Crowdfund.FixedGovernanceOpts memory govOpts = cf.getFixedGovernanceOpts();
        return Party.PartyOptions({
            name: defaultName,
            symbol: defaultSymbol,
            governance: PartyGovernance.GovernanceOpts({
                hosts: govOpts.hosts,
                voteDuration: govOpts.voteDuration,
                executionDelay: govOpts.executionDelay,
                passThresholdBps: govOpts.passThresholdBps,
                totalVotingPower: uint96(finalPrice),
                feeBps: defaultGovernanceOpts.feeBps,
                feeRecipient: defaultGovernanceOpts.feeRecipient
            })
        });
    }

    function _getAmountWithoutSplit(uint256 contribution)
        private
        view
        returns (uint256 r)
    {
        return (uint256(1e4 - defaultSplitBps) * contribution) / 1e4;
    }

    function _getAmountWithSplit(uint256 contribution, uint256 totalContributions)
        private
        view
        returns (uint256 r)
    {
        return _getAmountWithoutSplit(contribution) +
            (uint256(defaultSplitBps) * totalContributions + (1e4 - 1)) / 1e4;
    }

    function test_creation_initialContribution_withDelegate() public {
        _expectEmit0();
        address initialContributor = _randomAddress();
        address initialDelegate = _randomAddress();
        uint256 initialContribution = _randomRange(1, 1 ether);
        vm.deal(address(this), initialContribution);
        emit Contributed(initialContributor, initialContribution, initialDelegate, 0);
        TestableCrowdfund cf = new TestableCrowdfund{value: initialContribution }(
            globals,
            Crowdfund.CrowdfundOptions({
                name: defaultName,
                symbol: defaultSymbol,
                splitRecipient: defaultSplitRecipient,
                splitBps: defaultSplitBps,
                initialContributor: initialContributor,
                initialDelegate: initialDelegate,
                gateKeeper: defaultGateKeeper,
                gateKeeperId: defaultGateKeeperId,
                governanceOpts: defaultGovernanceOpts
            })
        );
        (
            uint256 ethContributed,
            uint256 ethUsed,
            uint256 ethOwed,
            uint256 votingPower
        ) = cf.getContributorInfo(initialContributor);
        assertEq(ethContributed, initialContribution);
        assertEq(ethUsed, 0);
        assertEq(ethOwed, 0);
        assertEq(votingPower, 0);
        assertEq(uint256(cf.totalContributions()), initialContribution);
        assertEq(cf.delegationsByContributor(initialContributor), initialDelegate);
    }

    function test_creation_initialContribution_noValue() public {
        address initialContributor = _randomAddress();
        TestableCrowdfund cf = new TestableCrowdfund(
            globals,
            Crowdfund.CrowdfundOptions({
                name: defaultName,
                symbol: defaultSymbol,
                splitRecipient: defaultSplitRecipient,
                splitBps: defaultSplitBps,
                initialContributor: initialContributor,
                initialDelegate: initialContributor,
                gateKeeper: defaultGateKeeper,
                gateKeeperId: defaultGateKeeperId,
                governanceOpts: defaultGovernanceOpts
            })
        );
        (
            uint256 ethContributed,
            uint256 ethUsed,
            uint256 ethOwed,
            uint256 votingPower
        ) = cf.getContributorInfo(initialContributor);
        assertEq(ethContributed, 0);
        assertEq(ethUsed, 0);
        assertEq(ethOwed, 0);
        assertEq(votingPower, 0);
        assertEq(uint256(cf.totalContributions()), 0);
        assertEq(cf.delegationsByContributor(initialContributor), address(0));
    }

    // One person contributes, their entire contribution is used.
    function testWin_oneContributor() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        assertEq(cf.totalContributions(), 1e18);
        // set up a win using contributor1's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(cf, 1e18),
            erc721Tokens,
            erc721TokenIds
        );
        Party party_ = cf.testSetWon(
            1e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        assertEq(address(party_), address(party));
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            1e18,
            delegate1
        );
        cf.burn(contributor1);
        // contributor1 gets back none of their contribution
        assertEq(contributor1.balance, 0);
    }

    // Two contributors, their entire combined contribution is used.
    function testWin_twoContributors() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        address payable contributor2 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // contributor2 contributes 0.5 ETH
        vm.deal(contributor2, 0.5e18);
        vm.prank(contributor2);
        cf.contribute{ value: contributor2.balance }(delegate2, "");
        assertEq(cf.totalContributions(), 1.5e18);
        // set up a win using everyone's total contributions
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(cf, 1.5e18),
            erc721Tokens,
            erc721TokenIds
        );
        Party party_ = cf.testSetWon(
            1.5e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        assertEq(address(party_), address(party));
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            1e18,
            delegate1
        );
        cf.burn(contributor1);
        // contributor1 gets back none of their contribution
        assertEq(contributor1.balance, 0);
        // contributor2 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor2,
            0.5e18,
            delegate2
        );
        cf.burn(contributor2);
        // contributor2 gets back none of their contribution
        assertEq(contributor2.balance, 0);
    }

    // two contribute but only part of the second contributor's ETH is used.
    function testWin_twoContributors_partialContributionUsed() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        address payable contributor2 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // contributor2 contributes 0.5 ETH
        vm.deal(contributor2, 0.5e18);
        vm.prank(contributor2);
        cf.contribute{ value: contributor2.balance }(delegate2, "");
        // set up a win using half of contributor2's total contributions
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(cf, 1.25e18),
            erc721Tokens,
            erc721TokenIds
        );
        cf.testSetWon(
            1.25e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            1e18,
            delegate1
        );
        cf.burn(contributor1);
        // contributor1 gets back none of their contribution
        assertEq(contributor1.balance, 0);
        // contributor2 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor2,
            0.25e18,
            delegate2
        );
        cf.burn(contributor2);
        // contributor2 gets back half their contribution
        assertEq(contributor2.balance, 0.25e18);
    }

    // two contribute, with contributor1 sandwiching contributor2
    // and only part of the total is used.
    function testWin_twoContributorsSandiwched_partialContributionUsed() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        address payable contributor2 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // contributor2 contributes 0.5 ETH
        vm.deal(contributor2, 0.5e18);
        vm.prank(contributor2);
        cf.contribute{ value: contributor2.balance }(delegate2, "");
        // contributor1 contributes 0.25 ETH
        vm.deal(contributor1, 0.25e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // set up a win using half of contributor2's total contributions
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(cf, 1.65e18),
            erc721Tokens,
            erc721TokenIds
        );
        cf.testSetWon(
            1.65e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            1.15e18,
            delegate1
        );
        cf.burn(contributor1);
        // contributor1 gets back some of their second contribution
        assertEq(contributor1.balance, 0.1e18);
        // contributor2 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor2,
            0.5e18,
            delegate2
        );
        cf.burn(contributor2);
        // contributor2 gets back none of their contribution
        assertEq(contributor2.balance, 0);
    }

    // One person contributes, final price is zero (should never happen IRL)
    function testWin_oneContributor_zeroFinalPrice() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        assertEq(cf.totalContributions(), 1e18);
        // set up a win with 0 final price
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(cf, 0),
            erc721Tokens,
            erc721TokenIds
        );
        Party party_ = cf.testSetWon(
            0,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        assertEq(address(party_), address(party));
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit Burned(
            contributor1,
            0,
            1e18,
            0
        );
        cf.burn(contributor1);
        // contributor1 gets back all of their contribution
        assertEq(contributor1.balance, 1e18);
    }

    // Two contributors, CF loses
    function testLoss_twoContributors() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        address payable contributor2 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // contributor2 contributes 0.5 ETH
        vm.deal(contributor2, 0.5e18);
        vm.prank(contributor2);
        cf.contribute{ value: contributor2.balance }(delegate2, "");
        assertEq(cf.totalContributions(), 1.5e18);
        // set up a loss
        cf.testSetLifeCycle(Crowdfund.CrowdfundLifecycle.Lost);
        assertEq(address(cf.party()), address(0));
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit Burned(contributor1, 0, 1e18, 0);
        cf.burn(contributor1);
        // contributor1 gets back their contribution
        assertEq(contributor1.balance, 1e18);
        // contributor2 burns tokens
        vm.expectEmit(false, false, false, true);
        emit Burned(contributor2, 0, 0.5e18, 0);
        cf.burn(contributor2);
        // contributor2 gets back their contribution
        assertEq(contributor2.balance, 0.5e18);
    }

    // One person contributes, their entire contribution is used, they try to burn twice.
    function testWin_oneContributor_cannotBurnTwice() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // set up a win using contributor1's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        cf.testSetWon(
            1e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        cf.burn(contributor1);
        // They try to burn again.
        vm.expectRevert(abi.encodeWithSelector(
            CrowdfundNFT.AlreadyBurnedError.selector,
            contributor1,
            uint256(uint160(address(contributor1)))
        ));
        cf.burn(contributor1);
    }

    // One person contributes, part of their contribution is used, they try to burn twice.
    function testWin_oneContributor_partialContributionUsed_cannotBurnTwice() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // set up a win using contributor1's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        cf.testSetWon(
            0.5e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        cf.burn(contributor1);
        // contributor1 gets back part of their contribution
        assertEq(contributor1.balance, 0.5e18);
        // They try to burn again.
        vm.expectRevert(abi.encodeWithSelector(
            CrowdfundNFT.AlreadyBurnedError.selector,
            contributor1,
            uint256(uint160(address(contributor1)))
        ));
        cf.burn(contributor1);
    }

    // One person contributes, CF loses, they try to burn twice.
    function testLoss_oneContributor_cannotBurnTwice() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // Set up a loss.
        cf.testSetLifeCycle(Crowdfund.CrowdfundLifecycle.Lost);
        assertEq(address(cf.party()), address(0));
        // contributor1 burns tokens
        cf.burn(contributor1);
        // contributor1 gets back their contribution
        assertEq(contributor1.balance, 1e18);
        // They try to burn again.
        vm.expectRevert(abi.encodeWithSelector(
            CrowdfundNFT.AlreadyBurnedError.selector,
            contributor1,
            uint256(uint160(address(contributor1)))
        ));
        cf.burn(contributor1);
    }

    // One person contributes, CF is busy, they try to burn.
    function testBusy_oneContributor_cannotBurn() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // Set up a loss.
        cf.testSetLifeCycle(Crowdfund.CrowdfundLifecycle.Busy);
        // They try to burn again.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Busy
        ));
        cf.burn(contributor1);
    }

    // Trying to pass in different governance opts after winning.
    function testWin_cannotChangeGovernanceOpts() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        // set up a win using contributor1's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        unchecked {
            uint256 r = _randomUint256() % 4;
            if (r == 0) {
                defaultGovernanceOpts.hosts[0] = _randomAddress();
            } else if (r == 1) {
                defaultGovernanceOpts.voteDuration += 1;
            } else if (r == 2) {
                defaultGovernanceOpts.executionDelay += 1;
            } else if (r == 3) {
                defaultGovernanceOpts.passThresholdBps += 1;
            }
        }
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.InvalidGovernanceOptionsError.selector,
            cf.hashFixedGovernanceOpts(defaultGovernanceOpts),
            cf.governanceOptsHash()
        ));
        cf.testSetWon(
            1e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
    }

    // Split recipient set but does not contribute.
    // Half of contributor's contribution used.
    function testWin_nonParticipatingSplitRecipient() public {
        address payable splitRecipient = _randomAddress();
        defaultSplitRecipient = splitRecipient;
        TestableCrowdfund cf = _createCrowdfund(0);

        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // set up a win using half of contributor1's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        cf.testSetWon(
            0.5e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            _getAmountWithoutSplit(0.5e18),
            delegate1 // will use last contribute() delegate
        );
        cf.burn(contributor1);
        // contributor1 gets back half of their contribution
        assertEq(contributor1.balance, 0.5e18);
        // split recipient burns
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            splitRecipient,
            _getAmountWithSplit(0, 0.5e18),
            splitRecipient
        );
        cf.burn(splitRecipient);
    }

    // Split recipient set and contributes.
    // All of contributor1's contrubtion used.
    // Part of split recipient's contribution used.
    function testWin_participatingSplitRecipient_splitRecipientContributionPartiallyUsed() public {
        address payable splitRecipient = _randomAddress();
        defaultSplitRecipient = splitRecipient;
        TestableCrowdfund cf = _createCrowdfund(0);

        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // recipient contributes 0.5 ETH
        vm.deal(splitRecipient, 0.5e18);
        vm.prank(splitRecipient);
        cf.contribute{ value: splitRecipient.balance }(delegate2, "");
        // set up a win using half of split recipient's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        cf.testSetWon(
            1.25e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            _getAmountWithoutSplit(1e18),
            delegate1 // will use last contribute() delegate
        );
        cf.burn(contributor1);
        // contributor1 gets back none of their contribution
        assertEq(contributor1.balance, 0);
        // split recipient burns
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            splitRecipient,
            _getAmountWithSplit(0.25e18, 1.25e18),
            delegate2
        );
        cf.burn(splitRecipient);
    }

    // Split recipient set and contributes.
    // All of contributor1's contrubtion used.
    // NONE of split recipient's contribution used.
    function testWin_participatingSplitRecipient_splitRecipientContributionNotUsed() public {
        address payable splitRecipient = _randomAddress();
        defaultSplitRecipient = splitRecipient;
        TestableCrowdfund cf = _createCrowdfund(0);

        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        // recipient contributes 0.5 ETH
        vm.deal(splitRecipient, 0.5e18);
        vm.prank(splitRecipient);
        cf.contribute{ value: splitRecipient.balance }(delegate2, "");
        // set up a win using none of split recipient's total contribution
        (IERC721[] memory erc721Tokens, uint256[] memory erc721TokenIds) =
            _createTokens(address(cf), 2);
        cf.testSetWon(
            1e18,
            defaultGovernanceOpts,
            erc721Tokens,
            erc721TokenIds
        );
        // contributor1 burns tokens
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            contributor1,
            _getAmountWithoutSplit(1e18),
            delegate1 // will use last contribute() delegate
        );
        cf.burn(contributor1);
        // contributor1 gets back none of their contribution
        assertEq(contributor1.balance, 0);
        // split recipient burns
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(cf),
            splitRecipient,
            _getAmountWithSplit(0, 1e18),
            delegate2
        );
        cf.burn(splitRecipient);
    }

    // Two contributors, one is blocked
    function test_twoContributors_oneBlockedByGateKeeper() public {
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address payable contributor1 = _randomAddress();
        address payable contributor2 = _randomAddress();

        AllowListGateKeeper gk = new AllowListGateKeeper();
        bytes12 gateId = gk.createGate(keccak256(abi.encodePacked(contributor1)));
        defaultGateKeeper = gk;
        defaultGateKeeperId = gateId;
        TestableCrowdfund cf = _createCrowdfund(0);

        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, abi.encode(new bytes32[](0)));

        // contributor2 contributes 0.5 ETH but will be blocked by the gatekeeper.
        vm.deal(contributor2, 0.5e18);
        vm.prank(contributor2);
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.NotAllowedByGateKeeperError.selector,
            contributor2,
            defaultGateKeeper,
            gateId,
            abi.encode(new bytes32[](0))
        ));
        cf.contribute{ value: contributor2.balance }(delegate2, abi.encode(new bytes32[](0)));
    }

    // test nft renderer
    function test_nftRenderer() public {
        TestableCrowdfund cf = _createCrowdfund(0);
        address delegate1 = _randomAddress();
        address payable contributor1 = _randomAddress();
        // contributor1 contributes 1 ETH
        vm.deal(contributor1, 1e18);
        vm.prank(contributor1);
        cf.contribute{ value: contributor1.balance }(delegate1, "");
        string memory tokenURI = cf.tokenURI(uint256(uint160(address(contributor1))));
        assertTrue(bytes(tokenURI).length > 0);
    }

    function test_contractURI() external {
        TestableCrowdfund cf = _createCrowdfund(0);

        string memory contractURI = cf.contractURI();

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function test_supportsInterface() external {
        TestableCrowdfund cf = _createCrowdfund(0);
        cf.supportsInterface(0x01ffc9a7); // EIP165
        cf.supportsInterface(0x80ac58cd); // ERC721
        cf.supportsInterface(0x150b7a02); // ERC721Receiver
    }
}
