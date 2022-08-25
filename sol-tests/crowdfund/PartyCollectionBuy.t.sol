// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/PartyCollectionBuy.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./TestERC721Vault.sol";

contract PartyCollectionBuyTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    event MockPartyFactoryMint(
        address caller,
        Party party,
        address owner,
        uint256 amount,
        address delegate
    );

    string defaultName = 'PartyCollectionBuy';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint128 defaultMaxPrice = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    PartyCrowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    TestERC721Vault erc721Vault = new TestERC721Vault();
    PartyCollectionBuy partyCollectionBuyImpl;
    Party party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();
        partyCollectionBuyImpl = new PartyCollectionBuy(globals);
    }

    function _createCrowdfund(address[] memory hosts, uint128 initialContribution)
        private
        returns (PartyCollectionBuy pb, PartyCrowdfund.FixedGovernanceOpts memory governanceOpts)
    {
        governanceOpts.hosts = hosts;

        pb = PartyCollectionBuy(payable(address(new Proxy{ value: initialContribution }(
            partyCollectionBuyImpl,
            abi.encodeCall(
                PartyCollectionBuy.initialize,
                PartyCollectionBuy.PartyCollectionBuyOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    nftContract: erc721Vault.token(),
                    duration: defaultDuration,
                    maximumPrice: defaultMaxPrice,
                    splitRecipient: defaultSplitRecipient,
                    splitBps: defaultSplitBps,
                    initialContributor: address(this),
                    initialDelegate: defaultInitialDelegate,
                    gateKeeper: defaultGateKeeper,
                    gateKeeperId: defaultGateKeeperId,
                    governanceOpts: governanceOpts
                })
            )
        ))));
    }

    function _createExpectedPartyOptions(address[] memory hosts, uint256 finalPrice)
        private
        view
        returns (Party.PartyOptions memory opts)
    {
        return Party.PartyOptions({
            name: defaultName,
            symbol: defaultSymbol,
            governance: PartyGovernance.GovernanceOpts({
                hosts: hosts,
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
        // Create a PartyCollectionBuy instance.
        address host = _randomAddress();
        (
            PartyCollectionBuy pb,
            PartyCrowdfund.FixedGovernanceOpts memory governanceOpts
        ) = _createCrowdfund(_toAddressArray(host), 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        pb.contribute{ value: contributor.balance }(delegate, "");
        // Buy the token.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(pb),
            address(pb),
            _createExpectedPartyOptions(_toAddressArray(host), 0.5e18),
            _toERC721Array(erc721Vault.token()),
            _toUint256Array(tokenId)
        );
        vm.prank(host);
        Party party_ = pb.buy(
            tokenId,
            payable(address(erc721Vault)),
            0.5e18,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            governanceOpts
        );
        assertEq(address(party), address(party_));
        // Burn contributor's NFT, mock minting governance tokens and returning
        // unused contribution.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryMint(
            address(pb),
            party_,
            contributor,
            0.5e18,
            delegate
        );
        pb.burn(contributor);
        assertEq(contributor.balance, 0.5e18);
    }

    function testOnlyHostCanBuy() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a PartyCollectionBuy instance.
        address host = _randomAddress();
        (
            PartyCollectionBuy pb,
            PartyCrowdfund.FixedGovernanceOpts memory governanceOpts
        ) = _createCrowdfund(_toAddressArray(host), 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        pb.contribute{ value: contributor.balance }(delegate, "");
        // Buy the token as a non-host contributor and expect revert.
        vm.expectRevert(PartyCollectionBuy.OnlyPartyHostError.selector);
        vm.prank(contributor);
        Party party_ = pb.buy(
            tokenId,
            payable(address(erc721Vault)),
            0.5e18,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            governanceOpts
        );
    }

    // The call to buy() does not transfer the token.
    function testBuyDoesNotTransferToken() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a PartyCollectionBuy instance.
        address host = _randomAddress();
        (
            PartyCollectionBuy pb,
            PartyCrowdfund.FixedGovernanceOpts memory governanceOpts
        ) = _createCrowdfund(_toAddressArray(host), 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        pb.contribute{ value: contributor.balance }(delegate, "");
        // Pretend to buy the token.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyBuyBase.FailedToBuyNFTError.selector,
                erc721Vault.token(),
                tokenId
            )
        );
        vm.prank(host);
        pb.buy(
            tokenId,
            _randomAddress(), // Call random EOA, which will succeed but do nothing
            0.5e18,
            "",
            governanceOpts
        );
        assertTrue(pb.getCrowdfundLifecycle() == PartyCrowdfund.CrowdfundLifecycle.Active);
    }

    function testCannotReinitialize() public {
        ( PartyCollectionBuy pb,) = _createCrowdfund(new address[](0), 0);
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        PartyCollectionBuy.PartyCollectionBuyOptions memory opts;
        pb.initialize(opts);
    }
}
