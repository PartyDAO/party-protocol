// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/PartyNFTRenderer.sol";
import "../../contracts/renderers/RendererStorage.sol";
import "../../contracts/renderers/MetadataRegistry.sol";
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
    MetadataRegistry metadataRegistry;
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
        metadataRegistry = new MetadataRegistry(globals, _toAddressArray(address(this)));
        globalsAdmin.setPartyImpl(address(partyImpl));
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);
        globalsAdmin.setMetadataRegistry(address(metadataRegistry));

        tokenDistributor = new TestTokenDistributor();
        globalsAdmin.setTokenDistributor(address(tokenDistributor));

        eng = new DummySimpleProposalEngineImpl();
        globalsAdmin.setProposalEng(address(eng));

        partyFactory = new PartyFactory(globals);

        john = new PartyParticipant();
        partyAdmin = new PartyAdmin(partyFactory);

        // Upload font on-chain
        PixeldroidConsoleFont font = new PixeldroidConsoleFont();
        nftRendererStorage = new RendererStorage(address(this));
        nftRenderer = new PartyNFTRenderer(globals, nftRendererStorage, font);
        globalsAdmin.setGovernanceNftRendererAddress(address(nftRenderer));
        globalsAdmin.setRendererStorage(address(nftRendererStorage));

        // Generate customization options.
        uint256 versionId = 1;
        uint256 numOfColors = uint8(type(RendererBase.Color).max) + 1;
        for (uint256 i; i < numOfColors; ++i) {
            // Generate customization options for all colors w/ each mode (light and dark).
            nftRendererStorage.createCustomizationPreset(
                // Preset ID 0 is reserved. It is used to indicates to party instances
                // to use the same customization preset as the crowdfund.
                i + 1,
                abi.encode(versionId, false, RendererBase.Color(i))
            );
            nftRendererStorage.createCustomizationPreset(
                i + 1 + numOfColors,
                abi.encode(versionId, true, RendererBase.Color(i))
            );
        }

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }

    function testMint() external {
        (Party party, , ) = partyAdmin.createParty(
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
        (Party party, , ) = partyAdmin.createParty(
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
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.OnlyMintAuthorityError.selector,
                notAuthority,
                address(partyAdmin)
            )
        );
        vm.prank(notAuthority);
        party.mint(_randomAddress(), 1, _randomAddress());
    }

    function testMint_cannotMintBeyondTotalVotingPower() external {
        (Party party, , ) = partyAdmin.createParty(
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
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(recipient, 101, recipient);
        assertEq(party.getVotingPowerAt(recipient, uint40(block.timestamp)), 100);
    }

    function testMint_cannotMintBeyondTotalVotingPower_twoMints() external {
        (Party party, , ) = partyAdmin.createParty(
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
        address recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(recipient, 99, recipient);
        assertEq(party.getVotingPowerAt(recipient, uint40(block.timestamp)), 99);
        recipient = _randomAddress();
        vm.prank(address(partyAdmin));
        party.mint(recipient, 2, recipient);
        assertEq(party.getVotingPowerAt(recipient, uint40(block.timestamp)), 1);
    }

    function testAbdicate() external {
        (Party party, , ) = partyAdmin.createParty(
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
        (Party party, , ) = partyAdmin.createParty(
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
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.OnlyMintAuthorityError.selector,
                notAuthority,
                address(partyAdmin)
            )
        );
        vm.prank(notAuthority);
        party.abdicate();
    }

    function test_supportsInterface() external {
        (Party party, , ) = partyAdmin.createParty(
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
        assertTrue(party.supportsInterface(0x01ffc9a7)); // EIP165
        assertTrue(party.supportsInterface(0x2a55205a)); // ERC2981
        assertTrue(party.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(party.supportsInterface(0x150b7a02)); // ERC721Receiver
        assertTrue(party.supportsInterface(0x4e2312e0)); // ERC1155Receiver
    }

    function testGenerateSVG_works() public {
        PartyGovernance.ProposalStatus[4] memory proposalStatuses = [
            PartyGovernance.ProposalStatus.Voting,
            PartyGovernance.ProposalStatus.Defeated,
            PartyGovernance.ProposalStatus.Passed,
            PartyGovernance.ProposalStatus.Invalid // Should not be rendered.
        ];

        string memory svg = nftRenderer.generateSVG(
            "Test",
            "10.32",
            proposalStatuses,
            3,
            420,
            true,
            RendererBase.Color.CYAN,
            true
        );

        // Uncomment for testing rendering:
        // console.log(svg);

        assertTrue(bytes(svg).length > 0);
    }

    function testTokenURI_works() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option
        party.useCustomizationPreset(16); // Should make card red w/ dark mode.

        // Create proposals
        party.createMockProposal(PartyGovernance.ProposalStatus.Complete);
        party.createMockProposal(PartyGovernance.ProposalStatus.Voting);
        party.createMockProposal(PartyGovernance.ProposalStatus.Ready);
        party.createMockProposal(PartyGovernance.ProposalStatus.InProgress);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set voting power percentage
        party.setVotingPowerPercentage(0.42069e18);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    // Test rendering using a preset ID 0, which is reserved to indicate to
    // parties to use the same preset as the crowdfund that created it (or of
    // whatever `mintAuthority()` chose if created outside the conventional flow).
    function testTokenURI_usingReservedPresetId() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option.
        nftRendererStorage.useCustomizationPreset(5); // Should make card purple w/ light mode.

        // Setting to preset ID 0 should cause `tokenURI()` to use the
        // customization option of the `mintAuthority()` (which for this test is
        // the caller).
        party.useCustomizationPreset(0);

        // Create proposals
        party.createMockProposal(PartyGovernance.ProposalStatus.Complete);
        party.createMockProposal(PartyGovernance.ProposalStatus.Voting);
        party.createMockProposal(PartyGovernance.ProposalStatus.Ready);
        party.createMockProposal(PartyGovernance.ProposalStatus.InProgress);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set voting power percentage
        party.setVotingPowerPercentage(0.42069e18);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testTokenURI_nonexistentPresetId() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option
        party.useCustomizationPreset(999); // Should fallback to default card since doesn't exist.

        // Create proposals
        party.createMockProposal(PartyGovernance.ProposalStatus.Complete);
        party.createMockProposal(PartyGovernance.ProposalStatus.Voting);
        party.createMockProposal(PartyGovernance.ProposalStatus.Ready);
        party.createMockProposal(PartyGovernance.ProposalStatus.InProgress);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        // Set voting power percentage
        party.setVotingPowerPercentage(0.42069e18);

        // Set claimed/unclaimed state
        tokenDistributor.setHasClaimed(address(party), false);

        // Get token URI
        string memory tokenURI = party.tokenURI(tokenId);

        // Uncomment for testing rendering:
        // console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testTokenURI_customMetadata() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Create dummy crowdfund address to use as mint authority.
        DummyCrowdfund crowdfund = new DummyCrowdfund();
        Crowdfund.FixedGovernanceOpts memory opts;
        opts.hosts = _toAddressArray(address(this));
        crowdfund.setGovernanceOptsHash(opts);
        party.setMintAuthority(address(crowdfund));

        TokenMetadata memory metadata = TokenMetadata({
            name: "NAME",
            description: "DESCRIPTION",
            image: "IMAGE"
        });

        // Set custom metadata
        metadataRegistry.setCustomMetadata(Crowdfund(address(crowdfund)), opts, 0, metadata);

        // Mint governance NFT
        uint256 tokenId = 396;
        party.mint(tokenId);

        string memory tokenURI = party.tokenURI(tokenId);

        // Uncomment for testing rendering:
        console.log(tokenURI);

        assertTrue(bytes(tokenURI).length > 0);
    }

    function testContractURI() external {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Set customization option
        party.useCustomizationPreset(1);

        string memory contractURI = party.contractURI();

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function testContractURI_customMetadata() public {
        // Create party
        DummyParty party = new DummyParty(address(globals), "Party of the Living Dead");

        // Create dummy crowdfund address to use as mint authority.
        DummyCrowdfund crowdfund = new DummyCrowdfund();
        Crowdfund.FixedGovernanceOpts memory opts;
        opts.hosts = _toAddressArray(address(this));
        crowdfund.setGovernanceOptsHash(opts);
        party.setMintAuthority(address(crowdfund));

        CollectionMetadata memory metadata = CollectionMetadata({
            name: "NAME",
            description: "DESCRIPTION",
            image: "IMAGE",
            banner: "BANNER"
        });

        // Set custom metadata
        metadataRegistry.setCustomCollectionMetadata(
            Crowdfund(address(crowdfund)),
            opts,
            0,
            metadata
        );

        string memory contractURI = party.contractURI();

        // Uncomment for testing rendering:
        // console.log(contractURI);

        assertTrue(bytes(contractURI).length > 0);
    }

    function testRoyaltyInfo() external {
        // Create party
        (Party party, , ) = partyAdmin.createParty(
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
        PartyGovernance.ProposalStatus status = PartyGovernance.ProposalStatus(
            _randomRange(1, uint8(type(PartyGovernance.ProposalStatus).max))
        );

        party.createMockProposal(status);
    }
}

contract DummyCrowdfund {
    uint256 public totalContributions;
    bytes32 public governanceOptsHash;

    function setGovernanceOptsHash(Crowdfund.FixedGovernanceOpts memory opts) external {
        governanceOptsHash = _hashFixedGovernanceOpts(opts);
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
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    address public mintAuthority;
    uint256 public tokenCount;
    mapping(uint256 => uint256) public votingPowerByTokenId;

    mapping(uint256 => PartyGovernance.ProposalStatus) _proposalStatuses;
    uint256 votingPowerPercentage; // 1e18 == 100%

    function useCustomizationPreset(uint256 customizationPresetId) external {
        if (customizationPresetId != 0) {
            RendererStorage(GLOBALS.getAddress(LibGlobals.GLOBAL_RENDERER_STORAGE))
                .useCustomizationPreset(customizationPresetId);
        } else {
            mintAuthority = msg.sender;
        }
    }

    function tokenURI(uint256) public view returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    function contractURI() public view returns (string memory) {
        _delegateToRenderer();
        return ""; // Just to make the compiler happy.
    }

    function mint(uint256 tokenId) external {
        _balanceOf[msg.sender]++;
        ownerOf[tokenId] = msg.sender;
    }

    function createMockProposal(PartyGovernance.ProposalStatus status) external {
        _proposalStatuses[++lastProposalId] = status;
    }

    function getProposalStateInfo(
        uint256 proposalId
    )
        external
        view
        returns (
            PartyGovernance.ProposalStatus status,
            PartyGovernance.ProposalStateValues memory values
        )
    {
        status = _proposalStatuses[proposalId];
        values;
    }

    function setVotingPowerPercentage(uint256 vp) external {
        votingPowerPercentage = vp;
    }

    function setMintAuthority(address authority) external {
        mintAuthority = authority;
    }

    function getDistributionShareOf(uint256) external view returns (uint256) {
        return votingPowerPercentage;
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
    ) external view returns (bool) {
        return _hasClaimed;
    }
}
