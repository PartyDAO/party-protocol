// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/CollectionBuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "./TestERC721Vault.sol";

contract CollectionBuyCrowdfundTest is Test, TestUtils {
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

    string defaultName = "CollectionBuyCrowdfund";
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
    CollectionBuyCrowdfund collectionBuyCrowdfundImpl;
    MockParty party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();
        collectionBuyCrowdfundImpl = new CollectionBuyCrowdfund(globals);
    }

    function _createCrowdfund(
        address[] memory hosts,
        uint96 initialContribution
    )
        private
        returns (CollectionBuyCrowdfund cf, Crowdfund.FixedGovernanceOpts memory governanceOpts)
    {
        governanceOpts.hosts = hosts;

        cf = CollectionBuyCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        collectionBuyCrowdfundImpl,
                        abi.encodeCall(
                            CollectionBuyCrowdfund.initialize,
                            CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
                                nftContract: erc721Vault.token(),
                                duration: defaultDuration,
                                maximumPrice: defaultMaxPrice,
                                splitRecipient: defaultSplitRecipient,
                                splitBps: defaultSplitBps,
                                initialContributor: address(this),
                                initialDelegate: defaultInitialDelegate,
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: defaultGateKeeper,
                                gateKeeperId: defaultGateKeeperId,
                                governanceOpts: governanceOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function _createExpectedPartyOptions(
        address[] memory hosts,
        uint256 finalPrice
    ) private view returns (Party.PartyOptions memory opts) {
        return
            Party.PartyOptions({
                name: defaultName,
                symbol: defaultSymbol,
                customizationPresetId: 0,
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
        // Create a CollectionBuyCrowdfund instance.
        address host = _randomAddress();
        (
            CollectionBuyCrowdfund cf,
            Crowdfund.FixedGovernanceOpts memory governanceOpts
        ) = _createCrowdfund(_toAddressArray(host), 0);
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
            _createExpectedPartyOptions(_toAddressArray(host), 0.5e18),
            _toERC721Array(erc721Vault.token()),
            _toUint256Array(tokenId)
        );
        vm.prank(host);
        Party party_ = cf.buy(
            tokenId,
            payable(address(erc721Vault)),
            0.5e18,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            governanceOpts,
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

    function testOnlyHostCanBuy() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a CollectionBuyCrowdfund instance.
        address host = _randomAddress();
        (
            CollectionBuyCrowdfund cf,
            Crowdfund.FixedGovernanceOpts memory governanceOpts
        ) = _createCrowdfund(_toAddressArray(host), 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Buy the token as a non-host contributor and expect revert.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        vm.prank(contributor);
        cf.buy(
            tokenId,
            payable(address(erc721Vault)),
            0.5e18,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            governanceOpts,
            0
        );
    }

    // The call to buy() does not transfer the token.
    function testBuyDoesNotTransferToken() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a CollectionBuyCrowdfund instance.
        address host = _randomAddress();
        (
            CollectionBuyCrowdfund cf,
            Crowdfund.FixedGovernanceOpts memory governanceOpts
        ) = _createCrowdfund(_toAddressArray(host), 0);
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
        vm.prank(host);
        cf.buy(
            tokenId,
            _randomAddress(), // Call random EOA, which will succeed but do nothing
            0.5e18,
            "",
            governanceOpts,
            0
        );
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Active);
    }

    function testCannotReinitialize() public {
        (CollectionBuyCrowdfund cf, ) = _createCrowdfund(_toAddressArray(_randomAddress()), 0);
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions memory opts;
        cf.initialize(opts);
    }

    function test_creation_initialContribution() public {
        uint256 initialContribution = _randomRange(1, 1 ether);
        address initialContributor = _randomAddress();
        address initialDelegate = _randomAddress();
        defaultGovernanceOpts.hosts = _toAddressArray(_randomAddress());
        vm.deal(address(this), initialContribution);
        _expectEmit0();
        emit Contributed(
            address(this),
            initialContributor,
            initialContribution,
            initialDelegate,
            0
        );
        CollectionBuyCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        collectionBuyCrowdfundImpl,
                        abi.encodeCall(
                            CollectionBuyCrowdfund.initialize,
                            CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
                                nftContract: erc721Vault.token(),
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
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }
}
