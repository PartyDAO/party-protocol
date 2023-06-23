// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../party/Party.sol";

/// @notice Helpers for getting data from contract off-chain.
contract PartyHelpers {
    enum CrowdfundType {
        Bid,
        Buy,
        CollectionBuy,
        CollectionBatchBuy
    }

    struct MemberAndDelegate {
        address member;
        address delegate;
    }

    struct MemberAndVotingPower {
        address member;
        uint96 votingPower;
    }

    struct NftInfo {
        uint256 tokenId;
        address owner;
        uint256 intrinsicVotingPower;
    }

    // Token address used to indicate ETH.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /////////////////////////////
    // PartyGovernance helpers //
    /////////////////////////////

    /// @notice Get the current delegate for each member in `members`
    function getCurrentDelegates(
        Party party,
        address[] calldata members
    ) external view returns (MemberAndDelegate[] memory membersAndDelegates) {
        membersAndDelegates = new MemberAndDelegate[](members.length);
        for (uint256 i; i < members.length; ++i) {
            membersAndDelegates[i] = MemberAndDelegate({
                member: members[i],
                delegate: party.delegationsByVoter(members[i])
            });
        }
    }

    /// @notice Get the total voting power of each voter in `voters` at a timestamp.
    function getVotingPowersAt(
        Party party,
        address[] calldata voters,
        uint40 timestamp,
        uint256[] calldata indexes
    ) external view returns (MemberAndVotingPower[] memory memberAndVotingPower) {
        memberAndVotingPower = new MemberAndVotingPower[](voters.length);
        for (uint256 i; i < voters.length; ++i) {
            memberAndVotingPower[i] = MemberAndVotingPower({
                member: voters[i],
                votingPower: party.getVotingPowerAt(voters[i], timestamp, indexes[i])
            });
        }
    }

    ////////////////////////////////
    // PartyGovernanceNFT helpers //
    ////////////////////////////////

    /// @notice Get the owner and intrinsic voting power of each governance nft in a range
    function getNftInfos(
        Party party,
        uint256 startTokenId,
        uint256 endTokenId
    ) external view returns (NftInfo[] memory nftInfos) {
        uint256 count = endTokenId - startTokenId + 1;
        {
            uint256 tokenCount = party.tokenCount();
            if (count > tokenCount) {
                count = tokenCount + 1 - startTokenId;
            }
        }

        nftInfos = new NftInfo[](count);

        for (uint256 i; i < count; ++i) {
            uint256 currIndex = startTokenId + i;
            address owner = party.ownerOf(currIndex);
            uint256 intrinsicVotingPower = party.votingPowerByTokenId(currIndex);
            nftInfos[i] = NftInfo({
                intrinsicVotingPower: intrinsicVotingPower,
                owner: owner,
                tokenId: currIndex
            });
        }
    }

    /// @notice Get the owner and intrinsic voting power of each governance nft in a list
    function getNftInfosBatch(
        Party party,
        uint256[] memory tokenIds
    ) external view returns (NftInfo[] memory nftInfos) {
        uint256 numTokens = tokenIds.length;
        nftInfos = new NftInfo[](numTokens);

        for (uint256 i; i < numTokens; ++i) {
            uint256 currItem = tokenIds[i];
            address owner = party.ownerOf(currItem);
            uint256 intrinsicVotingPower = party.votingPowerByTokenId(currItem);
            nftInfos[i] = NftInfo({
                intrinsicVotingPower: intrinsicVotingPower,
                owner: owner,
                tokenId: currItem
            });
        }
    }

    function getRageQuitWithdrawAmounts(
        Party party,
        uint256[] calldata tokenIds,
        IERC20[] calldata withdrawTokens
    ) external view returns (uint256[] memory withdrawAmounts) {
        withdrawAmounts = new uint256[](withdrawTokens.length);

        uint16 feeBps_ = party.feeBps();
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            uint256 shareOfVotingPower = party.getVotingPowerShareOf(tokenId);

            for (uint256 j; j < withdrawTokens.length; ++j) {
                // Calculate amount to withdraw.
                IERC20 token = withdrawTokens[j];

                uint256 balance = address(token) == ETH_ADDRESS
                    ? address(party).balance
                    : token.balanceOf(address(party));

                uint256 amount = (balance * shareOfVotingPower) / 1e18;

                // Take fee from amount.
                uint256 fee = (amount * feeBps_) / 1e4;

                // Sum up amount to withdraw.
                withdrawAmounts[j] += amount - fee;
            }
        }

        return withdrawAmounts;
    }
}
