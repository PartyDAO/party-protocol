// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Party.sol";

contract PartyHelpers {
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
        returns (address[] memory delegates)
    {
        Party p = Party(payable(party));
        delegates = new address[](members.length);
        for (uint256 i = 0; i < members.length;) {
            delegates[i] = p.delegationsByVoter(members[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the total voting power of each voter in `voters` at a timestamp.
    function getVotingPowersAt(address party, address[] calldata voters, uint40 timestamp)
        external
        view
        returns (uint96[] memory votingPowers)
    {
        Party p = Party(payable(party));
        votingPowers = new uint96[](voters.length);
        // todo: should we turn an array of voting powers or an array of { uint256 address; uint96 votingPower; }
        for (uint256 i = 0; i < voters.length;) {
            votingPowers[i] = p.getVotingPowerAt(voters[i], timestamp);
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
