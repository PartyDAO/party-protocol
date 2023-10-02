// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../contracts/globals/Globals.sol";
import "../contracts/globals/LibGlobals.sol";
import "../contracts/party/Party.sol";
import "../contracts/party/PartyFactory.sol";
import "../contracts/vendor/markets/IZoraAuctionHouse.sol";

contract ERC721Holder {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract GlobalsAdmin is Test {
    Globals public globals;

    constructor() {
        globals = new Globals(address(this));
        vm.deal(address(this), 100 ether);
    }

    function setProposalEng(address proposalEngAddress) public {
        globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, proposalEngAddress);
    }

    function setGlobalDaoWallet(address anAddress) public {
        globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, anAddress);
    }

    function setTokenDistributor(address tokenDistributorAddress) public {
        globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, tokenDistributorAddress);
    }

    function setGovernanceNftRendererAddress(address rendererAddress) public {
        globals.setAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL, rendererAddress);
    }

    function setRendererStorage(address rendererStorage) public {
        globals.setAddress(LibGlobals.GLOBAL_RENDERER_STORAGE, rendererStorage);
    }

    function setMetadataRegistry(address metadataRegistry) public {
        globals.setAddress(LibGlobals.GLOBAL_METADATA_REGISTRY, metadataRegistry);
    }

    function setGlobalPartyFactory(address partyFactory) public {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, partyFactory);
    }

    function setOffChainSignatureValidator(address signatureValidator) public {
        globals.setAddress(LibGlobals.GLOBAL_OFF_CHAIN_SIGNATURE_VALIDATOR, signatureValidator);
    }
}

contract PartyAdmin is Test {
    struct PartyCreationMinimalOptions {
        address host1;
        address host2;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
        address preciousTokenAddress;
        uint256 preciousTokenId;
        uint40 rageQuitTimestamp;
        uint16 feeBps;
        address payable feeRecipient;
    }

    PartyFactory _partyFactory;

    ProposalStorage.ProposalEngineOpts proposalEngineOpts;

    constructor(PartyFactory partyFactory) {
        _partyFactory = partyFactory;
    }

    function transferNft(IERC721 erc721Contract, uint256 tokenId, address sendTo) public {
        erc721Contract.safeTransferFrom(address(this), sendTo, tokenId);
    }

    function createParty(
        Party partyImpl,
        PartyCreationMinimalOptions calldata opts
    )
        public
        returns (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds)
    {
        uint256 size = 2 - (opts.host1 == address(0) ? 1 : 0) - (opts.host2 == address(0) ? 1 : 0);
        address[] memory hosts = new address[](size);
        if (opts.host1 != address(0)) {
            hosts[0] = opts.host1;
        }
        if (opts.host2 != address(0)) {
            hosts[1] = opts.host2;
        }

        preciousTokens = new IERC721[](1);
        preciousTokens[0] = IERC721(opts.preciousTokenAddress);

        preciousTokenIds = new uint256[](1);
        preciousTokenIds[0] = opts.preciousTokenId;

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        party = _partyFactory.createParty(
            partyImpl,
            authorities,
            Party.PartyOptions({
                governance: PartyGovernance.GovernanceOpts({
                    hosts: hosts,
                    voteDuration: 99,
                    executionDelay: 300,
                    passThresholdBps: opts.passThresholdBps,
                    totalVotingPower: opts.totalVotingPower,
                    feeRecipient: opts.feeRecipient,
                    feeBps: opts.feeBps
                }),
                proposalEngine: proposalEngineOpts,
                name: "Dope party",
                symbol: "DOPE",
                customizationPresetId: 0
            }),
            preciousTokens,
            preciousTokenIds,
            opts.rageQuitTimestamp
        );
        return (party, preciousTokens, preciousTokenIds);
    }

    function mintGovNft(
        Party party,
        address mintTo,
        uint256 votingPower,
        address delegateTo
    ) public {
        party.mint(mintTo, votingPower, delegateTo);
    }

    function mintGovNft(Party party, address mintTo, uint256 votingPower) public {
        party.mint(mintTo, votingPower, mintTo);
    }
}

contract PartyParticipant is ERC721Holder, Test {
    constructor() {
        vm.deal(address(this), 100 ether);
    }

    receive() external payable {}

    struct ExecutionOptions {
        uint256 proposalId;
        PartyGovernance.Proposal proposal;
        IERC721[] preciousTokens;
        uint256[] preciousTokenIds;
        bytes progressData;
    }

    function makeProposal(
        Party party,
        PartyGovernance.Proposal memory proposal,
        uint256 lastestSnapIndex
    ) public returns (uint256) {
        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        return party.propose(proposal, lastestSnapIndex);
    }

    function vote(Party party, uint256 proposalId, uint256 snapIndex) public {
        party.accept(proposalId, snapIndex);
    }

    function delegate(Party party, address newDelegate) public {
        party.delegateVotingPower(newDelegate);
    }

    function transferVotingCard(Party party, PartyParticipant to, uint256 tokenId) public {
        party.transferFrom(address(this), address(to), tokenId);
    }

    function executeProposal(Party party, ExecutionOptions memory eo) public {
        party.execute(
            eo.proposalId,
            eo.proposal,
            eo.preciousTokens,
            eo.preciousTokenIds,
            eo.progressData,
            ""
        );
    }

    function vetoProposal(Party party, uint256 proposalId) public {
        party.veto(proposalId);
    }

    function distributeEth(
        Party party
    ) public returns (ITokenDistributor.DistributionInfo memory distInfo) {
        return
            party.distribute(
                address(party).balance,
                ITokenDistributor.TokenType.Native,
                address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
                0
            );
    }
}
