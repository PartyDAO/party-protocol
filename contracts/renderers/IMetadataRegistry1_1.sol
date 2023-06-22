// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

// Interface for `MetadataRegistry` contract from v1.1 of the protocol.
interface IMetadataRegistry1_1 {
    function customPartyMetadataByCrowdfund(
        address crowdfundAddress
    )
        external
        view
        returns (
            string memory customName,
            string memory customDescription,
            string memory customImage
        );
}
