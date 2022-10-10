// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/PartyNFTRenderer.sol";
import "../../contracts/renderers/RendererStorage.sol";
import "../../contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";
import "../TestUtils.sol";

contract PartyGovernanceNFTTest is Test, TestUtils {
    PartyFactory partyFactory;
    DummySimpleProposalEngineImpl eng;
    PartyNFTRenderer nftRenderer;
    RendererStorage nftRendererStorage;
    TestTokenDistributor tokenDistributor;
    Globals globals;
    PartyParticipant john;
    DummyERC721 toadz;
    PartyAdmin partyAdmin;
    address globalDaoWalletAddress = address(420);

    constructor() {
        GlobalsAdmin globalsAdmin = new GlobalsAdmin();
        globals = globalsAdmin.globals();
        Party partyImpl = new Party(globals);
        globalsAdmin.setPartyImpl(address(partyImpl));
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        tokenDistributor = new TestTokenDistributor();
        globalsAdmin.setTokenDistributor(address(tokenDistributor));

        eng = new DummySimpleProposalEngineImpl();
        globalsAdmin.setProposalEng(address(eng));

        partyFactory = new PartyFactory(globals);

        john = new PartyParticipant();
        partyAdmin = new PartyAdmin(partyFactory);

        // Upload font on-chain
        PixeldroidConsoleFont font = new PixeldroidConsoleFont();
        nftRendererStorage = new RendererStorage();
        nftRenderer = new PartyNFTRenderer(globals, nftRendererStorage, font);
        globalsAdmin.setGovernanceNftRendererAddress(address(nftRenderer));

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }

    function testMint() external {
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        vm.prank(address(partyAdmin));
        party.mint(_randomAddress(), 1, _randomAddress());
    }

    function testMint_onlyMinter() external {
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address notAuthority = _randomAddress();
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernanceNFT.OnlyMintAuthorityError.selector,
            notAuthority,
            address(partyAdmin)
        ));
        vm.prank(notAuthority);
        party.mint(_randomAddress(), 1, _randomAddress());
    }

    function testAbdicate() external {
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        assertEq(party.mintAuthority(), address(partyAdmin));
        vm.prank(address(partyAdmin));
        party.abdicate();
        assertEq(party.mintAuthority(), address(0));
    }

    function testAbdicate_onlyMinter() external {
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        address notAuthority = _randomAddress();
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernanceNFT.OnlyMintAuthorityError.selector,
            notAuthority,
            address(partyAdmin)
        ));
        vm.prank(notAuthority);
        party.abdicate();
    }

    function testTokenURI() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Create proposals
        uint256 n = _randomRange(0, 6);
        for (uint256 i; i < n; ++i) {
            _createMockProposal(party);
        }

        bool hasClaimed = n > 3;
        uint256 tokenId = _randomUint256() % 1000;

        // Mint governance NFT
        party.mint(tokenId);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), hasClaimed);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testContractURI() external {
        // Create party
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        string memory contractURI = party.contractURI();

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function testRoyaltyInfo() external {
        // Create party
        (Party party, ,) = partyAdmin.createParty(
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        (address receiver, uint256 royaltyAmount) = party.royaltyInfo(0, 0);
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function _createMockProposal(DummyParty party) private {
        PartyGovernance.ProposalStatus status =
            PartyGovernance.ProposalStatus(_randomRange(1, uint8(type(PartyGovernance.ProposalStatus).max)));

        party.createMockProposal(status);
    }
}

contract DummyParty is ReadOnlyDelegateCall {
    Globals immutable GLOBALS;

    constructor(address globals, string memory _name) {
        name = _name;
        GLOBALS = Globals(globals);
    }

    bool public emergencyExecuteDisabled;
    uint16 public feeBps;
    address payable public feeRecipient;
    bytes32 public preciousListHash;
    uint256 public lastProposalId;
    mapping(address => bool) public isHost;
    mapping(address => address) public delegationsByVoter;
    PartyGovernance.GovernanceValues private _governanceValues;
    mapping(uint256 => PartyGovernance.ProposalState) private _proposalStateByProposalId;
    mapping(address => PartyGovernance.VotingPowerSnapshot[]) private _votingPowerSnapshotsByVoter;
    string public name;
    string public symbol;
    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    address public mintAuthority;
    uint256 public tokenCount;
    mapping(uint256 => uint256) public votingPowerByTokenId;

    mapping(uint256 => PartyGovernance.ProposalStatus) _proposalStatuses;

    function tokenURI(uint256) public view returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    function mint(uint256 tokenId) external {
        _balanceOf[msg.sender]++;
        _ownerOf[tokenId] = msg.sender;
    }

    function createMockProposal(PartyGovernance.ProposalStatus status) external {
        _proposalStatuses[++lastProposalId] = status;
    }

    function getProposalStateInfo(uint256 proposalId)
        external
        view
        returns (PartyGovernance.ProposalStatus status, PartyGovernance.ProposalStateValues memory values)
    {
        status = _proposalStatuses[proposalId];
        values;
    }

    function getDistributionShareOf(uint256) external pure returns (uint256) {
        return 69.42e18;
    }

    function _delegateToRenderer() private view {
        _readOnlyDelegateCall(
            // Instance of IERC721Renderer.
            GLOBALS.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL),
            msg.data
        );
        assert(false); // Will not be reached.
    }
}

contract TestTokenDistributor {
    mapping(ITokenDistributorParty => uint256) public lastDistributionIdPerParty;
    bool private _hasClaimed;

    function setHasClaimed(address party, bool hasClaimed) external {
        lastDistributionIdPerParty[ITokenDistributorParty(party)] = 1;
        _hasClaimed = hasClaimed;
    }

    function hasPartyTokenIdClaimed(
        ITokenDistributorParty,
        uint256,
        uint256
    )
        external
        view returns (bool)
    {
        return _hasClaimed;
    }
}