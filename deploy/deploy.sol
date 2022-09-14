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
import "../contracts/party/PartyFactory.sol";
import "../contracts/renderers/CrowdfundNFTRenderer.sol";
import "../contracts/renderers/PartyGovernanceNFTRenderer.sol";
import "../contracts/proposals/ProposalExecutionEngine.sol";
import "../contracts/utils/PartyHelpers.sol";
import "./LibDeployConstants.sol";

contract Deploy is Script {
    struct AddressMapping {
        string key;
        address value;
    }

    // After adding a new contract to deploy, please update `Deploy.t.sol`
    // to check that it was actually deployed.
    Globals globals;
    IZoraAuctionHouse zoraAuctionHouse;
    AuctionCrowdfund auctionCrowdfundImpl;
    BuyCrowdfund buyCrowdfundImpl;
    CollectionBuyCrowdfund collectionBuyCrowdfundImpl;
    CrowdfundFactory partyCrowdfundFactory;
    Party partyImpl;
    PartyFactory partyFactory;
    IOpenseaExchange seaport;
    ProposalExecutionEngine proposalEngineImpl;
    TokenDistributor tokenDistributor;
    CrowdfundNFTRenderer partyCrowdfundNFTRenderer;
    PartyGovernanceNFTRenderer partyGovernanceNFTRenderer;
    PartyHelpers partyHelpers;
    IGateKeeper allowListGateKeeper;
    IGateKeeper tokenGateKeeper;

    function run(LibDeployConstants.DeployConstants memory deployConstants) public {
        bytes32 networkHash = keccak256(abi.encodePacked(deployConstants.networkName));
        bool isFork = networkHash == keccak256("fork");
        bool isMainnet = networkHash == keccak256("mainnet");

        address deployer = isFork ? address(this) : tx.origin;

        if (!isFork) {
            console.log("Starting deploy script.");
            console.log("Deployer", deployer);
            vm.startBroadcast();
        }

        seaport = IOpenseaExchange(deployConstants.seaportExchangeAddress);

        // DEPLOY_GLOBALS
        if (!isFork) {
            console.log("");
            console.log("### Globals");
            console.log("  Deploying - Globals");
        }

        globals = new Globals(deployer);

        if (!isFork) {
            console.log("  Deployed - Globals", address(globals));

            console.log("");
            console.log("  Globals - setting PartyDao Multi-sig address");
        }

        if (isMainnet) {
            globals.setAddress(
                LibGlobals.GLOBAL_DAO_WALLET,
                deployConstants.partyDaoMultisig
            );
            console.log(
                "  Globals - successfully set PartyDao multi-sig address",
                deployConstants.partyDaoMultisig
            );
        } else if (isFork) {
            globals.setAddress(
                LibGlobals.GLOBAL_DAO_WALLET,
                deployConstants.partyDaoMultisig
            );
        } else {
            // Development/testnet deploy
            globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, deployer);
            console.log(
                "  Globals - successfully set PartyDao multi-sig address",
                deployer
            );
        }

        if (!isFork) {
            console.log("");
            console.log(
                "  Globals - setting DAO authority addresses",
                deployConstants.adminAddresses.length
            );
        }

        for (uint256 i = 0; i < deployConstants.adminAddresses.length; ++i) {
            address adminAddress = deployConstants.adminAddresses[i];
            if (!isFork) {
                console.log(
                    "  Globals - setting DAO authority address",
                    adminAddress
                );
            }
            globals.setIncludesAddress(
                LibGlobals.GLOBAL_DAO_AUTHORITIES,
                adminAddress,
                true
            );
            if (!isFork) {
                console.log(
                    "  Globals - successfully set DAO authority address",
                    adminAddress
                );
            }
        }

        if (!isFork) {
            console.log("  Globals - successfully set DAO authority addresses");

            console.log("  Globals - setting PartyDao split basis points");
        }

        globals.setUint256(
            LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT,
            deployConstants.partyDaoDistributionSplitBps
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set PartyDao split basis points",
                deployConstants.partyDaoDistributionSplitBps
            );
        }

        if (!isFork) {
            console.log("  Globals - setting seaport params");
        }

        globals.setBytes32(
            LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY,
            deployConstants.osConduitKey
        );
        globals.setAddress(
            LibGlobals.GLOBAL_OPENSEA_ZONE,
            deployConstants.osZone
        );

        if (!isFork) {
            console.log("  Globals - successfully set seaport values:");
            console.logBytes32(deployConstants.osConduitKey);
            console.log(deployConstants.osZone);
        }

        // DEPLOY_TOKEN_DISTRIBUTOR
        if (!isFork) {
            console.log("");
            console.log("### TokenDistributor");
            console.log("  Deploying - TokenDistributor");
        }

        tokenDistributor = new TokenDistributor(globals);

        if (!isFork) {
            console.log(
                "  Deployed - TokenDistributor",
                address(tokenDistributor)
            );

            console.log("");
            console.log("  Globals - setting Token Distributor address");
        }

        globals.setAddress(
            LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR,
            address(tokenDistributor)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set Token Distributor address",
                address(tokenDistributor)
            );
        }

        // CONFIG_LIMITS
        if (!isFork) {
            console.log("");

            console.log("");
            console.log(
                "  Globals - setting OpenSea and Zora auction variables"
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION,
            deployConstants.osZoraAuctionDuration
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set OpenSea Zora auction duration",
                deployConstants.osZoraAuctionDuration
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT,
            deployConstants.osZoraAuctionTimeout
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set OpenSea Zora auction timeout",
                deployConstants.osZoraAuctionTimeout
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION,
            deployConstants.osMinOrderDuration
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set OpenSea min order duration",
                deployConstants.osMinOrderDuration
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION,
            deployConstants.osMaxOrderDuration
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set OpenSea max order duration",
                deployConstants.osMaxOrderDuration
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION,
            deployConstants.zoraMinAuctionDuration
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set Zora min auction duration",
                deployConstants.zoraMinAuctionDuration
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION,
            deployConstants.zoraMaxAuctionDuration
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set Zora max auction duration",
                deployConstants.zoraMaxAuctionDuration
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT,
            deployConstants.zoraMaxAuctionTimeout
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set Zora max auction timeout",
                deployConstants.zoraMaxAuctionTimeout
            );
        }

        globals.setUint256(
            LibGlobals.GLOBAL_PROPOSAL_MAX_CANCEL_DURATION,
            deployConstants.proposalMaxCancelDuration
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set max cancel duration",
                deployConstants.proposalMaxCancelDuration
            );
        }

        // DEPLOY_PROPOSAL_EXECUTION_ENGINE
        if (!isFork) {
            console.log("");
            console.log("### ProposalExecutionEngine");
            console.log("  Deploying - ProposalExecutionEngine");
        }

        zoraAuctionHouse = IZoraAuctionHouse(
            deployConstants.zoraAuctionHouseAddress
        );
        IOpenseaConduitController conduitController = IOpenseaConduitController(
            deployConstants.osConduitController
        );
        IFractionalV1VaultFactory fractionalVaultFactory = IFractionalV1VaultFactory(
                deployConstants.fractionalVaultFactory
            );
        proposalEngineImpl = new ProposalExecutionEngine(
            globals,
            seaport,
            conduitController,
            zoraAuctionHouse,
            fractionalVaultFactory
        );

        if (!isFork) {
            console.log(
                "  Deployed - ProposalExecutionEngine",
                address(proposalEngineImpl)
            );
            console.log(
                "    with seaport",
                address(seaport)
            );
            console.log(
                "    with zora auction house",
                address(zoraAuctionHouse)
            );

            console.log("");
            console.log(
                "  Globals - setting Proposal engine implementation address"
            );
        }

        globals.setAddress(
            LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL,
            address(proposalEngineImpl)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set Proposal engine implementation address",
                address(proposalEngineImpl)
            );
        }

        // DEPLOY_PARTY_IMPLEMENTATION
        if (!isFork) {
            console.log("");
            console.log("### Party implementation");
            console.log("  Deploying - Party implementation");
        }

        partyImpl = new Party(globals);

        if (!isFork) {
            console.log(
                "  Deployed - Party implementation",
                address(partyImpl)
            );

            console.log("");
            console.log("  Globals - setting Party implementation address");
        }

        globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));

        if (!isFork) {
            console.log(
                "  Globals - successfully set Party implementation address",
                address(partyImpl)
            );
        }

        // DEPLOY_PARTY_FACTORY
        if (!isFork) {
            console.log("");
            console.log("### PartyFactory");
            console.log("  Deploying - PartyFactory");
        }

        partyFactory = new PartyFactory(globals);

        if (!isFork) {
            console.log("  Deployed - PartyFactory", address(partyFactory));

            console.log("");
            console.log("  Globals - setting Party Factory address");
        }

        globals.setAddress(
            LibGlobals.GLOBAL_PARTY_FACTORY,
            address(partyFactory)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set Party Factory address",
                address(partyFactory)
            );
        }

        // DEPLOY_AUCTION_CF_IMPLEMENTATION
        if (!isFork) {
            console.log("");
            console.log("### AuctionCrowdfund crowdfund implementation");
            console.log(
                "  Deploying - AuctionCrowdfund crowdfund implementation"
            );
        }

        auctionCrowdfundImpl = new AuctionCrowdfund(globals);

        if (!isFork) {
            console.log(
                "  Deployed - AuctionCrowdfund crowdfund implementation",
                address(auctionCrowdfundImpl)
            );

            console.log("");
            console.log(
                "  Globals - setting AuctionCrowdfund crowdfund implementation address"
            );
        }

        globals.setAddress(
            LibGlobals.GLOBAL_AUCTION_CF_IMPL,
            address(auctionCrowdfundImpl)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set AuctionCrowdfund crowdfund implementation address",
                address(auctionCrowdfundImpl)
            );
        }

        // DEPLOY_BUY_CF_IMPLEMENTATION
        if (!isFork) {
            console.log("");
            console.log("### BuyCrowdfund crowdfund implementation");
            console.log("  Deploying - BuyCrowdfund crowdfund implementation");
        }

        buyCrowdfundImpl = new BuyCrowdfund(globals);

        if (!isFork) {
            console.log(
                "  Deployed - BuyCrowdfund crowdfund implementation",
                address(buyCrowdfundImpl)
            );

            console.log("");
            console.log(
                "  Globals - setting BuyCrowdfund crowdfund implementation address"
            );
        }

        globals.setAddress(
            LibGlobals.GLOBAL_BUY_CF_IMPL,
            address(buyCrowdfundImpl)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set BuyCrowdfund crowdfund implementation address",
                address(buyCrowdfundImpl)
            );
        }

        // DEPLOY_COLLECTION_BUY_CF_IMPLEMENTATION
        if (!isFork) {
            console.log("");
            console.log("### CollectionBuyCrowdfund crowdfund implementation");
            console.log(
                "  Deploying - CollectionBuyCrowdfund crowdfund implementation"
            );
        }

        collectionBuyCrowdfundImpl = new CollectionBuyCrowdfund(globals);

        if (!isFork) {
            console.log(
                "  Deployed - CollectionBuyCrowdfund crowdfund implementation",
                address(collectionBuyCrowdfundImpl)
            );

            console.log("");
            console.log(
                "  Globals - setting CollectionBuyCrowdfund crowdfund implementation address"
            );
        }

        globals.setAddress(
            LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL,
            address(collectionBuyCrowdfundImpl)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set CollectionBuyCrowdfund crowdfund implementation address",
                address(collectionBuyCrowdfundImpl)
            );
        }

        // DEPLOY_PARTY_CROWDFUND_FACTORY
        if (!isFork) {
            console.log("");
            console.log("### PartyCrowdfundFactory");
            console.log("  Deploying - PartyCrowdfundFactory");
        }

        partyCrowdfundFactory = new CrowdfundFactory(globals);

        if (!isFork) {
            console.log(
                "  Deployed - PartyCrowdfundFactory",
                address(partyCrowdfundFactory)
            );
        }

        // DEPLOY_PARTY_CROWDFUND_NFT_RENDERER
        if (!isFork) {
            console.log("");
            console.log("### CrowdfundNFTRenderer");
            console.log("  Deploying - CrowdfundNFTRenderer");
        }

        partyCrowdfundNFTRenderer = new CrowdfundNFTRenderer(globals);

        if (!isFork) {
            console.log(
                "  Deployed - CrowdfundNFTRenderer",
                address(partyCrowdfundNFTRenderer)
            );

            console.log("");
            console.log("  Globals - setting CrowdfundNFTRenderer address");
        }

        globals.setAddress(
            LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL,
            address(partyCrowdfundNFTRenderer)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set CrowdfundNFTRenderer",
                address(partyCrowdfundNFTRenderer)
            );
        }

        // DEPLOY_PARTY_GOVERNANCE_NFT_RENDERER
        if (!isFork) {
            console.log("");
            console.log("### PartyGovernanceNFTRenderer");
            console.log("  Deploying - PartyGovernanceNFTRenderer");
        }

        partyGovernanceNFTRenderer = new PartyGovernanceNFTRenderer(globals);

        if (!isFork) {
            console.log(
                "  Deployed - PartyGovernanceNFTRenderer",
                address(partyGovernanceNFTRenderer)
            );

            console.log("");
            console.log(
                "  Globals - setting PartyGovernanceNFTRenderer address"
            );
        }

        globals.setAddress(
            LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL,
            address(partyGovernanceNFTRenderer)
        );

        if (!isFork) {
            console.log(
                "  Globals - successfully set PartyGovernanceNFTRenderer",
                address(partyGovernanceNFTRenderer)
            );
        }

        // DEPLOY_PARTY_HELPERS
        if (!isFork) {
            console.log("");
            console.log("### PartyHelpers");
            console.log("  Deploying - PartyHelpers");
        }

        partyHelpers = new PartyHelpers();

        if (!isFork) {
            console.log("  Deployed - PartyHelpers", address(partyHelpers));
        }

        // DEPLOY_GATE_KEEPRS
        if (!isFork) {
            console.log("");
            console.log("### GateKeepers");
            console.log("  Deploying - AllowListGateKeeper");
        }

        allowListGateKeeper = new AllowListGateKeeper();

        if (!isFork) {
            console.log(
                "  Deployed - AllowListGateKeeper",
                address(allowListGateKeeper)
            );

            console.log("  Deploying - TokenGateKeeper");
        }

        tokenGateKeeper = new TokenGateKeeper();

        if (!isFork) {
            console.log(
                "  Deployed - TokenGateKeeper",
                address(tokenGateKeeper)
            );
        }

        if (isMainnet) {
            console.log("");
            console.log("### Transfer MultiSig");
            console.log(
                "  Transferring ownership to PartyDAO multi-sig",
                deployConstants.partyDaoMultisig
            );
        }

        if (isMainnet || isFork) {
            globals.transferMultiSig(deployConstants.partyDaoMultisig);
        }

        if (isMainnet) {
            console.log(
                "  Transferred ownership to",
                deployConstants.partyDaoMultisig
            );
        }

        if (isFork) return;

        AddressMapping[] memory addressMapping = new AddressMapping[](15);
        addressMapping[0] = AddressMapping("globals", address(globals));
        addressMapping[1] = AddressMapping("tokenDistributor", address(tokenDistributor));
        addressMapping[2] = AddressMapping("seaportExchange", address(seaport));
        addressMapping[3] = AddressMapping("proposalEngineImpl", address(proposalEngineImpl));
        addressMapping[4] = AddressMapping("partyImpl", address(partyImpl));
        addressMapping[5] = AddressMapping("partyFactory", address(partyFactory));
        addressMapping[6] = AddressMapping("auctionCrowdfundImpl", address(auctionCrowdfundImpl));
        addressMapping[7] = AddressMapping("buyCrowdfundImpl", address(buyCrowdfundImpl));
        addressMapping[8] = AddressMapping("collectionBuyCrowdfundImpl", address(collectionBuyCrowdfundImpl));
        addressMapping[9] = AddressMapping("partyCrowdfundFactory", address(partyCrowdfundFactory));
        addressMapping[10] = AddressMapping("partyCrowdfundNFTRenderer", address(partyCrowdfundNFTRenderer));
        addressMapping[11] = AddressMapping("partyGovernanceNFTRenderer", address(partyGovernanceNFTRenderer));
        addressMapping[12] = AddressMapping("partyHelpers", address(partyHelpers));
        addressMapping[13] = AddressMapping("allowListGateKeeper", address(allowListGateKeeper));
        addressMapping[14] = AddressMapping("tokenGateKeeper", address(tokenGateKeeper));

        console.log("");
        console.log("### Deployed addresses");
        string memory jsonRes = generateJSONString(addressMapping);
        console.log(jsonRes);

        vm.stopBroadcast();
        writeAddressesToFile(deployConstants.networkName, jsonRes);
        writeAbisToFiles();
        console.log("");
        console.log("Ending deploy script.");
    }

    function generateJSONString(AddressMapping[] memory parts) private pure returns (string memory) {
        string memory vals = "";
        for (uint256 i = 0; i < parts.length; ++i) {
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
