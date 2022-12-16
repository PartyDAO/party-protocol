// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Script.sol";

import "../contracts/crowdfund/AuctionCrowdfund.sol";
import "../contracts/crowdfund/BuyCrowdfund.sol";
import "../contracts/crowdfund/CollectionBuyCrowdfund.sol";
import "../contracts/crowdfund/CrowdfundFactory.sol";
import "../contracts/distribution/TokenDistributor.sol";
import "../contracts/gatekeepers/AllowListGateKeeper.sol";
import "../contracts/gatekeepers/TokenGateKeeper.sol";
import "../contracts/gatekeepers/IGateKeeper.sol";
import "../contracts/globals/Globals.sol";
import "../contracts/globals/LibGlobals.sol";
import "../contracts/party/Party.sol";
import "../contracts/party/PartyList.sol";
import "../contracts/party/PartyFactory.sol";
import "../contracts/renderers/CrowdfundNFTRenderer.sol";
import "../contracts/renderers/PartyNFTRenderer.sol";
import "../contracts/renderers/fonts/PixeldroidConsoleFont.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";
import "../contracts/utils/PartyHelpers.sol";
import "../contracts/market-wrapper/FoundationMarketWrapper.sol";
import "../contracts/market-wrapper/NounsMarketWrapper.sol";
import "../contracts/market-wrapper/ZoraMarketWrapper.sol";
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
    IZoraAuctionHouse public zoraAuctionHouse;
    AuctionCrowdfund public auctionCrowdfundImpl;
    BuyCrowdfund public buyCrowdfundImpl;
    CollectionBuyCrowdfund public collectionBuyCrowdfundImpl;
    CrowdfundFactory public crowdfundFactory;
    Party public partyImpl;
    PartyList public partyList;
    PartyFactory public partyFactory;
    IOpenseaExchange public seaport;
    ProposalExecutionEngine public proposalEngineImpl;
    TokenDistributor public tokenDistributor;
    RendererStorage public rendererStorage;
    CrowdfundNFTRenderer public crowdfundNFTRenderer;
    PartyNFTRenderer public partyNFTRenderer;
    PartyHelpers public partyHelpers;
    IGateKeeper public allowListGateKeeper;
    IGateKeeper public tokenGateKeeper;
    FoundationMarketWrapper public foundationMarketWrapper;
    NounsMarketWrapper public nounsMarketWrapper;
    ZoraMarketWrapper public zoraMarketWrapper;
    PixeldroidConsoleFont public pixeldroidConsoleFont;

    function deploy(LibDeployConstants.DeployConstants memory deployConstants) public virtual {
        _switchDeployer(DeployerRole.Default);

        seaport = IOpenseaExchange(deployConstants.seaportExchangeAddress);

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
        zoraAuctionHouse = IZoraAuctionHouse(deployConstants.zoraAuctionHouse);
        IOpenseaConduitController conduitController = IOpenseaConduitController(
            deployConstants.osConduitController
        );
        IFractionalV1VaultFactory fractionalVaultFactory = IFractionalV1VaultFactory(
            deployConstants.fractionalVaultFactory
        );
        _trackDeployerGasBefore();
        proposalEngineImpl = new ProposalExecutionEngine(
            globals,
            seaport,
            conduitController,
            zoraAuctionHouse,
            fractionalVaultFactory
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - ProposalExecutionEngine", address(proposalEngineImpl));

        // DEPLOY_PARTY_IMPLEMENTATION
        console.log("");
        console.log("### Party implementation");
        console.log("  Deploying - Party implementation");
        _trackDeployerGasBefore();
        partyImpl = new Party(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - Party implementation", address(partyImpl));

        // DEPLOY_PARTY_LIST
        console.log("");
        console.log("### PartyList");
        console.log("  Deploying - PartyList");
        _trackDeployerGasBefore();
        partyList = new PartyList(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - PartyList", address(partyList));

        // DEPLOY_PARTY_FACTORY
        console.log("");
        console.log("### PartyFactory");
        console.log("  Deploying - PartyFactory");
        _switchDeployer(DeployerRole.PartyFactory);
        _trackDeployerGasBefore();
        partyFactory = new PartyFactory(globals, partyList);
        _trackDeployerGasAfter();
        console.log("  Deployed - PartyFactory", address(partyFactory));
        _switchDeployer(DeployerRole.Default);

        // DEPLOY_AUCTION_CF_IMPLEMENTATION
        console.log("");
        console.log("### AuctionCrowdfund crowdfund implementation");
        console.log("  Deploying - AuctionCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        auctionCrowdfundImpl = new AuctionCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - AuctionCrowdfund crowdfund implementation",
            address(auctionCrowdfundImpl)
        );

        // DEPLOY_BUY_CF_IMPLEMENTATION
        console.log("");
        console.log("### BuyCrowdfund crowdfund implementation");
        console.log("  Deploying - BuyCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        buyCrowdfundImpl = new BuyCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - BuyCrowdfund crowdfund implementation",
            address(buyCrowdfundImpl)
        );

        // DEPLOY_COLLECTION_BUY_CF_IMPLEMENTATION
        console.log("");
        console.log("### CollectionBuyCrowdfund crowdfund implementation");
        console.log("  Deploying - CollectionBuyCrowdfund crowdfund implementation");
        _trackDeployerGasBefore();
        collectionBuyCrowdfundImpl = new CollectionBuyCrowdfund(globals);
        _trackDeployerGasAfter();
        console.log(
            "  Deployed - CollectionBuyCrowdfund crowdfund implementation",
            address(collectionBuyCrowdfundImpl)
        );

        // DEPLOY_PARTY_CROWDFUND_FACTORY
        console.log("");
        console.log("### CrowdfundFactory");
        console.log("  Deploying - CrowdfundFactory");
        _switchDeployer(DeployerRole.CrowdfundFactory);
        _trackDeployerGasBefore();
        crowdfundFactory = new CrowdfundFactory(globals);
        _trackDeployerGasAfter();
        console.log("  Deployed - CrowdfundFactory", address(crowdfundFactory));
        _switchDeployer(DeployerRole.Default);

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
            uint256 numOfColors = uint8(type(RendererBase.Color).max) + 1;
            bytes[] memory multicallData = new bytes[](numOfColors * 2);
            // Create customization options for all colors w/ both modes (light and dark).
            for (uint256 i; i < numOfColors; ++i) {
                multicallData[i * 2] = abi.encodeCall(
                    rendererStorage.createCustomizationPreset,
                    (
                        // Preset ID 0 is reserved. It is used to indicates to party instances
                        // to use the same customization preset as the crowdfund.
                        i + 1,
                        abi.encode(versionId, false, RendererBase.Color(i))
                    )
                );
                multicallData[i * 2 + 1] = abi.encodeCall(
                    rendererStorage.createCustomizationPreset,
                    (i + 1 + numOfColors, abi.encode(versionId, true, RendererBase.Color(i)))
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
            IFont(address(pixeldroidConsoleFont))
        );
        _trackDeployerGasAfter();
        console.log("  Deployed - PartyNFTRenderer", address(partyNFTRenderer));

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

        // DEPLOY_GATE_KEEPRS
        console.log("");
        console.log("### GateKeepers");
        console.log("  Deploying - AllowListGateKeeper");
        _trackDeployerGasBefore();
        allowListGateKeeper = new AllowListGateKeeper();
        _trackDeployerGasAfter();
        console.log("  Deployed - AllowListGateKeeper", address(allowListGateKeeper));

        // DEPLOY_MARKET_WRAPPERS
        console.log("");
        console.log("### MarketWrappers");
        if (address(deployConstants.deployedFoundationMarketWrapper) == address(0)) {
            console.log("  Deploying - FoundationMarketWrapper");
            _trackDeployerGasBefore();
            foundationMarketWrapper = new FoundationMarketWrapper(deployConstants.foundationMarket);
            _trackDeployerGasAfter();
            console.log("  Deployed - FoundationMarketWrapper", address(foundationMarketWrapper));
        } else {
            foundationMarketWrapper = FoundationMarketWrapper(
                deployConstants.deployedFoundationMarketWrapper
            );
        }
        if (address(deployConstants.deployedNounsMarketWrapper) == address(0)) {
            console.log("  Deploying - NounsMarketWrapper");
            _trackDeployerGasBefore();
            nounsMarketWrapper = new NounsMarketWrapper(deployConstants.nounsAuctionHouse);
            _trackDeployerGasAfter();
            console.log("  Deployed - NounsMarketWrapper", address(nounsMarketWrapper));
        } else {
            nounsMarketWrapper = NounsMarketWrapper(deployConstants.deployedNounsMarketWrapper);
        }
        if (address(deployConstants.deployedZoraMarketWrapper) == address(0)) {
            console.log("  Deploying - ZoraMarketWrapper");
            _trackDeployerGasBefore();
            zoraMarketWrapper = new ZoraMarketWrapper(deployConstants.zoraAuctionHouse);
            _trackDeployerGasAfter();
            console.log("  Deployed - ZoraMarketWrapper", address(zoraMarketWrapper));
        } else {
            zoraMarketWrapper = ZoraMarketWrapper(deployConstants.deployedZoraMarketWrapper);
        }

        console.log("");
        console.log("  Deploying - TokenGateKeeper");
        _trackDeployerGasBefore();
        tokenGateKeeper = new TokenGateKeeper();
        _trackDeployerGasAfter();
        console.log("  Deployed - TokenGateKeeper", address(tokenGateKeeper));

        // Set Global values and transfer ownership
        {
            console.log("### Configure Globals");
            bytes[] memory multicallData = new bytes[](23);
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
                (LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(proposalEngineImpl))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_AUCTION_CF_IMPL, address(auctionCrowdfundImpl))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_BUY_CF_IMPL, address(buyCrowdfundImpl))
            );
            multicallData[n++] = abi.encodeCall(
                globals.setAddress,
                (LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL, address(collectionBuyCrowdfundImpl))
            );
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

        AddressMapping[] memory addressMapping = new AddressMapping[](21);
        addressMapping[0] = AddressMapping("globals", address(globals));
        addressMapping[1] = AddressMapping("tokenDistributor", address(tokenDistributor));
        addressMapping[2] = AddressMapping("seaportExchange", address(seaport));
        addressMapping[3] = AddressMapping("proposalEngineImpl", address(proposalEngineImpl));
        addressMapping[4] = AddressMapping("partyImpl", address(partyImpl));
        addressMapping[5] = AddressMapping("partyFactory", address(partyFactory));
        addressMapping[6] = AddressMapping("auctionCrowdfundImpl", address(auctionCrowdfundImpl));
        addressMapping[7] = AddressMapping("buyCrowdfundImpl", address(buyCrowdfundImpl));
        addressMapping[8] = AddressMapping(
            "collectionBuyCrowdfundImpl",
            address(collectionBuyCrowdfundImpl)
        );
        addressMapping[9] = AddressMapping("partyCrowdfundFactory", address(crowdfundFactory));
        addressMapping[10] = AddressMapping(
            "partyCrowdfundNFTRenderer",
            address(crowdfundNFTRenderer)
        );
        addressMapping[11] = AddressMapping(
            "partyGovernanceNFTRenderer",
            address(partyNFTRenderer)
        );
        addressMapping[12] = AddressMapping("partyHelpers", address(partyHelpers));
        addressMapping[13] = AddressMapping("allowListGateKeeper", address(allowListGateKeeper));
        addressMapping[14] = AddressMapping("tokenGateKeeper", address(tokenGateKeeper));
        addressMapping[15] = AddressMapping(
            "foundationMarketWrapper",
            address(foundationMarketWrapper)
        );
        addressMapping[16] = AddressMapping("nounsMarketWrapper", address(nounsMarketWrapper));
        addressMapping[17] = AddressMapping("zoraMarketWrapper", address(zoraMarketWrapper));
        addressMapping[18] = AddressMapping("rendererStorage", address(rendererStorage));
        addressMapping[19] = AddressMapping(
            "pixeldroidConsoleFont",
            address(pixeldroidConsoleFont)
        );
        addressMapping[20] = AddressMapping("partyList", address(partyList));

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
        ffiCmd[1] = "./js/utils/output-abis.js";
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
        ffiCmd[1] = "./js/utils/save-json.js";
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
