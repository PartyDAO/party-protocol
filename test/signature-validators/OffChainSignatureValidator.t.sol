// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";
import { SetSignatureValidatorProposal } from "../../contracts/proposals/SetSignatureValidatorProposal.sol";
import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC721 } from "../../contracts/tokens/IERC721.sol";
import { GlobalsAdmin } from "../TestUsers.sol";
import { PartyFactory } from "../../contracts/party/PartyFactory.sol";
import { Globals } from "../../contracts/globals/Globals.sol";
import { Party } from "../../contracts/party/Party.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { IFractionalV1VaultFactory } from "../../contracts/proposals/vendor/FractionalV1.sol";
import { MockZoraReserveAuctionCoreEth } from "../proposals/MockZoraReserveAuctionCoreEth.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";
import { OffChainSignatureValidator } from "../../contracts/signature-validators/OffChainSignatureValidator.sol";
import { Strings } from "openzeppelin/contracts/utils/Strings.sol";

contract OffChainSignatureValidatorTest is Test {
    event SigningThresholdBipsSet(
        Party indexed party,
        uint96 oldThresholdBips,
        uint96 newThresholdBips
    );

    GlobalsAdmin globalsAdmin;
    Globals globals;
    Party party;
    PartyFactory partyFactory;
    OffChainSignatureValidator offChainGlobalValidator = new OffChainSignatureValidator();
    uint256 internal johnPk = 0xa11ce;
    uint256 internal dannyPk = 0xb0b;
    uint256 internal stevePk = 0xca1;
    address internal john = vm.addr(johnPk);
    address internal danny = vm.addr(dannyPk);
    address internal steve = vm.addr(stevePk);
    IERC721[] preciousTokens = new IERC721[](0);
    uint256[] preciousTokenIds = new uint256[](0);
    uint40 internal constant _EXECUTION_DELAY = 300;

    function setUp() public {
        globalsAdmin = new GlobalsAdmin();
        globals = globalsAdmin.globals();
        Party partyImpl = new Party(globals);
        address globalDaoWalletAddress = address(420);
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        ProposalExecutionEngine pe = new ProposalExecutionEngine(
            globals,
            new MockZoraReserveAuctionCoreEth(),
            IFractionalV1VaultFactory(address(0))
        );
        globalsAdmin.setProposalEng(address(pe));
        globalsAdmin.setOffChainSignatureValidator(address(offChainGlobalValidator));

        Party.PartyOptions memory opts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 20001;

        partyFactory = new PartyFactory();
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);
        party = partyFactory.createParty(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            0
        );
        party.mint(john, 10000, john);
        party.mint(danny, 10000, danny);
        party.mint(steve, 1, steve);
        vm.warp(block.timestamp + 100);
        vm.roll(block.number + 10);
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
        emit SigningThresholdBipsSet(party, 0, 5000);
        offChainGlobalValidator.setSigningThersholdBips(5000);

        vm.prank(address(0), address(0));
        (bool success, bytes memory res) = address(party).staticcall(staticCallData);
        assertFalse(success);
        _assertEqual(res, OffChainSignatureValidator.InsufficientVotingPower.selector);

        vm.prank(address(party));
        offChainGlobalValidator.setSigningThersholdBips(4000);

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
        offChainGlobalValidator.setSigningThersholdBips(1000);

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
        signature = abi.encodePacked(r, s, v, abi.encode(message));
    }

    function _setValidatorForHash(bytes32 hash, IERC1271 validator) internal {
        PartyGovernance.Proposal memory proposal = _createTestProposal(hash, validator);

        vm.prank(john);
        uint256 proposalId = party.propose(proposal, 0);

        vm.warp(block.timestamp + _EXECUTION_DELAY);

        vm.prank(john);
        party.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
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
