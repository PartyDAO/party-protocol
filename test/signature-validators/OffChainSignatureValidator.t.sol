// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { SetSignatureValidatorProposal } from "../../contracts/proposals/SetSignatureValidatorProposal.sol";
import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { Party } from "../../contracts/party/Party.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";
import { OffChainSignatureValidator } from "../../contracts/signature-validators/OffChainSignatureValidator.sol";
import { Strings } from "openzeppelin/contracts/utils/Strings.sol";
import { LibGlobals } from "../../contracts/globals/LibGlobals.sol";

contract OffChainSignatureValidatorTest is SetupPartyHelper {
    constructor() SetupPartyHelper(false) {}

    OffChainSignatureValidator offChainGlobalValidator;

    event SigningThresholdBpsSet(
        Party indexed party,
        uint96 oldThresholdBps,
        uint96 newThresholdBps
    );

    function setUp() public override {
        setUpWithParams(
            SetupPartyHelper.SetupPartyParams({
                johnVotes: 1000,
                dannyVotes: 1000,
                steveVotes: 1,
                thisVotes: 1
            })
        );

        offChainGlobalValidator = OffChainSignatureValidator(
            globals.getAddress(LibGlobals.GLOBAL_OFF_CHAIN_SIGNATURE_VALIDATOR)
        );
    }

    function testOffChainMessageValidation() public {
        (bytes32 messageHash, bytes memory signature) = _signMessage(
            johnPk,
            "Hello World! nonce:1000"
        );

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );
        vm.startPrank(address(0), address(0));
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);
    }

    function testOffChainMessageValidationNotInParty() public {
        (bytes32 messageHash, bytes memory signature) = _signMessage(
            12345634,
            "Hello World! nonce:1000"
        );

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );
        vm.startPrank(address(0), address(0));

        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertFalse(success);
        _assertEqual(res, OffChainSignatureValidator.NotMemberOfParty.selector);
    }

    function testOffChainMessageValidationHashMismatch() public {
        bytes memory message = "hello world1";
        bytes memory encondedMessage = abi.encodePacked(message);
        bytes memory encodedPacket = abi.encodePacked(
            "\x19Ethereum Signed Message:\n",
            Strings.toString(encondedMessage.length),
            encondedMessage
        );
        bytes32 messageHash = keccak256(encodedPacket);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(johnPk, messageHash);
        message = "hello world2";
        bytes memory signature = abi.encodePacked(r, s, v, abi.encode(message));

        vm.startPrank(address(0), address(0));

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertFalse(success);
        _assertEqual(res, OffChainSignatureValidator.MessageHashMismatch.selector);
    }

    function testOffChainMessageValidationInsufficientVotingPower() public {
        (bytes32 messageHash, bytes memory signature) = _signMessage(
            johnPk,
            "Hello World! nonce:1000"
        );

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );

        vm.prank(address(party));
        vm.expectEmit(true, true, true, true);
        emit SigningThresholdBpsSet(party, 0, 5000);
        offChainGlobalValidator.setSigningThresholdBps(5000);

        vm.prank(address(0), address(0));
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertFalse(success);
        _assertEqual(res, OffChainSignatureValidator.InsufficientVotingPower.selector);

        vm.prank(address(party));
        offChainGlobalValidator.setSigningThresholdBps(4000);

        vm.prank(address(0), address(0));
        // Now sufficient
        (success, res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);
    }

    function testOffChainMessageValidationDelegatedLessThanOneBip() public {
        (bytes32 messageHash, bytes memory signature) = _signMessage(
            stevePk,
            "Hello World! nonce:1000"
        );

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );

        vm.prank(address(party));
        offChainGlobalValidator.setSigningThresholdBps(1000);

        vm.prank(address(0), address(0));
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertFalse(success);
        _assertEqual(res, OffChainSignatureValidator.InsufficientVotingPower.selector);
    }

    function testDelegatedNonPartyMemberCanSign() public {
        uint256 bobPk = 12345678;
        address bob = vm.addr(bobPk);

        (bytes32 messageHash, bytes memory signature) = _signMessage(
            bobPk,
            "Hello World! nonce:1000"
        );

        vm.prank(john);
        party.delegateVotingPower(bob);
        vm.roll(block.number + 10);

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );
        vm.startPrank(address(0), address(0));
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);

        // But john can still sign too
        (messageHash, signature) = _signMessage(johnPk, "Hello World! nonce:1000");
        staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            messageHash,
            signature
        );
        vm.startPrank(address(0), address(0));
        (success, res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);
    }

    function _signMessage(
        uint256 privateKey,
        string memory message
    ) internal pure returns (bytes32 messageHash, bytes memory signature) {
        bytes memory encondedMessage = abi.encodePacked(message);
        bytes memory encodedPacket = abi.encodePacked(
            "\x19Ethereum Signed Message:\n",
            Strings.toString(encondedMessage.length),
            encondedMessage
        );
        messageHash = keccak256(encodedPacket);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        signature = abi.encodePacked(r, s, v, message);
    }

    function _setValidatorForHash(bytes32 hash, IERC1271 validator) internal {
        PartyGovernance.Proposal memory proposal = _createTestProposal(hash, validator);
        _proposePassAndExecuteProposal(proposal);
    }

    function _createTestProposal(
        bytes32 hash,
        IERC1271 validator
    ) private pure returns (PartyGovernance.Proposal memory proposal) {
        SetSignatureValidatorProposal.SetSignatureValidatorProposalData
            memory data = SetSignatureValidatorProposal.SetSignatureValidatorProposalData({
                signatureHash: hash,
                signatureValidator: validator
            });

        proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.SetSignatureValidatorProposal)),
                data
            )
        });
    }

    function _getValidatorForHash(bytes32 hash) internal returns (address) {
        (bool success, bytes memory res) = address(party).staticcall(
            abi.encodeWithSelector(
                SetSignatureValidatorProposal.getSignatureValidatorForHash.selector,
                hash
            )
        );
        assertTrue(success);
        return abi.decode(res, (address));
    }

    function _assertEqual(bytes memory givenRevert, bytes4 expectedRevert) internal {
        bytes4 givenRevertParsed;
        assembly {
            givenRevertParsed := mload(add(givenRevert, 0x20))
        }
        assertEq(givenRevertParsed, expectedRevert);
    }
}
