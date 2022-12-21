// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/PartyList.sol";
import "../../contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "../../contracts/proposals/ProposalExecutionEngine.sol";
import "../DummyERC721.sol";

contract PartyFactoryTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    Party partyImpl = new Party(globals);
    PartyList partyList = new PartyList(globals);
    PartyFactory factory = new PartyFactory(globals, partyList);
    ProposalExecutionEngine eng;
    Party.PartyOptions defaultPartyOptions;
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;
    bytes32 preciousListHash;

    constructor() {
        defaultPartyOptions.name = "PARTY";
        defaultPartyOptions.symbol = "PR-T";
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.voteDuration = 1 days;
        defaultPartyOptions.governance.executionDelay = 8 hours;
        defaultPartyOptions.governance.passThresholdBps = 0.51e4;
        defaultPartyOptions.governance.totalVotingPower = 100e18;

        eng = new ProposalExecutionEngine(
            globals,
            IOpenseaExchange(_randomAddress()),
            IOpenseaConduitController(_randomAddress()),
            IZoraAuctionHouse(_randomAddress()),
            IFractionalV1VaultFactory(_randomAddress())
        );

        globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));
        globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(eng));
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(factory));

        preciousTokens = new IERC721[](3);
        preciousTokenIds = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            DummyERC721 t = new DummyERC721();
            preciousTokens[i] = IERC721(address(t));
            preciousTokenIds[i] = t.mint(address(this));
        }
    }

    function _hashPreciousList(
        IERC721[] memory _preciousTokens,
        uint256[] memory _preciousTokenIds
    ) internal pure returns (bytes32 h) {
        assembly {
            mstore(0x00, keccak256(add(_preciousTokens, 0x20), mul(mload(_preciousTokens), 0x20)))
            mstore(
                0x20,
                keccak256(add(_preciousTokenIds, 0x20), mul(mload(_preciousTokenIds), 0x20))
            )
            h := keccak256(0x00, 0x40)
        }
    }

    function testCreateParty(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps
    ) external {
        vm.assume(randomBps <= 1e4);

        address authority = _randomAddress();
        Party.PartyOptions memory opts = Party.PartyOptions({
            governance: PartyGovernance.GovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                totalVotingPower: randomUint96,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            }),
            name: randomStr,
            symbol: randomStr,
            customizationPresetId: 0
        });
        Party party = factory.createParty(authority, opts, preciousTokens, preciousTokenIds);
        assertEq(party.name(), opts.name);
        assertEq(party.symbol(), opts.symbol);
        assertEq(party.mintAuthority(), authority);
        PartyGovernance.GovernanceValues memory values = party.getGovernanceValues();
        assertEq(values.voteDuration, opts.governance.voteDuration);
        assertEq(values.executionDelay, opts.governance.executionDelay);
        assertEq(values.passThresholdBps, opts.governance.passThresholdBps);
        assertEq(values.totalVotingPower, opts.governance.totalVotingPower);
        assertEq(party.feeBps(), opts.governance.feeBps);
        assertEq(party.feeRecipient(), opts.governance.feeRecipient);
        assertEq(address(party.getProposalExecutionEngine()), address(eng));
        assertEq(party.preciousListHash(), _hashPreciousList(preciousTokens, preciousTokenIds));
    }

    function testCreatePartyWithInvalidBps(uint16 passThresholdBps, uint16 feeBps) external {
        // At least one of the BPs must be invalid for this test to work.
        vm.assume(passThresholdBps > 1e4 || feeBps > 1e4);

        address authority = _randomAddress();

        Party.PartyOptions memory opts = defaultPartyOptions;
        opts.governance.feeBps = feeBps;
        opts.governance.passThresholdBps = passThresholdBps;

        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.InvalidBpsError.selector,
                feeBps > 1e4 ? feeBps : passThresholdBps
            )
        );
        factory.createParty(authority, opts, preciousTokens, preciousTokenIds);
    }

    function testCreatePartyFromList() external {
        address member = _randomAddress();
        address delegate = _randomAddress();
        uint96 votingPower = 0.1e18;
        uint256 nonce = _randomUint256();

        for (uint256 i; i < preciousTokens.length; ++i) {
            preciousTokens[i].approve(address(factory), preciousTokenIds[i]);
        }

        IPartyFactory.PartyFromListInitOpts memory initOpts = IPartyFactory.PartyFromListInitOpts({
            opts: defaultPartyOptions,
            tokens: preciousTokens,
            tokenIds: preciousTokenIds,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            creator: _randomAddress(),
            creatorVotingPower: 0.3e18,
            creatorDelegate: _randomAddress(),
            listMerkleRoot: keccak256(abi.encodePacked(member, votingPower, nonce))
        });

        Party party = factory.createPartyFromList(initOpts);

        assertEq(party.mintAuthority(), address(partyList));
        assertEq(partyList.listMerkleRoots(party), initOpts.listMerkleRoot);
        assertEq(party.balanceOf(initOpts.creator), 1);
        assertEq(party.delegationsByVoter(initOpts.creator), initOpts.creatorDelegate);
        assertEq(party.votingPowerByTokenId(1), initOpts.creatorVotingPower);

        partyList.mint(
            PartyList.MintArgs({
                party: party,
                member: member,
                votingPower: votingPower,
                nonce: nonce,
                delegate: delegate,
                proof: new bytes32[](0)
            })
        );
        assertEq(party.balanceOf(member), 1);
        assertEq(party.delegationsByVoter(member), delegate);
        assertEq(party.votingPowerByTokenId(2), votingPower);

        for (uint256 i; i < preciousTokens.length; ++i) {
            assertEq(preciousTokens[i].ownerOf(preciousTokenIds[i]), address(party));
        }
    }
}
