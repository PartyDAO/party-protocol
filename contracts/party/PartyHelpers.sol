// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Party.sol";

contract PartyHelpers {
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

    /////////////////////////////
    // PartyGovernance helpers //
    /////////////////////////////

    /// @notice Get the current delegate for each member in `members`
    function getCurrentDelegates(address party, address[] calldata members)
        external
        view
        returns (MemberAndDelegate[] memory membersAndDelegates)
    {
        Party p = Party(payable(party));
        membersAndDelegates = new MemberAndDelegate[](members.length);
        for (uint256 i = 0; i < members.length;) {
            membersAndDelegates[i] = MemberAndDelegate({
                member: members[i],
                delegate: p.delegationsByVoter(members[i])
            });
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the total voting power of each voter in `voters` at a timestamp.
    function getVotingPowersAt(address party, address[] calldata voters, uint40 timestamp)
        external
        view
        returns (MemberAndVotingPower[] memory memberAndVotingPower)
    {
        Party p = Party(payable(party));
        memberAndVotingPower = new MemberAndVotingPower[](voters.length);
        for (uint256 i = 0; i < voters.length;) {
            memberAndVotingPower[i] = MemberAndVotingPower({
                member: voters[i],
                votingPower: p.getVotingPowerAt(voters[i], timestamp)
            });
            unchecked {
                ++i;
            }
        }
    }


    ////////////////////////////////
    // PartyGovernanceNFT helpers //
    ////////////////////////////////

    /// @notice Get the current delegate for each member in `members`
    function getNftInfos(address party, uint256 startIndex, uint256 endIndex)
        external
        view
        returns (NftInfo[] memory nftInfos)
    {
        Party p = Party(payable(party));
        {
            uint256 tokenCount = p.tokenCount();
            if (endIndex > tokenCount) {
                endIndex = tokenCount;
            }
        }

        nftInfos = new NftInfo[](endIndex - startIndex + 1);

        for (uint256 i = startIndex; i <= endIndex;) {
            address owner = p.ownerOf(i);
            uint256 intrinsicVotingPower = p.votingPowerByTokenId(i);
            nftInfos[i - startIndex] = NftInfo({
                intrinsicVotingPower: intrinsicVotingPower,
                owner: owner,
                tokenId: i
            });
            unchecked {
                ++i;
            }
        }
    }
}
