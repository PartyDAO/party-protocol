// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { SetSignatureValidatorProposal } from "../../contracts/proposals/SetSignatureValidatorProposal.sol";
import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";
import { OffChainSignatureValidator } from "../../contracts/signature-validators/OffChainSignatureValidator.sol";

contract SetSignatureValidatorProposalTest is SetupPartyHelper {
    constructor() SetupPartyHelper(false) {}

    event SignatureValidatorSet(bytes32 indexed hash, IERC1271 indexed signatureValidator);

    function testSetValidatorForHash() public {
        PartyGovernance.Proposal memory proposal = _createTestProposal(
            keccak256("hello"),
            IERC1271(address(1))
        );

        uint256 proposalId = _proposeAndPassProposal(proposal);

        vm.expectEmit(true, true, true, true);
        emit SignatureValidatorSet(keccak256("hello"), IERC1271(address(1)));
        _executeProposal(proposalId, proposal);

        assertEq(_getValidatorForHash(keccak256("hello")), address(1));
    }

    function testSetValidatorToAddress1() public {
        // Set validator for hash(hello) to be always valid
        _setValidatorForHash(keccak256("hello"), IERC1271(address(1)));

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            keccak256("hello"),
            "0x"
        );
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);
    }

    function testNoValidatorSetOnChainValidation() public {
        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            keccak256("hello2"),
            "0x"
        );
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), 0);
    }

    function testValidatorSetToExternalValidator() public {
        MockValdidator validator = new MockValdidator();
        _setValidatorForHash(keccak256("hello"), validator);

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            keccak256("hello"),
            "0x"
        );
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);

        // Will also call that validator for off-chain call
        vm.prank(address(0), address(0));
        (success, res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);
    }

    function testOverrideDefaultOffChainValidator() public {
        MockValdidator validator = new MockValdidator();
        _setValidatorForHash(0, validator);

        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            keccak256("hello"),
            "0x"
        );
        vm.startPrank(address(0), address(0));
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertTrue(success);
        assertEq(abi.decode(res, (bytes4)), IERC1271.isValidSignature.selector);
    }

    function testDefaultOffChainValidatorCalled() public {
        bytes memory staticCallData = abi.encodeWithSelector(
            IERC1271.isValidSignature.selector,
            keccak256("hello"),
            "0x"
        );
        vm.startPrank(address(0), address(0));
        // Validation should fail (malformed entry)
        (bool success, ) = address(party).staticcall(staticCallData);
        assertFalse(success);
    }

    function _setValidatorForHash(bytes32 hash, IERC1271 validator) internal {
        PartyGovernance.Proposal memory proposal = _createTestProposal(hash, validator);
        uint256 proposalId = _proposeAndPassProposal(proposal);

        vm.expectEmit(true, true, true, true);
        emit SignatureValidatorSet(hash, validator);
        _executeProposal(proposalId, proposal);
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
}

/// @notice Mock validator that always returns valid signature
contract MockValdidator is IERC1271 {
    function isValidSignature(bytes32, bytes memory) external pure override returns (bytes4) {
        return MockValdidator.isValidSignature.selector;
    }
}
