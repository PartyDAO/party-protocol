// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "../../contracts/proposals/ProposalExecutionEngine.sol";

contract PartyFactoryTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    Party partyImpl = new Party(globals);
    PartyFactory factory = new PartyFactory(globals);
    ProposalExecutionEngine eng;
    Party.PartyOptions defaultPartyOptions;

    constructor() {
        defaultPartyOptions.name = 'PARTY';
        defaultPartyOptions.symbol = 'PR-T';
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.voteDuration = 1 days;
        defaultPartyOptions.governance.executionDelay = 8 hours;
        defaultPartyOptions.governance.passThresholdBps = 0.51e4;
        defaultPartyOptions.governance.totalVotingPower = 100e18;

        eng = new ProposalExecutionEngine(
            globals,
            ISeaportExchange(_randomAddress()),
            ISeaportConduitController(_randomAddress()),
            IZoraAuctionHouse(_randomAddress()),
            IFractionalV1VaultFactory(_randomAddress())
        );

        globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));
        globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(eng));
    }

    function _createPreciouses(uint256 count)
        private
        view
        returns (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds)
    {
        preciousTokens = new IERC721[](count);
        preciousTokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            preciousTokens[i] = IERC721(_randomAddress());
            preciousTokenIds[i] = _randomUint256();
        }
    }

    function _hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        internal
        pure
        returns (bytes32 h)
    {
        assembly {
            mstore(0x00, keccak256(
                add(preciousTokens, 0x20),
                mul(mload(preciousTokens), 0x20)
            ))
            mstore(0x20, keccak256(
                add(preciousTokenIds, 0x20),
                mul(mload(preciousTokenIds), 0x20)
            ))
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
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
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
            symbol: randomStr
        });
        Party party = factory.createParty(
            authority,
            opts,
            preciousTokens,
            preciousTokenIds
        );
        assertEq(factory.partyAuthorities(party), authority);
        assertEq(party.name(), opts.name);
        assertEq(party.symbol(), opts.symbol);
        assertEq(party.mintAuthority(), address(factory));
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
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);

        Party.PartyOptions memory opts = defaultPartyOptions;
        opts.governance.feeBps = feeBps;
        opts.governance.passThresholdBps = passThresholdBps;

        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.InvalidBpsError.selector,
            feeBps > 1e4 ? feeBps : passThresholdBps
        ));
        factory.createParty(authority, opts, preciousTokens, preciousTokenIds);
    }

    function testMint_works(address owner, address delegate, uint256 amount) external {
        vm.assume(
            amount <= type(uint96).max &&
            owner != address(0) &&
            delegate != address(0)
        );
        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        vm.prank(authority);
        factory.mint(party, owner, amount, delegate);
    }

    function testMint_onlyAuthorityCanCall() external {
        address authority = _randomAddress();
        address notAuthority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        {
            address owner = _randomAddress();
            address delegate = _randomAddress();
            uint256 amount = _randomUint256();
            vm.expectRevert(abi.encodeWithSelector(
                PartyFactory.OnlyAuthorityError.selector
            ));
            vm.prank(notAuthority);
            factory.mint(party, owner, amount, delegate);
        }
    }

    function testAbdicate_works() external {
        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciouses(3);
        Party party = factory.createParty(
            authority,
            defaultPartyOptions,
            preciousTokens,
            preciousTokenIds
        );
        assertEq(factory.partyAuthorities(party), authority);
        vm.prank(authority);
        factory.abdicate(party);
        assertEq(factory.partyAuthorities(party), address(0));
    }
}
