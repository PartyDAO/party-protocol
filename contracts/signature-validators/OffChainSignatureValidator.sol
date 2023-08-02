// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { Strings } from "openzeppelin/contracts/utils/Strings.sol";
import { Party } from "../party/Party.sol";

/// @notice Contract that by default validates off-chain signatures for parties
contract OffChainSignatureValidator is IERC1271 {
    error NotMemberOfParty();
    error InsufficientVotingPower();
    error MessageHashMismatch();

    /// @notice Event emmitted when signing threshold updated
    event SigningThresholdBpsSet(
        Party indexed party,
        uint96 oldThresholdBps,
        uint96 newThresholdBps
    );

    /// @notice Mapping of party to signing threshold BPS
    mapping(Party party => uint96 thresholdBps) public signingThersholdBps;

    /// @notice Validate an off-chain signature
    /// @dev This function requires `signature` to be a valid EOA signature from a member in the
    /// party with sufficient voting power. The raw message must be abi encoded and appended to
    /// the end of the signature. EIP-712 typed signatures are not supported.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            // First word of signature after size contains r
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            // v is one byte which starts after s. type is uint8 so extra data will be ignored
            v := mload(add(signature, 0x41))
        }

        bytes memory message;
        assembly {
            // Raw message data begins after v. Overwriting part of s and v with size of `message`
            message := add(signature, 0x41)
            mstore(message, sub(mload(signature), 0x41))
        }

        // Recreate the message pre-hash from the raw data
        bytes memory encodedPacket = abi.encodePacked(
            "\x19Ethereum Signed Message:\n",
            Strings.toString(message.length),
            message
        );
        if (keccak256(encodedPacket) != hash) {
            revert MessageHashMismatch();
        }

        Party party = Party(payable(msg.sender));
        address signer = ecrecover(hash, v, r, s);
        uint96 signerVotingPowerBps = party.getVotingPowerAt(signer, uint40(block.timestamp)) *
            10000;

        if (signerVotingPowerBps == 0 && party.balanceOf(signer) == 0) {
            // Must own a party card or be delegatated voting power
            revert NotMemberOfParty();
        }

        uint96 totalVotingPower = party.getGovernanceValues().totalVotingPower;
        uint96 thresholdBps = signingThersholdBps[party];

        // Either threshold is 0 or signer votes above threshold
        if (
            thresholdBps == 0 ||
            (signerVotingPowerBps > totalVotingPower &&
                signerVotingPowerBps / totalVotingPower >= thresholdBps)
        ) {
            return IERC1271.isValidSignature.selector;
        }

        revert InsufficientVotingPower();
    }

    /// @notice Set the signing threshold BPS for the party to validate off-chain signatures
    /// @param thresholdBps The new threshold BPS
    function setSigningThresholdBps(uint96 thresholdBps) external {
        Party party = Party(payable(msg.sender));
        emit SigningThresholdBpsSet(party, signingThersholdBps[party], thresholdBps);
        signingThersholdBps[party] = thresholdBps;
    }
}
