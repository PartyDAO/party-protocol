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
    mapping (uint256 => address payable) _owners;
    mapping (uint256 => uint256) _shares;

    function mintShare(address payable owner, uint256 tokenId, uint256 share)
        external
        returns (address payable owner_, uint256 tokenId_, uint256 share_)
    {
        _owners[tokenId] = owner;
        _shares[tokenId] = share;
        return (owner, tokenId, share);
    }

    function ownerOf(uint256 tokenId)
        external
        view
        returns (address)
    {
        return _owners[tokenId];
    }

    function getDistributionShareOf(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return _shares[tokenId];
    }
}

contract TokenDistributorUnitTest is Test, TestUtils {

    event DistributionCreated(
        ITokenDistributorParty indexed party,
        ITokenDistributor.DistributionInfo info
    );
    event DistributionClaimed(
        ITokenDistributorParty indexed party,
        uint256 indexed partyTokenId,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId,
        uint256 amount
    );
    event DistributionFeeClaimed(
        ITokenDistributorParty indexed party,
        address indexed feeRecipient,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId,
        uint256 amount
    );

    address constant ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address payable constant DEFAULT_FEE_RECIPIENT = payable(0xfeEFEEfeefEeFeefEEFEEfEeFeefEEFeeFEEFEeF);
    uint16 constant DEFAULT_FEE_BPS = 0.02e4;

    Globals globals;
    TokenDistributor distributor;
    TestParty party;
    DummyERC20 erc20 = new DummyERC20();
    DummyERC1155 erc1155 = new DummyERC1155();

    constructor() {
        globals = new Globals(address(this));
        distributor = new TokenDistributor(globals);
        party = new TestParty();
    }

    // Should fail if supply is zero.
    function test_createNativeDistribution_zeroSupply() external {
        vm.expectRevert(abi.encodeWithSelector(
            ITokenDistributor.InvalidDistributionSupplyError.selector,
            0
        ));
        vm.prank(address(party));
        distributor.createNativeDistribution(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // Should fail if supply is zero.
    function test_createErc20Distribution_zeroSupply() external {
        vm.expectRevert(abi.encodeWithSelector(
            ITokenDistributor.InvalidDistributionSupplyError.selector,
            0
        ));
        vm.prank(address(party));
        distributor.createErc20Distribution(erc20, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // Should fail if supply is zero.
    function test_createErc1155Distribution_zeroSupply() external {
        vm.expectRevert(abi.encodeWithSelector(
            ITokenDistributor.InvalidDistributionSupplyError.selector,
            0
        ));
        vm.prank(address(party));
        distributor.createErc1155Distribution(erc1155, 0, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // Should fail if feeBps is greater than 1e4.
    function test_createNativeDistribution_feeBpsGreaterThan100Percent() external {
        vm.expectRevert(abi.encodeWithSelector(
            ITokenDistributor.InvalidFeeBpsError.selector,
            1e4 + 1
        ));
        vm.prank(address(party));
        distributor.createNativeDistribution(DEFAULT_FEE_RECIPIENT, 1e4 + 1);
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
                tokenId: 0,
                memberSupply: uint128(_computeLessFees(supply, DEFAULT_FEE_BPS)),
                fee: uint128(_computeFees(supply, DEFAULT_FEE_BPS)),
                feeRecipient: DEFAULT_FEE_RECIPIENT
            })
        );
        vm.deal(address(party), supply);
        vm.prank(address(party));
        distributor.createNativeDistribution{ value: supply }(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
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
                tokenId: 0,
                memberSupply: uint128(_computeLessFees(supply, DEFAULT_FEE_BPS)),
                fee: uint128(_computeFees(supply, DEFAULT_FEE_BPS)),
                feeRecipient: DEFAULT_FEE_RECIPIENT
            })
        );
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        distributor.createErc20Distribution(erc20, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    function test_createErc1155Distribution_works() external {
        uint256 tokenId = _randomUint256();
        uint256 supply = _randomUint256() % 1e18;
        _expectEmit1();
        emit DistributionCreated(
            party,
            ITokenDistributor.DistributionInfo({
                distributionId: 1,
                party: party,
                tokenType: ITokenDistributor.TokenType.Erc1155,
                token: address(erc1155),
                tokenId: tokenId,
                memberSupply: uint128(_computeLessFees(supply, DEFAULT_FEE_BPS)),
                fee: uint128(_computeFees(supply, DEFAULT_FEE_BPS)),
                feeRecipient: DEFAULT_FEE_RECIPIENT
            })
        );
        erc1155.deal(address(distributor), tokenId, supply);
        vm.prank(address(party));
        distributor.createErc1155Distribution(erc1155, tokenId, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
    }

    // One member with 100% of shares, default fees.
    function test_claimNative_oneMemberWithFees() external {
        (address member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        uint256 claimAmount = _computeLessFees(supply, DEFAULT_FEE_BPS);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenId,
            ITokenDistributor.TokenType.Native,
            ETH_TOKEN_ADDRESS,
            0,
            claimAmount
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(member.balance, claimAmount);
    }

    // One member with 100% of shares, default fees.
    function test_claimErc20_oneMemberWithFees() external {
        (address member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createErc20Distribution(erc20, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        uint256 claimAmount = _computeLessFees(supply, DEFAULT_FEE_BPS);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenId,
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            0,
            claimAmount
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(erc20.balanceOf(member), claimAmount);
    }

    // One member with 100% of shares, default fees.
    function test_claimErc1155_oneMemberWithFees() external {
        (address member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        uint256 tokenId = _randomUint256();
        erc1155.deal(address(distributor), tokenId, supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createErc1155Distribution(erc1155, tokenId, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        uint256 claimAmount = _computeLessFees(supply, DEFAULT_FEE_BPS);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenId,
            ITokenDistributor.TokenType.Erc1155,
            address(erc1155),
            tokenId,
            claimAmount
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(erc1155.balanceOf(member, tokenId), claimAmount);
    }

    // One member with 100% of shares, no fees.
    function test_claimNative_oneMemberNoFees() external {
        (address member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(payable(0), 0);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenId,
            ITokenDistributor.TokenType.Native,
            ETH_TOKEN_ADDRESS,
            0,
            supply
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(member.balance, supply);
    }

    // One member with 100% of shares, no fees.
    function test_claimErc20_oneMemberNoFees() external {
        (address member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createErc20Distribution(erc20, payable(0), 0);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenId,
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            0,
            supply
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(erc20.balanceOf(member), supply);
    }

    // One member with 100% of shares, no fees.
    function test_claimErc1155_oneMemberNoFees() external {
        (address member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        uint256 tokenId = _randomUint256();
        erc1155.deal(address(distributor), tokenId, supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createErc1155Distribution(erc1155, tokenId, payable(0), 0);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenId,
            ITokenDistributor.TokenType.Erc1155,
            address(erc1155),
            tokenId,
            supply
        );
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        // Member should have supply less fees.
        assertEq(erc1155.balanceOf(member, tokenId), supply);
    }

    // Multiple members, default fees.
    function test_claimNative_multiMemberWithFees() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, uint256[] memory shares) =
            _mintRandomShares(_randomUint256() % 8 + 1);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        uint256 memberIdx = _randomUint256() % members.length;
        uint256 claimAmount = _computeMemberShare(_computeLessFees(supply, DEFAULT_FEE_BPS), shares[memberIdx]);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenIds[memberIdx],
            ITokenDistributor.TokenType.Native,
            ETH_TOKEN_ADDRESS,
            0,
            claimAmount
        );
        vm.prank(members[memberIdx]);
        distributor.claim(di, memberTokenIds[memberIdx]);
        // Member should have supply less fees.
        assertEq(members[memberIdx].balance, claimAmount);
    }

    // Multiple members, default fees.
    function test_claimErc20_multiMemberWithFees() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, uint256[] memory shares) =
            _mintRandomShares(_randomUint256() % 8 + 1);
        uint256 supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createErc20Distribution(erc20, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        uint256 memberIdx = _randomUint256() % members.length;
        uint256 claimAmount = _computeMemberShare(_computeLessFees(supply, DEFAULT_FEE_BPS), shares[memberIdx]);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenIds[memberIdx],
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            0,
            claimAmount
        );
        vm.prank(members[memberIdx]);
        distributor.claim(di, memberTokenIds[memberIdx]);
        // Member should have supply less fees.
        assertEq(erc20.balanceOf(members[memberIdx]), claimAmount);
    }

    // Multiple members, default fees.
    function test_claimErc1155_multiMemberWithFees() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, uint256[] memory shares) =
            _mintRandomShares(_randomUint256() % 8 + 1);
        uint256 supply = _randomUint256() % 1e18;
        uint256 tokenId = _randomUint256();
        erc1155.deal(address(distributor), tokenId, supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createErc1155Distribution(erc1155, tokenId, DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        uint256 memberIdx = _randomUint256() % members.length;
        uint256 claimAmount = _computeMemberShare(_computeLessFees(supply, DEFAULT_FEE_BPS), shares[memberIdx]);
        _expectEmit2();
        emit DistributionClaimed(
            party,
            memberTokenIds[memberIdx],
            ITokenDistributor.TokenType.Erc1155,
            address(erc1155),
            tokenId,
            claimAmount
        );
        vm.prank(members[memberIdx]);
        distributor.claim(di, memberTokenIds[memberIdx]);
        // Member should have supply less fees.
        assertEq(erc1155.balanceOf(members[memberIdx], tokenId), claimAmount);
    }

    // Ensure that a naughty party that has shares totaling more than 100% does not
    // cannot claim more than their supply. The claim logic is shared by other
    // token types so we shouldn't need to test those separately.
    function test_claimNative_partyWithSharesMoreThan100Percent() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, ) =
            _mintRandomShares(2, 1.01e18); // 101% total shares
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(payable(0), 0);
        // Deal more ETH to the distributor to attempt to steal.
        vm.deal(address(distributor), address(distributor).balance + supply);
        uint256 balanceBeforeClaim = address(distributor).balance;
        for (uint256 i = 0; i < members.length; ++i) {
            vm.prank(members[i]);
            distributor.claim(di, memberTokenIds[i]);
        }
        assertEq(address(distributor).balance, balanceBeforeClaim - supply);
    }

    // Ensure that the supply for the next distribution is correct after
    // claiming a previous distribution (stored balances accounting is correct).
    function test_claimNative_supplyForNextDistributionIsCorrect() external {
        (address payable[] memory members, uint256[] memory memberTokenIds, ) =
            _mintRandomShares(2);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(payable(0), 0);
        assertEq(di.memberSupply, supply);
        // Claim.
        for (uint256 i = 0; i < members.length; ++i) {
            vm.prank(members[i]);
            distributor.claim(di, memberTokenIds[i]);
        }

        // Create a new distribution.
        uint256 supply2 = _randomUint256() % 1e18;
        vm.deal(address(distributor), address(distributor).balance + supply2);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di2) =
            distributor.createNativeDistribution(payable(0), 0);
        assertEq(di2.memberSupply, supply2);
    }

    // Ensure that the supply for the next distribution is correct after
    // claiming the fee for a previous distribution (stored balances accounting is correct).
    function test_claimFee_supplyForNextDistributionIsCorrect() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        assertEq(di.memberSupply, _computeLessFees(supply, DEFAULT_FEE_BPS));
        // Claim fee.
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, _randomAddress());

        // Create a new distribution.
        uint256 supply2 = _randomUint256() % 1e18;
        vm.deal(address(distributor), address(distributor).balance + supply2);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di2) =
            distributor.createNativeDistribution(payable(0), 0);
        assertEq(di2.memberSupply, supply2);
    }

    // Different token types use different stored balances.
    function test_distributionsHaveSeparateBalances() external {
        uint256 nativeSupply = _randomUint256() % 1e18;
        (ITokenDistributor.DistributionInfo memory nativeDi) =
            distributor.createNativeDistribution{ value: nativeSupply }(payable(0), 0);
        assertEq(nativeDi.memberSupply, nativeSupply);

        uint256 erc20Supply = _randomUint256() % 1e18;
        erc20.deal(address(distributor), erc20Supply);
        (ITokenDistributor.DistributionInfo memory erc20Di) =
            distributor.createErc20Distribution(erc20, payable(0), 0);
        assertEq(erc20Di.memberSupply, erc20Supply);

        uint256 erc1155Supply = _randomUint256() % 1e18;
        uint256 tokenId = _randomUint256();
        erc1155.deal(address(distributor), tokenId, erc1155Supply);
        (ITokenDistributor.DistributionInfo memory erc1155Di) =
            distributor.createErc1155Distribution(erc1155, tokenId, payable(0), 0);
        assertEq(erc1155Di.memberSupply, erc1155Supply);
    }

    // Different 1155 tokenIds use different stored balances.
    function test_createErc1155Distribution_tokenIdsHaveSeparateBalances() external {
        uint256 tokenId1 = _randomUint256();
        uint256 erc1155Supply1 = _randomUint256() % 1e18;
        erc1155.deal(address(distributor), tokenId1, erc1155Supply1);
        uint256 tokenId2 = _randomUint256();
        uint256 erc1155Supply2 = _randomUint256() % 1e18;
        erc1155.deal(address(distributor), tokenId2, erc1155Supply2);
        (ITokenDistributor.DistributionInfo memory di1) =
            distributor.createErc1155Distribution(erc1155, tokenId1, payable(0), 0);
        assertEq(di1.memberSupply, erc1155Supply1);
        (ITokenDistributor.DistributionInfo memory di2) =
            distributor.createErc1155Distribution(erc1155, tokenId2, payable(0), 0);
        assertEq(di2.memberSupply, erc1155Supply2);
    }

    // Cannot claim with different distribution info.
    function test_claimNative_cannotChangeDistributionInfo() external {
        (address payable member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(distributor), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(payable(0), 0);

        assertEq(abi.encode(di).length / 32, 8);
        // Try replacing each field and claiming.
        for (uint256 i = 0; i < 8; ++i) {
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
                di_.tokenId = _randomUint256();
            } else if (i == 6) {
                di_.memberSupply = uint128(_randomUint256() % type(uint128).max);
            } else if (i == 7) {
                di_.fee = uint128(_randomUint256() % type(uint128).max);
            }
            vm.expectRevert(abi.encodeWithSelector(
                ITokenDistributor.InvalidDistributionInfoError.selector,
                di_
            ));
            vm.prank(member);
            distributor.claim(di, memberTokenId);
        }
    }

    // Someone other than the party token owner tries to claim for that token.
    function test_claimNative_cannotClaimFromNonOwnerOfPartyToken() external {
        (address payable member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution{ value: supply }(payable(0), 0);
        address notMember = _randomAddress();
        vm.prank(notMember);
        vm.expectRevert(abi.encodeWithSelector(
            ITokenDistributor.MustOwnTokenError.selector,
            notMember,
            member,
            memberTokenId
        ));
        distributor.claim(di, memberTokenId);
    }

    // Someone other than the party token owner tries to claim for that token.
    function test_claimNative_cannotClaimTwice() external {
        (address payable member, uint256 memberTokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution{ value: supply }(payable(0), 0);
        vm.prank(member);
        distributor.claim(di, memberTokenId);
        vm.prank(member);
        vm.expectRevert(abi.encodeWithSelector(
            ITokenDistributor.DistributionAlreadyClaimedByTokenError.selector,
            di.distributionId,
            memberTokenId
        ));
        distributor.claim(di, memberTokenId);
    }

    function test_claimFee_cannotClaimIfNotFeeRecipient() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution{ value: supply }(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        address notFeeRecipient = _randomAddress();
        vm.prank(notFeeRecipient);
        vm.expectRevert(abi.encodeWithSelector(
           ITokenDistributor.OnlyFeeRecipientError.selector,
           notFeeRecipient,
           di.feeRecipient
        ));
        distributor.claimFee(di, _randomAddress());
    }

    function test_claimFee_cannotClaimTwice() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution{ value: supply }(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, _randomAddress());
        vm.prank(DEFAULT_FEE_RECIPIENT);
        vm.expectRevert(abi.encodeWithSelector(
           ITokenDistributor.DistributionFeeAlreadyClaimedError.selector,
           di.distributionId
        ));
        distributor.claimFee(di, _randomAddress());
    }

    function test_claimFee_canClaimFeeToFeeRecipient() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution{ value: supply }(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, DEFAULT_FEE_RECIPIENT);
        assertEq(DEFAULT_FEE_RECIPIENT.balance, di.fee);
    }

    function test_claimFee_canClaimFeeToOther() external {
        uint256 supply = _randomUint256() % 1e18;
        vm.deal(address(party), supply);
        vm.prank(address(party));
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution{ value: supply }(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        address payable dest = _randomAddress();
        vm.prank(DEFAULT_FEE_RECIPIENT);
        distributor.claimFee(di, dest);
        assertEq(dest.balance, di.fee);
    }

    function _computeMemberShare(uint256 total, uint256 share)
        private
        pure
        returns (uint256)
    {
        return total * share / 1e18;
    }

    function _computeFees(uint256 total, uint16 feeBps)
        private
        pure
        returns (uint256)
    {
        return total * feeBps / 1e4;
    }

    function _computeLessFees(uint256 total, uint16 feeBps)
        private
        pure
        returns (uint256)
    {
        return total - _computeFees(total, feeBps);
    }

    function _mintRandomShares(uint256 count)
        private
        returns (
            address payable[] memory owners,
            uint256[] memory tokenIds,
            uint256[] memory shares
        )
    {
        return _mintRandomShares(count, 1e18);
    }

    function _mintRandomShares(uint256 count, uint256 total)
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
        for (uint256 i = 0; i < count; ++i) {
            sharesSum += shares[i] = _randomUint256() % 1e18;
        }
        for (uint256 i = 0; i < count; ++i) {
            shares[i] = shares[i] * total / sharesSum;
        }
        for (uint256 i = 0; i < count; ++i) {
            owners[i] = _randomAddress();
            tokenIds[i] = _randomUint256();
            party.mintShare(owners[i], tokenIds[i], shares[i]);
        }
    }
}
