// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Script.sol";

import "../contracts/crowdfund/AuctionCrowdfund.sol";
import "../contracts/crowdfund/BuyCrowdfund.sol";
import "../contracts/crowdfund/CollectionBuyCrowdfund.sol";
import "../contracts/crowdfund/CollectionBatchBuyCrowdfund.sol";
import "../contracts/operators/CollectionBatchBuyOperator.sol";
import "../contracts/operators/ERC20SwapOperator.sol";
import "../contracts/crowdfund/InitialETHCrowdfund.sol";
import "../contracts/crowdfund/ReraiseETHCrowdfund.sol";
import "../contracts/crowdfund/CrowdfundFactory.sol";
import "../contracts/distribution/TokenDistributor.sol";
import "../contracts/gatekeepers/AllowListGateKeeper.sol";
import "../contracts/gatekeepers/TokenGateKeeper.sol";
import "../contracts/gatekeepers/IGateKeeper.sol";
import "../contracts/globals/Globals.sol";
import "../contracts/globals/LibGlobals.sol";
import "../contracts/party/Party.sol";
import "../contracts/party/PartyFactory.sol";
import "../contracts/renderers/MetadataRegistry.sol";
import "../contracts/renderers/MetadataProvider.sol";
import "../contracts/renderers/CrowdfundNFTRenderer.sol";
import "../contracts/renderers/PartyNFTRenderer.sol";
import "../contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";
import "../contracts/utils/PartyHelpers.sol";
import "../contracts/market-wrapper/NounsMarketWrapper.sol";
import { AtomicManualParty } from "../contracts/crowdfund/AtomicManualParty.sol";
import { ContributionRouter } from "../contracts/crowdfund/ContributionRouter.sol";
import { AddPartyCardsAuthority } from "../contracts/authorities/AddPartyCardsAuthority.sol";
import { SSTORE2MetadataProvider } from "../contracts/renderers/SSTORE2MetadataProvider.sol";
import { BasicMetadataProvider } from "../contracts/renderers/BasicMetadataProvider.sol";
import "./LibDeployConstants.sol";

abstract contract Deploy {
    enum DeployerRole {
        Default,
        PartyFactory,
        CrowdfundFactory,
        TokenDistributor
    }

    struct AddressMapping {
        string key;
        address value;
    }

    mapping(address => uint256) private _deployerGasBefore;
    mapping(address => uint256) private _deployerGasUsage;

    // temporary variables to store deployed contract addresses
    Globals public globals;
    AuctionCrowdfund public auctionCrowdfund;
    RollingAuctionCrowdfund public rollingAuctionCrowdfund;
    BuyCrowdfund public buyCrowdfund;
    CollectionBuyCrowdfund public collectionBuyCrowdfund;
    CollectionBatchBuyCrowdfund public collectionBatchBuyCrowdfund;
    InitialETHCrowdfund public initialETHCrowdfund;
    ReraiseETHCrowdfund public reraiseETHCrowdfund;
    CrowdfundFactory public crowdfundFactory;
    Party public party;
    PartyFactory public partyFactory;
    ProposalExecutionEngine public proposalExecutionEngine;
    TokenDistributor public tokenDistributor;
    MetadataRegistry public metadataRegistry;
    BasicMetadataProvider public basicMetadataProvider;
    SSTORE2MetadataProvider public sstore2MetadataProvider;
    RendererStorage public rendererStorage;
    CrowdfundNFTRenderer public crowdfundNFTRenderer;
    PartyNFTRenderer public partyNFTRenderer;
    CollectionBatchBuyOperator public collectionBatchBuyOperator;
    ERC20SwapOperator public swapOperator;
    PartyHelpers public partyHelpers;
    IGateKeeper public allowListGateKeeper;
    IGateKeeper public tokenGateKeeper;
    NounsMarketWrapper public nounsMarketWrapper;
    PixeldroidConsoleFont public pixeldroidConsoleFont;
    AtomicManualParty public atomicManualParty;
    ContributionRouter public contributionRouter;
    AddPartyCardsAuthority public addPartyCardsAuthority;

    function deploy(LibDeployConstants.DeployConstants memory deployConstants) public virtual {
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_GLOBALS
        console.log("");
        console.log("### Globals");
        console.log("  Deploying - Globals");
        globals = new Globals(this.getDeployer());
        console.log("  Deployed - Globals", address(globals));

        // DEPLOY_TOKEN_DISTRIBUTOR
        console.log("");
        console.log("### TokenDistributor");
        console.log("  Deploying - TokenDistributor");
        _switchDeployer(DeployerRole.TokenDistributor);
        _trackDeployerGasBefore();
        tokenDistributor = new TokenDistributor(
            globals,
            uint40(block.timestamp) + deployConstants.distributorEmergencyActionAllowedDuration
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - TokenDistributor", address(tokenDistributor));
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_PROPOSAL_EXECUTION_ENGINE
        console.log("");
        console.log("### ProposalExecutionEngine");
        console.log("  Deploying - ProposalExecutionEngine");
        IReserveAuctionCoreEth zora = IReserveAuctionCoreEth(
            deployConstants.zoraReserveAuctionCoreEth
        );
        IFractionalV1VaultFactory fractionalVaultFactory = IFractionalV1VaultFactory(
            deployConstants.fractionalVaultFactory
        );
        _trackDeployerGasBefore();
        proposalExecutionEngine = new ProposalExecutionEngine(
            globals,
            zora,
            fractionalVaultFactory
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - ProposalExecutionEngine", address(proposalExecutionEngine));

        // DEPLOY_PARTY_IMPLEMENTATION
        console.log("");
        console.log("### Party implementation");
        console.log("  Deploying - Party implementation");
        _trackDeployerGasBefore();
        party = new Party(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - Party implementation", address(party));

        // DEPLOY_PARTY_FACTORY
        console.log("");
        console.log("### PartyFactory");
        console.log("  Deploying - PartyFactory");
        _switchDeployer(DeployerRole.PartyFactory);
        _trackDeployerGasBefore();
        partyFactory = new PartyFactory(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - PartyFactory", address(partyFactory));
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_AUCTION_CF_IMPLEMENTATION
        console.log("");
        console.log("### AuctionCrowdfund crowdfund implementation");
        console.log("  Deploying - AuctionCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        auctionCrowdfund = new AuctionCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - AuctionCrowdfund crowdfund implementation",
            address(auctionCrowdfund)
        );

        // DEPLOY_BUY_CF_IMPLEMENTATION
        console.log("");
        console.log("### BuyCrowdfund crowdfund implementation");
        console.log("  Deploying - BuyCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        buyCrowdfund = new BuyCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - BuyCrowdfund crowdfund implementation", address(buyCrowdfund));

        // DEPLOY_COLLECTION_BUY_CF_IMPLEMENTATION
        console.log("");
        console.log("### CollectionBuyCrowdfund crowdfund implementation");
        console.log("  Deploying - CollectionBuyCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        collectionBuyCrowdfund = new CollectionBuyCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - CollectionBuyCrowdfund crowdfund implementation",
            address(collectionBuyCrowdfund)
        );

        // DEPLOY_COLLECTION_BATCH_BUY_CF_IMPLEMENTATION
        console.log("");
        console.log("### CollectionBatchBuyCrowdfund crowdfund implementation");
        console.log("  Deploying - CollectionBatchBuyCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        collectionBatchBuyCrowdfund = new CollectionBatchBuyCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - CollectionBatchBuyCrowdfund crowdfund implementation",
            address(collectionBatchBuyCrowdfund)
        );

        // DEPLOY_INITIAL_ETH_CF_IMPLEMENTATION
        console.log("");
        console.log("### InitialETHCrowdfund crowdfund implementation");
        console.log("  Deploying - InitialETHCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        initialETHCrowdfund = new InitialETHCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - InitialETHCrowdfund crowdfund implementation",
            address(initialETHCrowdfund)
        );

        // DEPLOY_RERAISE_ETH_CF_IMPLEMENTATION
        console.log("");
        console.log("### ReraiseETHCrowdfund crowdfund implementation");
        console.log("  Deploying - ReraiseETHCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        reraiseETHCrowdfund = new ReraiseETHCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - ReraiseETHCrowdfund crowdfund implementation",
            address(reraiseETHCrowdfund)
        );

        // DEPLOY_ROLLING_AUCTION_CF_IMPLEMENTATION
        console.log("");
        console.log("### RollingAuctionCrowdfund crowdfund implementation");
        console.log("  Deploying - RollingAuctionCrowdfund crowdfund implementation");
        rollingAuctionCrowdfund = new RollingAuctionCrowdfund(globals);
        console.log(
            "  Deployed - RollingAuctionCrowdfund crowdfund implementation",
            address(rollingAuctionCrowdfund)
        );

        // DEPLOY_PARTY_CROWDFUND_FACTORY
        console.log("");
        console.log("### CrowdfundFactory");
        console.log("  Deploying - CrowdfundFactory");
        _switchDeployer(DeployerRole.CrowdfundFactory);
        _trackDeployerGasBefore();
        crowdfundFactory = new CrowdfundFactory();
        _trackDeployerGasAfter();
        console.log("  Deployed - CrowdfundFactory", address(crowdfundFactory));
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_METADATA_REGISTRY
        address[] memory registrars = new address[](2);
        registrars[0] = address(partyFactory);
        registrars[1] = address(deployConstants.partyDaoMultisig);

        console.log("");
        console.log("### MetadataRegistry");
        console.log("  Deploying - MetadataRegistry");
        _trackDeployerGasBefore();
        metadataRegistry = new MetadataRegistry(globals, registrars);
        _trackDeployerGasAfter();
        console.log("  Deployed - MetadataRegistry", address(metadataRegistry));

        // DEPLOY_BASIC_METADATA_PROVIDER
        console.log("");
        console.log("### BasicMetadataProvider");
        console.log("  Deploying - BasicMetadataProvider");
        _trackDeployerGasBefore();
        basicMetadataProvider = new BasicMetadataProvider(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - BasicMetadataProvider", address(basicMetadataProvider));

        // DEPLOY_SSTORE2_METADATA_PROVIDER
        console.log("");
        console.log("### SSTORE2MetadataProvider");
        console.log("  Deploying - SSTORE2MetadataProvider");
        _trackDeployerGasBefore();
        sstore2MetadataProvider = new SSTORE2MetadataProvider(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - SSTORE2MetadataProvider", address(sstore2MetadataProvider));

        // DEPLOY_RENDERER_STORAGE
        console.log("");
        console.log("### RendererStorage");
        console.log("  Deploying - RendererStorage");
        _trackDeployerGasBefore();
        rendererStorage = new RendererStorage(this.getDeployer());
        _trackDeployerGasAfter();
        console.log("  Deployed - RendererStorage", address(rendererStorage));

        // CREATE_CUSTOMIZATION_OPTIONS
        {
            console.log("### Creating customization presets");
            uint256 versionId = 1;
            uint256 numOfColors = uint8(type(Color).max) + 1;
            bytes[] memory multicallData = new bytes[](numOfColors * 2);
            // Create customization options for all colors w/ both modes (light and dark).
            for (uint256 i; i < numOfColors; ++i) {
                multicallData[i * 2] = abi.encodeCall(
                    rendererStorage.createCustomizationPreset,
                    (
                        // Preset ID 0 is reserved. It is used to indicates to party instances
                        // to use the same customization preset as the crowdfund.
                        i + 1,
                        abi.encode(versionId, false, Color(i))
                    )
                );
                multicallData[i * 2 + 1] = abi.encodeCall(
                    rendererStorage.createCustomizationPreset,
                    (i + 1 + numOfColors, abi.encode(versionId, true, Color(i)))
                );
            }
            _trackDeployerGasBefore();
            rendererStorage.multicall(multicallData);
            _trackDeployerGasAfter();
        }

        // DEPLOY_FONT
        console.log("");
        console.log("### PixeldroidConsoleFont");
        console.log("  Deploying - PixeldroidConsoleFont");
        _trackDeployerGasBefore();
        pixeldroidConsoleFont = new PixeldroidConsoleFont();
        _trackDeployerGasAfter();
        console.log("  Deployed - PixeldroidConsoleFont", address(pixeldroidConsoleFont));

        // DEPLOY_CROWDFUND_NFT_RENDERER
        console.log("");
        console.log("### CrowdfundNFTRenderer");
        console.log("  Deploying - CrowdfundNFTRenderer");
        _trackDeployerGasBefore();
        crowdfundNFTRenderer = new CrowdfundNFTRenderer(
            globals,
            rendererStorage,
            IFont(address(pixeldroidConsoleFont))
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - CrowdfundNFTRenderer", address(crowdfundNFTRenderer));

        // DEPLOY_PARTY_NFT_RENDERER
        console.log("");
        console.log("### PartyNFTRenderer");
        console.log("  Deploying - PartyNFTRenderer");
        _trackDeployerGasBefore();
        partyNFTRenderer = new PartyNFTRenderer(
            globals,
            rendererStorage,
            IFont(address(pixeldroidConsoleFont)),
            deployConstants.oldTokenDistributor,
            deployConstants.baseExternalURL
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - PartyNFTRenderer", address(partyNFTRenderer));

        // DEPLOY_ADD_PARTY_CARDS_AUTHORITY
        console.log("");
        console.log("### AddPartyCardsAuthority");
        console.log("  Deploying - AddPartyCardsAuthority");
        _trackDeployerGasBefore();
        addPartyCardsAuthority = new AddPartyCardsAuthority();
        _trackDeployerGasAfter();
        console.log("  Deployed - AddPartyCardsAuthority", address(addPartyCardsAuthority));

        // DEPLOY_BATCH_BUY_OPERATOR
        console.log("");
        console.log("### CollectionBatchBuyOperator");
        console.log("  Deploying - CollectionBatchBuyOperator");
        _trackDeployerGasBefore();
        collectionBatchBuyOperator = new CollectionBatchBuyOperator();
        _trackDeployerGasAfter();
        console.log("  Deployed - CollectionBatchBuyOperator", address(collectionBatchBuyOperator));

        // DEPLOY_ERC20_SWAP_OPERATOR
        console.log("");
        console.log("### ERC20SwapOperator");
        console.log("  Deploying - ERC20SwapOperator");
        _trackDeployerGasBefore();
        swapOperator = new ERC20SwapOperator(
            globals,
            deployConstants.allowedERC20SwapOperatorTargets
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - ERC20SwapOperator", address(swapOperator));

        // DEPLOY_PARTY_HELPERS
        if (!isTest()) {
            console.log("");
            console.log("### PartyHelpers");
            console.log("  Deploying - PartyHelpers");
            _trackDeployerGasBefore();
            partyHelpers = new PartyHelpers();
            _trackDeployerGasAfter();
            console.log("  Deployed - PartyHelpers", address(partyHelpers));
        }

        // Deploy CONTRIBUTION_ROUTER
        console.log("");
        console.log("### ContributionRouter");
        console.log("  Deploying - ContributionRouter");
        _trackDeployerGasBefore();
        contributionRouter = new ContributionRouter(
            deployConstants.partyDaoMultisig,
            deployConstants.contributionRouterInitialFee
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - ContributionRouter", address(contributionRouter));

        // DEPLOY_GATE_KEEPRS
        console.log("");
        console.log("### GateKeepers");
        console.log("  Deploying - AllowListGateKeeper");
        _trackDeployerGasBefore();
        allowListGateKeeper = new AllowListGateKeeper(address(contributionRouter));
        _trackDeployerGasAfter();
        console.log("  Deployed - AllowListGateKeeper", address(allowListGateKeeper));

        console.log("");
        console.log("  Deploying - TokenGateKeeper");
        _trackDeployerGasBefore();
        tokenGateKeeper = new TokenGateKeeper(address(contributionRouter));
        _trackDeployerGasAfter();
        console.log("  Deployed - TokenGateKeeper", address(tokenGateKeeper));

        // DEPLOY_MARKET_WRAPPERS
        console.log("");
        console.log("### MarketWrappers");
        if (address(deployConstants.deployedNounsMarketWrapper) == address(0)) {
            console.log("  Deploying - NounsMarketWrapper");
            _trackDeployerGasBefore();
            nounsMarketWrapper = new NounsMarketWrapper(deployConstants.nounsAuctionHouse);
            _trackDeployerGasAfter();
            console.log("  Deployed - NounsMarketWrapper", address(nounsMarketWrapper));
        } else {
            nounsMarketWrapper = NounsMarketWrapper(deployConstants.deployedNounsMarketWrapper);
        }

        console.log("");
        console.log("  Deploying - AtomicManualParty");
        _trackDeployerGasBefore();
        atomicManualParty = new AtomicManualParty(partyFactory);
        _trackDeployerGasAfter();
        console.log("  Deployed - AtomicManualParty", address(atomicManualParty));

        // Set Global values and transfer ownership
        {
            console.log("### Configure Globals");
            bytes[] memory multicallData = new bytes[](999);
            uint256 n = 0;
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_DAO_WALLET, deployConstants.partyDaoMultisig)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setBytes32,
                (LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY, deployConstants.osConduitKey)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_OPENSEA_ZONE, deployConstants.osZone)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION, deployConstants.osZoraAuctionDuration)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT, deployConstants.osZoraAuctionTimeout)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION, deployConstants.osMinOrderDuration)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION, deployConstants.osMaxOrderDuration)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (
                    LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION,
                    deployConstants.zoraMinAuctionDuration
                )
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (
                    LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION,
                    deployConstants.zoraMaxAuctionDuration
                )
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT, deployConstants.zoraMaxAuctionTimeout)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_PROPOSAL_MIN_CANCEL_DURATION, deployConstants.minCancelDelay)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setUint256,
                (LibGlobals.GLOBAL_PROPOSAL_MAX_CANCEL_DURATION, deployConstants.maxCancelDelay)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_SEAPORT, deployConstants.seaportExchangeAddress)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_CONDUIT_CONTROLLER, deployConstants.osConduitController)
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(proposalExecutionEngine))
            );

            // The Globals commented out below were depreciated in 1.2; factories
            // can now choose the implementation address to deploy and no longer
            // deploy the latest implementation.
            //
            // See https://github.com/PartyDAO/party-migrations for
            // implementation addresses by release.

            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_PARTY_IMPL, address(party))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_CROWDFUND_FACTORY, address(crowdfundFactory))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_AUCTION_CF_IMPL, address(auctionCrowdfund))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_BUY_CF_IMPL, address(buyCrowdfund))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL, address(collectionBuyCrowdfund))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (
            //         LibGlobals.GLOBAL_COLLECTION_BATCH_BUY_CF_IMPL,
            //         address(collectionBatchBuyCrowdfund)
            //     )
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_INITIAL_ETH_CF_IMPL, address(initialETHCrowdfund))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_RERAISE_ETH_CF_IMPL, address(reraiseETHCrowdfund))
            // );
            // multicallData[n++] = abi.encodeCall(
            //     globals.setAddress,
            //     (LibGlobals.GLOBAL_ROLLING_AUCTION_CF_IMPL, address(rollingAuctionCrowdfund))
            // );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_RENDERER_STORAGE, address(rendererStorage))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL, address(crowdfundNFTRenderer))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL, address(partyNFTRenderer))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_METADATA_REGISTRY, address(metadataRegistry))
            );
            // transfer ownership of Globals to multisig
            if (this.getDeployer() != deployConstants.partyDaoMultisig) {
                multicallData[n++] = abi.encodeCall(
                    globals.transferMultiSig,
                    (deployConstants.partyDaoMultisig)
                );
            }
            assembly {
                mstore(multicallData, n)
            }
            _trackDeployerGasBefore();
            globals.multicall(multicallData);
            _trackDeployerGasAfter();
        }

        // transfer renderer storage ownership to multisig
        if (this.getDeployer() != deployConstants.partyDaoMultisig) {
            console.log("  Transferring RendererStorage ownership to multisig");
            _trackDeployerGasBefore();
            rendererStorage.transferOwnership(deployConstants.partyDaoMultisig);
            _trackDeployerGasAfter();
        }
    }

    function getDeployer() external view returns (address) {
        return msg.sender;
    }

    function isTest() internal view returns (bool) {
        return address(this) == this.getDeployer();
    }

    function _getDeployerGasUsage(address deployer) internal view returns (uint256) {
        return _deployerGasUsage[deployer];
    }

    function _trackDeployerGasBefore() private {
        address deployer = this.getDeployer();
        _deployerGasBefore[deployer] = gasleft();
    }

    function _trackDeployerGasAfter() private {
        address deployer = this.getDeployer();
        uint256 usage = _deployerGasBefore[deployer] - gasleft();
        _deployerGasUsage[deployer] += usage;
    }

    function _switchDeployer(DeployerRole role) internal virtual;
}

contract DeployFork is Deploy {
    function deployMainnetFork(address multisig) public {
        LibDeployConstants.DeployConstants memory dc = LibDeployConstants.mainnet();
        dc.partyDaoMultisig = multisig;
        deploy(dc);
    }

    function _switchDeployer(DeployerRole role) internal override {}
}

contract DeployScript is Script, Deploy {
    mapping(DeployerRole => address) internal _deployerByRole;
    address[] private _deployersUsed;

    function run() external {
        vm.startBroadcast();

        _run();

        {
            uint256 n = _deployersUsed.length;
            console.log("");
            for (uint256 i; i < n; ++i) {
                address deployer = _deployersUsed[i];
                uint256 gasUsed = _getDeployerGasUsage(deployer);
                console.log("deployer:", deployer);
                console.log("cost:", gasUsed * tx.gasprice);
                console.log("gas:", gasUsed);
                if (i + 1 < n) {
                    console.log("");
                }
            }
        }
    }

    function _run() internal virtual {}

    function _switchDeployer(DeployerRole role) internal override {
        vm.stopBroadcast();
        {
            address deployer_ = _deployerByRole[role];
            if (deployer_ != address(0)) {
                vm.startBroadcast(deployer_);
            } else {
                vm.startBroadcast();
            }
        }
        address deployer = this.getDeployer();
        console.log("Switched deployer to", deployer);
        for (uint256 i; i < _deployersUsed.length; ++i) {
            if (_deployersUsed[i] == deployer) {
                return;
            }
        }
        _deployersUsed.push(deployer);
        if (vm.envUint("DRY_RUN") == 1) {
            vm.deal(deployer, 100e18);
        }
    }

    function deploy(LibDeployConstants.DeployConstants memory deployConstants) public override {
        Deploy.deploy(deployConstants);
        vm.stopBroadcast();

        AddressMapping[] memory addressMapping = new AddressMapping[](28);
        addressMapping[0] = AddressMapping("Globals", address(globals));
        addressMapping[1] = AddressMapping("TokenDistributor", address(tokenDistributor));
        addressMapping[2] = AddressMapping(
            "ProposalExecutionEngine",
            address(proposalExecutionEngine)
        );
        addressMapping[3] = AddressMapping("Party", address(party));
        addressMapping[4] = AddressMapping("PartyFactory", address(partyFactory));
        addressMapping[5] = AddressMapping("AuctionCrowdfund", address(auctionCrowdfund));
        addressMapping[6] = AddressMapping(
            "RollingAuctionCrowdfund",
            address(rollingAuctionCrowdfund)
        );
        addressMapping[7] = AddressMapping("BuyCrowdfund", address(buyCrowdfund));
        addressMapping[8] = AddressMapping(
            "CollectionBuyCrowdfund",
            address(collectionBuyCrowdfund)
        );
        addressMapping[9] = AddressMapping(
            "CollectionBatchBuyCrowdfund",
            address(collectionBatchBuyCrowdfund)
        );
        addressMapping[10] = AddressMapping("InitialETHCrowdfund", address(initialETHCrowdfund));
        addressMapping[11] = AddressMapping("ReraiseETHCrowdfund", address(reraiseETHCrowdfund));
        addressMapping[12] = AddressMapping(
            "CollectionBatchBuyOperator",
            address(collectionBatchBuyOperator)
        );
        addressMapping[13] = AddressMapping("ERC20SwapOperator", address(swapOperator));
        addressMapping[14] = AddressMapping("CrowdfundFactory", address(crowdfundFactory));
        addressMapping[15] = AddressMapping("MetadataRegistry", address(metadataRegistry));
        addressMapping[16] = AddressMapping(
            "BasicMetadataProvider",
            address(basicMetadataProvider)
        );
        addressMapping[17] = AddressMapping(
            "SSTORE2MetadataProvider",
            address(sstore2MetadataProvider)
        );
        addressMapping[18] = AddressMapping("CrowdfundNFTRenderer", address(crowdfundNFTRenderer));
        addressMapping[19] = AddressMapping("PartyNFTRenderer", address(partyNFTRenderer));
        addressMapping[20] = AddressMapping("PartyHelpers", address(partyHelpers));
        addressMapping[21] = AddressMapping("AllowListGateKeeper", address(allowListGateKeeper));
        addressMapping[22] = AddressMapping("TokenGateKeeper", address(tokenGateKeeper));
        addressMapping[23] = AddressMapping("RendererStorage", address(rendererStorage));
        addressMapping[24] = AddressMapping(
            "PixeldroidConsoleFont",
            address(pixeldroidConsoleFont)
        );
        addressMapping[25] = AddressMapping("AtomicManualParty", address(atomicManualParty));
        addressMapping[26] = AddressMapping("ContributionRouter", address(contributionRouter));
        addressMapping[27] = AddressMapping(
            "AddPartyCardsAuthority",
            address(addPartyCardsAuthority)
        );

        console.log("");
        console.log("### Deployed addresses");
        string memory jsonRes = generateJSONString(addressMapping);
        console.log(jsonRes);

        writeAddressesToFile(deployConstants.networkName, jsonRes);
        writeAbisToFiles();
        console.log("");
        console.log("Ending deploy script.");
    }

    function generateJSONString(
        AddressMapping[] memory parts
    ) private pure returns (string memory) {
        string memory vals = "";
        for (uint256 i; i < parts.length; ++i) {
            string memory newValue = string.concat(
                '"',
                parts[i].key,
                '": "',
                Strings.toHexString(parts[i].value),
                '"'
            );
            if (i != parts.length - 1) {
                newValue = string.concat(newValue, ",");
            }
            vals = string.concat(vals, newValue);
        }
        return string.concat("{", vals, "}");
    }

    function writeAbisToFiles() private {
        string[] memory ffiCmd = new string[](2);
        ffiCmd[0] = "node";
        ffiCmd[1] = "./js/output-abis.js";
        bytes memory ffiResp = vm.ffi(ffiCmd);

        bool wroteSuccessfully = keccak256(ffiResp) ==
            keccak256(hex"0000000000000000000000000000000000000001");
        if (!wroteSuccessfully) {
            revert("Could not write ABIs to file");
        }
        console.log("Successfully wrote ABIS to files");
    }

    function writeAddressesToFile(string memory networkName, string memory jsonRes) private {
        string[] memory ffiCmd = new string[](4);
        ffiCmd[0] = "node";
        ffiCmd[1] = "./js/save-json.js";
        ffiCmd[2] = networkName;
        ffiCmd[3] = jsonRes;
        bytes memory ffiResp = vm.ffi(ffiCmd);

        bool wroteSuccessfully = keccak256(ffiResp) ==
            keccak256(hex"0000000000000000000000000000000000000001");
        if (!wroteSuccessfully) {
            revert("Could not write to file");
        }
        console.log("Successfully wrote to file");
    }
}
