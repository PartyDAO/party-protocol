// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

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

    ////////////////////////////
    // Crowdfund helpers //
    ////////////////////////////

    function getCrowdfundType(
        address globals,
        address crowdfund
    ) external view returns (CrowdfundType) {
        IGlobals g = IGlobals(globals);
        Implementation cf = Implementation(crowdfund);
        address impl = cf.IMPL();
        if (impl == g.getImplementation(LibGlobals.GLOBAL_AUCTION_CF_IMPL).IMPL()) {
            return CrowdfundType.Bid;
        } else if (impl == g.getImplementation(LibGlobals.GLOBAL_BUY_CF_IMPL).IMPL()) {
            return CrowdfundType.Buy;
        } else if (impl == g.getImplementation(LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL).IMPL()) {
            return CrowdfundType.CollectionBuy;
        } else if (
            impl == g.getImplementation(LibGlobals.GLOBAL_COLLECTION_BATCH_BUY_CF_IMPL).IMPL()
        ) {
            return CrowdfundType.CollectionBatchBuy;
        }
        revert("PartyHelpers::Unknown CrowdfundType");
    }

    /////////////////////////////
    // PartyGovernance helpers //
    /////////////////////////////

    /// @notice Get the current delegate for each member in `members`
    function getCurrentDelegates(
        address party,
        address[] calldata members
    ) external view returns (MemberAndDelegate[] memory membersAndDelegates) {
        Party p = Party(payable(party));
        membersAndDelegates = new MemberAndDelegate[](members.length);
        for (uint256 i; i < members.length; ++i) {
            membersAndDelegates[i] = MemberAndDelegate({
                member: members[i],
                delegate: p.delegationsByVoter(members[i])
            });
        }
    }

    /// @notice Get the total voting power of each voter in `voters` at a timestamp.
    function getVotingPowersAt(
        address party,
        address[] calldata voters,
        uint40 timestamp,
        uint256[] calldata indexes
    ) external view returns (MemberAndVotingPower[] memory memberAndVotingPower) {
        Party p = Party(payable(party));
        memberAndVotingPower = new MemberAndVotingPower[](voters.length);
        for (uint256 i; i < voters.length; ++i) {
            memberAndVotingPower[i] = MemberAndVotingPower({
                member: voters[i],
                votingPower: p.getVotingPowerAt(voters[i], timestamp, indexes[i])
            });
        }
    }

    ////////////////////////////////
    // PartyGovernanceNFT helpers //
    ////////////////////////////////

    /// @notice Get the owner and intrinsic voting power of each governance nft in a range
    function getNftInfos(
        address party,
        uint256 startTokenId,
        uint256 endTokenId
    ) external view returns (NftInfo[] memory nftInfos) {
        Party p = Party(payable(party));
        uint256 count = endTokenId - startTokenId + 1;
        {
            uint256 tokenCount = p.tokenCount();
            if (count > tokenCount) {
                count = tokenCount + 1 - startTokenId;
            }
        }

        nftInfos = new NftInfo[](count);

        for (uint256 i; i < count; ++i) {
            uint256 currIndex = startTokenId + i;
            address owner = p.ownerOf(currIndex);
            uint256 intrinsicVotingPower = p.votingPowerByTokenId(currIndex);
            nftInfos[i] = NftInfo({
                intrinsicVotingPower: intrinsicVotingPower,
                owner: owner,
                tokenId: currIndex
            });
        }
    }
}
