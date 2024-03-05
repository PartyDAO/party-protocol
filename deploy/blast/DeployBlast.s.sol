// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Script.sol";

import "contracts/crowdfund/AuctionCrowdfund.sol";
import "contracts/crowdfund/BuyCrowdfund.sol";
import "contracts/crowdfund/CollectionBuyCrowdfund.sol";
import "contracts/crowdfund/CollectionBatchBuyCrowdfund.sol";
import "contracts/operators/CollectionBatchBuyOperator.sol";
import "contracts/operators/ERC20SwapOperator.sol";
import { InitialETHCrowdfundBlast } from "contracts/blast/InitialETHCrowdfundBlast.sol";
import { CrowdfundFactoryBlast } from "contracts/blast/CrowdfundFactoryBlast.sol";
import { TokenDistributorBlast } from "contracts/blast/TokenDistributorBlast.sol";
import "contracts/gatekeepers/AllowListGateKeeper.sol";
import "contracts/gatekeepers/TokenGateKeeper.sol";
import "contracts/gatekeepers/IGateKeeper.sol";
import "contracts/globals/Globals.sol";
import "contracts/globals/LibGlobals.sol";
import { PartyBlast } from "contracts/blast/PartyBlast.sol";
import "contracts/party/PartyFactory.sol";
import { MetadataRegistryBlast } from "contracts/blast/MetadataRegistryBlast.sol";
import { MetadataProviderBlast } from "contracts/blast/MetadataProviderBlast.sol";
import "contracts/renderers/CrowdfundNFTRenderer.sol";
import "contracts/renderers/PartyNFTRenderer.sol";
import "contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "contracts/proposals/ProposalExecutionEngine.sol";
import "contracts/utils/PartyHelpers.sol";
import "contracts/market-wrapper/NounsMarketWrapper.sol";
import { AtomicManualPartyBlast } from "contracts/blast/AtomicManualPartyBlast.sol";
import { ContributionRouterBlast } from "contracts/blast/ContributionRouterBlast.sol";
import { AddPartyCardsAuthority } from "contracts/authorities/AddPartyCardsAuthority.sol";
import { SellPartyCardsAuthority } from "contracts/authorities/SellPartyCardsAuthority.sol";
import { SSTORE2MetadataProviderBlast } from "contracts/blast/SSTORE2MetadataProviderBlast.sol";
import { BasicMetadataProviderBlast } from "contracts/blast/BasicMetadataProviderBlast.sol";
import { OffChainSignatureValidator } from "contracts/signature-validators/OffChainSignatureValidator.sol";
import { BondingCurveAuthorityBlast } from "contracts/blast/BondingCurveAuthorityBlast.sol";
import { MockZoraReserveAuctionCoreEth } from "test/proposals/MockZoraReserveAuctionCoreEth.sol";
import "../LibDeployConstants.sol";

abstract contract DeployBlast {
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
    InitialETHCrowdfundBlast public initialETHCrowdfund;
    CrowdfundFactoryBlast public crowdfundFactory;
    PartyBlast public party;
    PartyFactory public partyFactory;
    ProposalExecutionEngine public proposalExecutionEngine;
    TokenDistributorBlast public tokenDistributor;
    MetadataRegistryBlast public metadataRegistry;
    BasicMetadataProviderBlast public basicMetadataProvider;
    SSTORE2MetadataProviderBlast public sstore2MetadataProvider;
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
    AtomicManualPartyBlast public atomicManualParty;
    ContributionRouterBlast public contributionRouter;
    AddPartyCardsAuthority public addPartyCardsAuthority;
    SellPartyCardsAuthority public sellPartyCardsAuthority;
    OffChainSignatureValidator public offChainSignatureValidator;
    BondingCurveAuthorityBlast public bondingCurveAuthority;
    address constant BLAST = 0x4300000000000000000000000000000000000002;

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
        console.log("### TokenDistributorBlast");
        console.log("  Deploying - TokenDistributorBlast");
        _switchDeployer(DeployerRole.TokenDistributor);
        _trackDeployerGasBefore();
        tokenDistributor = new TokenDistributorBlast(
            globals,
            uint40(block.timestamp) + deployConstants.distributorEmergencyActionAllowedDuration,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - TokenDistributorBlast", address(tokenDistributor));
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_PROPOSAL_EXECUTION_ENGINE
        console.log("");
        console.log("### ProposalExecutionEngine");
        console.log("  Deploying - ProposalExecutionEngine");
        if (deployConstants.zoraReserveAuctionCoreEth == address(0)) {
            deployConstants.zoraReserveAuctionCoreEth = address(
                new MockZoraReserveAuctionCoreEth()
            );
        }
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
        console.log("### PartyBlast implementation");
        console.log("  Deploying - PartyBlast implementation");
        _trackDeployerGasBefore();
        party = new PartyBlast(globals, BLAST);
        _trackDeployerGasAfter();
        console.log("  Deployed - PartyBlast implementation", address(party));

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

        // DEPLOY_INITIAL_ETH_CF_IMPLEMENTATION
        console.log("");
        console.log("### InitialETHCrowdfundBlast crowdfund implementation");
        console.log("  Deploying - InitialETHCrowdfundBlast crowdfund implementation");
        _trackDeployerGasBefore();
        initialETHCrowdfund = new InitialETHCrowdfundBlast(globals, BLAST);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - InitialETHCrowdfundBlast crowdfund implementation",
            address(initialETHCrowdfund)
        );

        // DEPLOY_PARTY_CROWDFUND_FACTORY
        console.log("");
        console.log("### CrowdfundFactoryBlast");
        console.log("  Deploying - CrowdfundFactoryBlast");
        _switchDeployer(DeployerRole.CrowdfundFactory);
        _trackDeployerGasBefore();
        crowdfundFactory = new CrowdfundFactoryBlast(BLAST, deployConstants.partyDaoMultisig);
        _trackDeployerGasAfter();
        console.log("  Deployed - CrowdfundFactoryBlast", address(crowdfundFactory));
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_METADATA_REGISTRY
        address[] memory registrars = new address[](2);
        registrars[0] = address(partyFactory);
        registrars[1] = address(deployConstants.partyDaoMultisig);

        console.log("");
        console.log("### MetadataRegistryBlast");
        console.log("  Deploying - MetadataRegistryBlast");
        _trackDeployerGasBefore();
        metadataRegistry = new MetadataRegistryBlast(
            globals,
            registrars,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - MetadataRegistryBlast", address(metadataRegistry));

        // DEPLOY_BASIC_METADATA_PROVIDER
        console.log("");
        console.log("### BasicMetadataProviderBlast");
        console.log("  Deploying - BasicMetadataProviderBlast");
        _trackDeployerGasBefore();
        basicMetadataProvider = new BasicMetadataProviderBlast(
            globals,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - BasicMetadataProviderBlast", address(basicMetadataProvider));

        // DEPLOY_SSTORE2_METADATA_PROVIDER
        console.log("");
        console.log("### SSTORE2MetadataProviderBlast");
        console.log("  Deploying - SSTORE2MetadataProviderBlast");
        _trackDeployerGasBefore();
        sstore2MetadataProvider = new SSTORE2MetadataProviderBlast(
            globals,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - SSTORE2MetadataProviderBlast", address(sstore2MetadataProvider));

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
            deployConstants.tokenDistributorV1,
            deployConstants.tokenDistributorV2,
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

        // DEPLOY_SELL_PARTY_CARDS_AUTHORITY
        console.log("");
        console.log("### SellPartyCardsAuthority");
        console.log("  Deploying - SellPartyCardsAuthority");
        _trackDeployerGasBefore();
        sellPartyCardsAuthority = new SellPartyCardsAuthority();
        _trackDeployerGasAfter();
        console.log("  Deployed - SellPartyCardsAuthority", address(sellPartyCardsAuthority));

        // Deploy_BONDING_CURVE_AUTHORITY
        console.log("");
        console.log("### BondingCurveAuthorityBlast");
        console.log("  Deploying - BondingCurveAuthorityBlast");
        _trackDeployerGasBefore();
        bondingCurveAuthority = new BondingCurveAuthorityBlast(
            payable(deployConstants.partyDaoMultisig),
            250,
            1000,
            250,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - BondingCurveAuthorityBlast", address(bondingCurveAuthority));

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
        console.log("### ContributionRouterBlast");
        console.log("  Deploying - ContributionRouterBlast");
        _trackDeployerGasBefore();
        contributionRouter = new ContributionRouterBlast(
            deployConstants.partyDaoMultisig,
            deployConstants.contributionRouterInitialFee,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - ContributionRouterBlast", address(contributionRouter));

        // Deploy OFF_CHAIN_SIGNATURE_VALIDATOR
        console.log("");
        console.log("### OffChainSignatureValidator");
        console.log("  Deploying - OffChainSignatureValidator");
        _trackDeployerGasBefore();
        offChainSignatureValidator = new OffChainSignatureValidator();
        _trackDeployerGasAfter();
        console.log("  Deployed - OffChainSignatureValidator", address(offChainSignatureValidator));

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
        console.log("  Deploying - AtomicManualPartyBlast");
        _trackDeployerGasBefore();
        atomicManualParty = new AtomicManualPartyBlast(
            partyFactory,
            BLAST,
            deployConstants.partyDaoMultisig
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - AtomicManualPartyBlast", address(atomicManualParty));

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
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (
                    LibGlobals.GLOBAL_OFF_CHAIN_SIGNATURE_VALIDATOR,
                    address(offChainSignatureValidator)
                )
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

contract DeployScriptBlast is Script, DeployBlast {
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
        DeployBlast.deploy(deployConstants);
        vm.stopBroadcast();

        AddressMapping[] memory addressMapping = new AddressMapping[](25);
        addressMapping[0] = AddressMapping("Globals", address(globals));
        addressMapping[1] = AddressMapping("TokenDistributor", address(tokenDistributor));
        addressMapping[2] = AddressMapping(
            "ProposalExecutionEngine",
            address(proposalExecutionEngine)
        );
        addressMapping[3] = AddressMapping("Party", address(party));
        addressMapping[4] = AddressMapping("PartyFactory", address(partyFactory));
        addressMapping[10] = AddressMapping("InitialETHCrowdfund", address(initialETHCrowdfund));
        addressMapping[11] = AddressMapping(
            "CollectionBatchBuyOperator",
            address(collectionBatchBuyOperator)
        );
        addressMapping[12] = AddressMapping("ERC20SwapOperator", address(swapOperator));
        addressMapping[13] = AddressMapping("CrowdfundFactory", address(crowdfundFactory));
        addressMapping[14] = AddressMapping("MetadataRegistry", address(metadataRegistry));
        addressMapping[15] = AddressMapping(
            "BasicMetadataProvider",
            address(basicMetadataProvider)
        );
        addressMapping[16] = AddressMapping(
            "SSTORE2MetadataProvider",
            address(sstore2MetadataProvider)
        );
        addressMapping[17] = AddressMapping("CrowdfundNFTRenderer", address(crowdfundNFTRenderer));
        addressMapping[18] = AddressMapping("PartyNFTRenderer", address(partyNFTRenderer));
        addressMapping[19] = AddressMapping("PartyHelpers", address(partyHelpers));
        addressMapping[20] = AddressMapping("AllowListGateKeeper", address(allowListGateKeeper));
        addressMapping[21] = AddressMapping("TokenGateKeeper", address(tokenGateKeeper));
        addressMapping[22] = AddressMapping("RendererStorage", address(rendererStorage));
        addressMapping[23] = AddressMapping(
            "PixeldroidConsoleFont",
            address(pixeldroidConsoleFont)
        );
        addressMapping[24] = AddressMapping("AtomicManualParty", address(atomicManualParty));
        addressMapping[9] = AddressMapping("ContributionRouter", address(contributionRouter));
        addressMapping[8] = AddressMapping(
            "AddPartyCardsAuthority",
            address(addPartyCardsAuthority)
        );
        addressMapping[7] = AddressMapping("BondingCurveAuthority", address(bondingCurveAuthority));
        addressMapping[6] = AddressMapping(
            "SellPartyCardsAuthority",
            address(sellPartyCardsAuthority)
        );
        addressMapping[5] = AddressMapping(
            "OffChainSignatureValidator",
            address(offChainSignatureValidator)
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
