// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/BuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

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

    event MockMint(
        address caller,
        address owner,
        uint256 amount,
        address delegate
    );

    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);

    string defaultName = 'BuyCrowdfund';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint96 defaultMaxPrice = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    PartyCrowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    TestERC721Vault erc721Vault = new TestERC721Vault();
    BuyCrowdfund partyBuyImpl;
    MockParty party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();
        partyBuyImpl = new BuyCrowdfund(globals);
    }

    function setUp() public {
    }

    function _createCrowdfund(
        uint256 tokenId,
        uint96 initialContribution
    )
        private
        returns (BuyCrowdfund pb)
    {
        pb = BuyCrowdfund(payable(address(new Proxy{ value: initialContribution }(
            partyBuyImpl,
            abi.encodeCall(
                BuyCrowdfund.initialize,
                BuyCrowdfund.PartyBuyOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    nftContract: erc721Vault.token(),
                    nftTokenId: tokenId,
                    duration: defaultDuration,
                    maximumPrice: defaultMaxPrice,
                    splitRecipient: defaultSplitRecipient,
                    splitBps: defaultSplitBps,
                    initialContributor: address(this),
                    initialDelegate: defaultInitialDelegate,
                    gateKeeper: defaultGateKeeper,
                    gateKeeperId: defaultGateKeeperId,
                    governanceOpts: defaultGovernanceOpts
                })
            )
        ))));
    }

    function _createExpectedPartyOptions(uint256 finalPrice)
        private
        view
        returns (Party.PartyOptions memory opts)
    {
        return Party.PartyOptions({
            name: defaultName,
            symbol: defaultSymbol,
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
        BuyCrowdfund pb = _createCrowdfund(tokenId, 0);
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
            _createExpectedPartyOptions(0.5e18),
            _toERC721Array(erc721Vault.token()),
            _toUint256Array(tokenId)
        );
        Party party_ = pb.buy(
            payable(address(erc721Vault)),
            0.5e18,
            abi.encodeCall(erc721Vault.claim, (tokenId)),
            defaultGovernanceOpts
        );
        assertEq(address(party), address(party_));
        // Burn contributor's NFT, mock minting governance tokens and returning
        // unused contribution.
        vm.expectEmit(false, false, false, true);
        emit MockMint(
            address(pb),
            contributor,
            0.5e18,
            delegate
        );
        pb.burn(contributor);
        assertEq(contributor.balance, 0.5e18);
    }

    // The call to buy() does not transfer the token.
    function testBuyDoesNotTransferToken() public {
        uint256 tokenId = erc721Vault.mint();
        // Create a BuyCrowdfund instance.
        BuyCrowdfund pb = _createCrowdfund(tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        pb.contribute{ value: contributor.balance }(delegate, "");
        // Pretend to buy the token.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.FailedToBuyNFTError.selector,
                erc721Vault.token(),
                tokenId
            )
        );
        pb.buy(
            _randomAddress(), // Call random EOA, which will succeed but do nothing
            0.5e18,
            "",
            defaultGovernanceOpts
        );
        assertTrue(pb.getCrowdfundLifecycle() == PartyCrowdfund.CrowdfundLifecycle.Active);
    }

    function testCannotReinitialize() public {
        uint256 tokenId = erc721Vault.mint();
        BuyCrowdfund pb = _createCrowdfund(tokenId, 0);
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        BuyCrowdfund.PartyBuyOptions memory opts;
        pb.initialize(opts);
    }

    function test_creation_initialContribution() public {
        uint256 tokenId = erc721Vault.mint();
        uint256 initialContribution = _randomRange(1, 1 ether);
        address initialContributor = _randomAddress();
        address initialDelegate = _randomAddress();
        vm.deal(address(this), initialContribution);
        emit Contributed(initialContributor, initialContribution, initialDelegate, 0);
        BuyCrowdfund(payable(address(new Proxy{ value: initialContribution }(
            partyBuyImpl,
            abi.encodeCall(
                BuyCrowdfund.initialize,
                BuyCrowdfund.PartyBuyOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    nftContract: erc721Vault.token(),
                    nftTokenId: tokenId,
                    duration: defaultDuration,
                    maximumPrice: defaultMaxPrice,
                    splitRecipient: defaultSplitRecipient,
                    splitBps: defaultSplitBps,
                    initialContributor: initialContributor,
                    initialDelegate: initialDelegate,
                    gateKeeper: defaultGateKeeper,
                    gateKeeperId: defaultGateKeeperId,
                    governanceOpts: defaultGovernanceOpts
                })
            )
        ))));
    }
}
