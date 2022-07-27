// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Party.sol";

contract PartyHelpers {
    struct NftInfo {
        uint256 tokenId;
        address owner;
        uint256 intrinsicVotingPower;
    }

    Party party;

    constructor(address _party) {
        party = Party(payable(_party));
    }


    /////////////////////////////
    // PartyGovernance helpers //
    /////////////////////////////

    /// @notice Get the current delegate for each member in `members`
    function getCurrentDelegates(address[] memory members)
        external
        view
        returns (address[] memory delegates)
    {
        delegates = new address[](members.length);
        for (uint256 i = 0; i < members.length;) {
            delegates[i] = party.delegationsByVoter(members[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the total voting power of each voter in `voters` at a timestamp.
    function getVotingPowersAt(address[] memory voters, uint40 timestamp)
        public
        view
        returns (uint96[] memory votingPowers)
    {
        votingPowers = new uint96[](voters.length);
        // todo: should we turn an array of voting powers or an array of { uint256 address; uint96 votingPower; }
        for (uint256 i = 0; i < voters.length;) {
            votingPowers[i] = party.getVotingPowerAt(voters[i], timestamp);
            unchecked {
                ++i;
            }
        }
    }


    ////////////////////////////////
    // PartyGovernanceNFT helpers //
    ////////////////////////////////

    /// @notice Get the current delegate for each member in `members`
    function getNftInfos(uint256 startIndex, uint256 endIndex)
        external
        view
        returns (NftInfo[] memory nftInfos)
    {
        // ensure startIndex and endIndex are in bounds
        if (endIndex < startIndex) {
            uint256 temp = endIndex;
            endIndex = startIndex;
            startIndex = temp;
        }
        if (startIndex == 0) {
            startIndex = 1;
        }
        uint256 tokenCount = party.tokenCount();
        if (endIndex > tokenCount) {
            endIndex = tokenCount;
        }

        nftInfos = new NftInfo[](endIndex - startIndex + 1);

        for (uint256 i = startIndex; i <= endIndex;) {
            address owner = party.ownerOf(i);
            uint256 intrinsicVotingPower = party.votingPowerByTokenId(i);
            nftInfos[i - 1] = NftInfo({
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
