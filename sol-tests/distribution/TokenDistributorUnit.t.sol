// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/distribution/TokenDistributor.sol";
import "../../contracts/distribution/ITokenDistributorParty.sol";
import "../../contracts/globals/Globals.sol";

import "../TestUtils.sol";
import "../DummyERC20.sol";
import "../DummyERC1155.sol";

contract TestParty is ITokenDistributorParty {
    mapping(uint256 => address payable) _owners;
    mapping(uint256 => uint256) _shares;

    function mintShare(
        address payable owner,
        uint256 partyTokenId,
        uint256 share
    ) external returns (address payable owner_, uint256 tokenId_, uint256 share_) {
        _owners[partyTokenId] = owner;
        _shares[partyTokenId] = share;
        return (owner, partyTokenId, share);
    }

    function ownerOf(uint256 partyTokenId) external view returns (address) {
        return _owners[partyTokenId];
    }

    function getDistributionShareOf(uint256 partyTokenId) external view returns (uint256) {
        return _shares[partyTokenId];
    }
}

contract TestTokenDistributorHash is TokenDistributor(IGlobals(address(0)), 0) {
    function getDistributionHash(
        DistributionInfo memory info
    ) external pure returns (bytes32 hash) {
        return _getDistributionHash(info);
    }
}

// A ERC777-like token that is itself also the malicious actor.
contract ReenteringToken is ERC20("ReenteringToken", "RET", 18) {
    TokenDistributor distributor;

    constructor(TokenDistributor _distributor) {
        distributor = _distributor;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        // Reenter into distributor to create another ERC20 distribution. Mimics
        // how ERC777 tokens will call a `tokensToSend` hook on transfer which
        // can implement arbitrary logic. Here, we use it to create a new
        // distribution before the state update triggered by another claiming
        // from distribution (which this is attempting to steal from) has been
        // updated.
        distributor.createErc20Distribution(
            IERC20(address(this)),
            ITokenDistributorParty(address(0)),
            payable(address(0)),
            0
        );
        return super.transfer(to, amount);
    }
}

contract TokenDistributorUnitTest is Test, TestUtils {
    event DistributionCreated(
        ITokenDistributorParty indexed party,
        ITokenDistributor.DistributionInfo info
    );
    event DistributionFeeClaimed(
        ITokenDistributorParty indexed party,
        address indexed feeRecipient,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 amount
    );
    event DistributionClaimedByPartyToken(
        ITokenDistributorParty indexed party,
        uint256 indexed partyTokenId,
        address indexed owner,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 amountClaimed
    );

    address constant ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address payable constant DEFAULT_FEE_RECIPIENT =
        payable(0xfeEFEEfeefEeFeefEEFEEfEeFeefEEFeeFEEFEeF);
    uint16 constant DEFAULT_FEE_BPS = 0.02e4;

    Globals globals;
    TokenDistributor distributor;
    TestParty party;
    DummyERC20 erc20 = new DummyERC20();
    DummyERC1155 erc1155 = new DummyERC1155();

    constructor() {
        globals = new Globals(address(this));
        distributor = new TokenDistributor(globals, 0);
        party = new TestParty();
    }

    // Should fail if supply is zero.
    function test_createNativeDistribution_zeroSupply() external {
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.InvalidDistributionSupplyError.selector, 0)
        );
        vm.prank(address(party));
        distributor.createNativeDistribution(party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // Should fail if supply is zero.
    function test_createErc20Distribution_zeroSupply() external {
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.InvalidDistributionSupplyError.selector, 0)
        );
        vm.prank(address(party));
        distributor.createErc20Distribution(erc20, party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // Should fail if feeBps is greater than 1e4.
    function test_createNativeDistribution_feeBpsGreaterThan100Percent() external {
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributor.InvalidFeeBpsError.selector, 1e4 + 1)
        );
        vm.prank(address(party));
        distributor.createNativeDistribution(party, DEFAULT_FEE_RECIPIENT, 1e4 + 1);
    }

    function test_createNativeDistribution_works() external {
        uint256 supply = _randomUint256() % 1e18;
        _expectEmit1();
        emit DistributionCreated(
            party,
            ITokenDistributor.DistributionInfo({
                distributionId: 1,
                party: party,
                tokenType: ITokenDistributor.TokenType.Native,
                token: ETH_TOKEN_ADDRESS,
                memberSupply: uint128(_computeLessFees(supply, DEFAULT_FEE_BPS)),
                fee: uint128(_computeFees(supply, DEFAULT_FEE_BPS)),
                feeRecipient: DEFAULT_FEE_RECIPIENT
            })
        );
        vm.deal(address(party), supply);
        vm.prank(address(party));
        distributor.createNativeDistribution{ value: supply }(
            party,
            DEFAULT_FEE_RECIPIENT,
            DEFAULT_FEE_BPS
        );
    }

    function test_createErc20Distribution_works() external {
        uint256 supply = _randomUint256() % 1e18;
        _expectEmit1();
        emit DistributionCreated(
            party,
            ITokenDistributor.DistributionInfo({
                distributionId: 1,
                party: party,
                tokenType: ITokenDistributor.TokenType.Erc20,
                token: address(erc20),
                memberSupply: uint128(_computeLessFees(supply, DEFAULT_FEE_BPS)),
                fee: uint128(_computeFees(supply, DEFAULT_FEE_BPS)),
                feeRecipient: DEFAULT_FEE_RECIPIENT
            })
        );
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        distributor.createErc20Distribution(erc20, party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // One member with 100% of shares, default fees.
    function test_claimNative_oneMemberWithFees() external {
        (address member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            DEFAULT_FEE_RECIPIENT,
            DEFAULT_FEE_BPS
        );
        uint256 claimAmount = _computeLessFees(supply, DEFAULT_FEE_BPS);
        _expectEmit2();
        emit DistributionClaimedByPartyToken(
            party,
            memberTokenId,
            member,
            ITokenDistributor.TokenType.Native,
            ETH_TOKEN_ADDRESS,
            claimAmount
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(member.balance, claimAmount);
    }

    // One member with 100% of shares, default fees.
    function test_claimErc20_oneMemberWithFees() external {
        (address member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createErc20Distribution(
            erc20,
            party,
            DEFAULT_FEE_RECIPIENT,
            DEFAULT_FEE_BPS
        );
        uint256 claimAmount = _computeLessFees(supply, DEFAULT_FEE_BPS);
        _expectEmit2();
        emit DistributionClaimedByPartyToken(
            party,
            memberTokenId,
            member,
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            claimAmount
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(erc20.balanceOf(member), claimAmount);
    }

    // One member with 100% of shares, no fees.
    function test_claimNative_oneMemberNoFees() external {
        (address member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );
        _expectEmit2();
        emit DistributionClaimedByPartyToken(
            party,
            memberTokenId,
            member,
            ITokenDistributor.TokenType.Native,
            ETH_TOKEN_ADDRESS,
            supply
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(member.balance, supply);
    }

    // One member with 100% of shares, no fees.
    function test_claimErc20_oneMemberNoFees() external {
        (address member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createErc20Distribution(
            erc20,
            party,
            payable(0),
            0
        );
        _expectEmit2();
        emit DistributionClaimedByPartyToken(
            party,
            memberTokenId,
            member,
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            supply
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(erc20.balanceOf(member), supply);
    }

    // Multiple members, default fees.
    function test_claimNative_multiMemberWithFees() external {
        (
            address payable[] memory members,
            uint256[] memory memberTokenIds,
            uint256[] memory shares
        ) = _mintRandomShares((_randomUint256() % 8) + 1);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            DEFAULT_FEE_RECIPIENT,
            DEFAULT_FEE_BPS
        );
        uint256 memberIdx = _randomUint256() % members.length;
        uint256 claimAmount = _computeMemberShare(
            _computeLessFees(supply, DEFAULT_FEE_BPS),
            shares[memberIdx]
        );
        _expectEmit2();
        emit DistributionClaimedByPartyToken(
            party,
            memberTokenIds[memberIdx],
            members[memberIdx],
            ITokenDistributor.TokenType.Native,
            ETH_TOKEN_ADDRESS,
            claimAmount
        );
        vm.prank(members[memberIdx]);
        distributor.claim(di, memberTokenIds[memberIdx]);
        // Member should have supply less fees.
        assertEq(members[memberIdx].balance, claimAmount);
    }

    // Multiple members, default fees.
    function test_claimErc20_multiMemberWithFees() external {
        (
            address payable[] memory members,
            uint256[] memory memberTokenIds,
            uint256[] memory shares
        ) = _mintRandomShares((_randomUint256() % 8) + 1);
        uint256 supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createErc20Distribution(
            erc20,
            party,
            DEFAULT_FEE_RECIPIENT,
            DEFAULT_FEE_BPS
        );
        uint256 memberIdx = _randomUint256() % members.length;
        uint256 claimAmount = _computeMemberShare(
            _computeLessFees(supply, DEFAULT_FEE_BPS),
            shares[memberIdx]
        );
        _expectEmit2();
        emit DistributionClaimedByPartyToken(
            party,
            memberTokenIds[memberIdx],
            members[memberIdx],
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            claimAmount
        );
        vm.prank(members[memberIdx]);
        distributor.claim(di, memberTokenIds[memberIdx]);
        // Member should have supply less fees.
        assertEq(erc20.balanceOf(members[memberIdx]), claimAmount);
    }

    // Make sure small denomination distributions work as expected
    // (round up, first come first serve).
    function test_claimNative_smallDenomination() external {
        (address payable member1, address payable member2) = (_randomAddress(), _randomAddress());
        (uint256 memberTokenId1, uint256 memberTokenId2) = (_randomUint256(), _randomUint256());
        // Both have 50% share ratios.
        party.mintShare(member1, memberTokenId1, 0.5e18);
        party.mintShare(member2, memberTokenId2, 0.5e18);
        // 3 wei supply, does not divide cleanly.
        vm.deal(address(distributor), 3);
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );
        // member1 claims, getting 2 wei.
        vm.prank(member1);
        distributor.claim(di, memberTokenId1);
        assertEq(member1.balance, 2);
        // member2 claims, getting 1 wei (all that's left).
        vm.prank(member2);
        distributor.claim(di, memberTokenId2);
        assertEq(member2.balance, 1);
    }

    // Ensure that a naughty party that has shares totaling more than 100% does not
    // cannot claim more than their supply. The claim logic is shared by other
    // token types so we shouldn't need to test those separately.
    function test_claimNative_partyWithSharesMoreThan100Percent() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, ) = _mintRandomShares(
            2,
            1.01e18
        ); // 101% total shares
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );
        // Deal more ETH to the distributor to attempt to steal.
        vm.deal(address(distributor), address(distributor).balance + supply);
        uint256 balanceBeforeClaim = address(distributor).balance;
        for (uint256 i; i < members.length; ++i) {
            vm.prank(members[i]);
            distributor.claim(di, memberTokenIds[i]);
        }
        assertEq(address(distributor).balance, balanceBeforeClaim - supply);
    }

    // Ensure that the supply for the next distribution is correct after
    // claiming a previous distribution (stored balances accounting is correct).
    function test_claimNative_supplyForNextDistributionIsCorrect() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, ) = _mintRandomShares(
            2
        );
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );
        assertEq(di.memberSupply, supply);
        // Claim.
        for (uint256 i; i < members.length; ++i) {
            vm.prank(members[i]);
            distributor.claim(di, memberTokenIds[i]);
        }

        // Create a new distribution.
        uint256 supply2 = _randomUint256() % 1e18;
        vm.deal(address(distributor), address(distributor).balance + supply2);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di2 = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );
        assertEq(di2.memberSupply, supply2);
    }

    // Ensure that the supply for the next distribution is correct after
    // claiming the fee for a previous distribution (stored balances accounting is correct).
    function test_claimFee_supplyForNextDistributionIsCorrect() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            DEFAULT_FEE_RECIPIENT,
            DEFAULT_FEE_BPS
        );
        assertEq(di.memberSupply, _computeLessFees(supply, DEFAULT_FEE_BPS));
        // Claim fee.
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, _randomAddress());

        // Create a new distribution.
        uint256 supply2 = _randomUint256() % 1e18;
        vm.deal(address(distributor), address(distributor).balance + supply2);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di2 = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );
        assertEq(di2.memberSupply, supply2);
    }

    // Different token types use different stored balances.
    function test_distributionsHaveSeparateBalances() external {
        uint256 nativeSupply = _randomUint256() % 1e18;
        ITokenDistributor.DistributionInfo memory nativeDi = distributor.createNativeDistribution{
            value: nativeSupply
        }(party, payable(0), 0);
        assertEq(nativeDi.memberSupply, nativeSupply);

        uint256 erc20Supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), erc20Supply);
        ITokenDistributor.DistributionInfo memory erc20Di = distributor.createErc20Distribution(
            erc20,
            party,
            payable(0),
            0
        );
        assertEq(erc20Di.memberSupply, erc20Supply);
    }

    // Cannot claim with different distribution info.
    function test_claimNative_cannotChangeDistributionInfo() external {
        (address payable member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution(
            party,
            payable(0),
            0
        );

        assertEq(abi.encode(di).length / 32, 7);
        // Try replacing each field and claiming.
        for (uint256 i; i < 8; ++i) {
            ITokenDistributor.DistributionInfo memory di_ = di;
            if (i == 0) {
                di_.tokenType = ITokenDistributor.TokenType.Erc20;
            } else if (i == 1) {
                di_.distributionId = _randomUint256();
            } else if (i == 2) {
                TestParty fakeParty = new TestParty();
                fakeParty.mintShare(member, memberTokenId, 100e18);
                di_.party = fakeParty;
            } else if (i == 3) {
                di_.feeRecipient = _randomAddress();
            } else if (i == 4) {
                di_.token = _randomAddress();
            } else if (i == 5) {
                di_.memberSupply = uint128(_randomUint256() % type(uint128).max);
            } else if (i == 6) {
                di_.fee = uint128(_randomUint256() % type(uint128).max);
            }
            vm.expectRevert(
                abi.encodeWithSelector(TokenDistributor.InvalidDistributionInfoError.selector, di_)
            );
            vm.prank(member);
            distributor.claim(di, memberTokenId);
        }
    }

    // Someone other than the party token owner tries to claim for that token.
    function test_claimNative_cannotClaimFromNonOwnerOfPartyToken() external {
        (address payable member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution{
            value: supply
        }(party, payable(0), 0);
        address notMember = _randomAddress();
        vm.prank(notMember);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.MustOwnTokenError.selector,
                notMember,
                member,
                memberTokenId
            )
        );
        distributor.claim(di, memberTokenId);
    }

    // Someone other than the party token owner tries to claim for that token.
    function test_claimNative_cannotClaimTwice() external {
        (address payable member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution{
            value: supply
        }(party, payable(0), 0);
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        vm.prank(member);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.DistributionAlreadyClaimedByPartyTokenError.selector,
                di.distributionId,
                memberTokenId
            )
        );
        distributor.claim(di, memberTokenId);
    }

    function test_claimFee_cannotClaimIfNotFeeRecipient() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution{
            value: supply
        }(party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        address notFeeRecipient = _randomAddress();
        vm.prank(notFeeRecipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.OnlyFeeRecipientError.selector,
                notFeeRecipient,
                di.feeRecipient
            )
        );
        distributor.claimFee(di, _randomAddress());
    }

    function test_claimFee_cannotClaimTwice() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution{
            value: supply
        }(party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, _randomAddress());
        vm.prank(DEFAULT_FEE_RECIPIENT);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.DistributionFeeAlreadyClaimedError.selector,
                di.distributionId
            )
        );
        distributor.claimFee(di, _randomAddress());
    }

    function test_claimFee_canClaimFeeToFeeRecipient() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution{
            value: supply
        }(party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, DEFAULT_FEE_RECIPIENT);
        assertEq(DEFAULT_FEE_RECIPIENT.balance, di.fee);
    }

    function test_claimFee_canClaimFeeToOther() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createNativeDistribution{
            value: supply
        }(party, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        address payable dest = _randomAddress();
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, dest);
        assertEq(dest.balance, di.fee);
    }

    function testFail_cannotReceive1155Token() external {
        DummyERC1155 erc1155_ = new DummyERC1155();
        address owner = _randomAddress();
        erc1155_.deal(owner, 1337, 1e18);
        vm.prank(owner);
        erc1155_.safeTransferFrom(owner, address(distributor), 1337, 1, "");
    }

    function test_getDistributionHash() external {
        ITokenDistributor.DistributionInfo memory di = ITokenDistributor.DistributionInfo({
            tokenType: ITokenDistributor.TokenType(uint8(_randomUint256() % 2)),
            distributionId: _randomUint256(),
            party: ITokenDistributorParty(_randomAddress()),
            feeRecipient: _randomAddress(),
            token: _randomAddress(),
            memberSupply: uint128(_randomUint256()),
            fee: uint128(_randomUint256())
        });
        bytes32 expectedHash = keccak256(abi.encode(di));
        bytes32 actualHash = new TestTokenDistributorHash().getDistributionHash(di);
        assertEq(actualHash, expectedHash);
    }

    function test_reentrancy() external {
        IERC20 reenteringToken = new ReenteringToken(distributor);
        (address member, uint256 memberTokenId, ) = party.mintShare(
            _randomAddress(),
            _randomUint256(),
            100e18
        );
        uint256 supply = _randomUint256() % 1e18;
        deal(address(reenteringToken), address(distributor), supply);
        vm.prank(address(party));
        ITokenDistributor.DistributionInfo memory di = distributor.createErc20Distribution(
            reenteringToken,
            party,
            payable(address(0)),
            0
        );
        // Attempt reentrancy.
        vm.expectRevert(
            abi.encodeWithSelector(
                LibERC20Compat.TokenTransferFailedError.selector,
                reenteringToken,
                address(member),
                supply
            )
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
    }

    function _computeMemberShare(uint256 total, uint256 share) private pure returns (uint256) {
        return (total * share + (1e18 - 1)) / 1e18;
    }

    function _computeFees(uint256 total, uint16 feeBps) private pure returns (uint256) {
        return (total * feeBps) / 1e4;
    }

    function _computeLessFees(uint256 total, uint16 feeBps) private pure returns (uint256) {
        return total - _computeFees(total, feeBps);
    }

    function _mintRandomShares(
        uint256 count
    )
        private
        returns (
            address payable[] memory owners,
            uint256[] memory tokenIds,
            uint256[] memory shares
        )
    {
        return _mintRandomShares(count, 1e18);
    }

    function _mintRandomShares(
        uint256 count,
        uint256 total
    )
        private
        returns (
            address payable[] memory owners,
            uint256[] memory tokenIds,
            uint256[] memory shares
        )
    {
        owners = new address payable[](count);
        tokenIds = new uint256[](count);
        shares = new uint256[](count);
        uint256 sharesSum = 0;
        for (uint256 i; i < count; ++i) {
            sharesSum += shares[i] = _randomUint256() % 1e18;
        }
        for (uint256 i; i < count; ++i) {
            shares[i] = (shares[i] * total) / sharesSum;
        }
        for (uint256 i; i < count; ++i) {
            owners[i] = _randomAddress();
            tokenIds[i] = _randomUint256();
            party.mintShare(owners[i], tokenIds[i], shares[i]);
        }
    }
}
