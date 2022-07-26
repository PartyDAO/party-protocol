# Crowdfund Contracts

These contracts allow people to create and join a crowdfund, pooling ETH together to acquire an NFT. Multiple crowdfund contracts exist for specific acquisition patterns.

## Key Concepts

- **Participation Cards**: A *soulbound* NFT (721) representing contributions made to a crowdfund.
- **Party**: The governance contract, which will be created and will custody the NFT after it has been acquired by the crowdfund.
- **Globals**: A single contract that holds configuration values, referenced by several ecosystem contracts.
- **Proxies**: All `PartyCrowdfund` instances are deployed as simple [`Proxy`](../contracts/utils/Proxy.sol) contracts that forward calls to a `Party` implementation contract.

## Contracts

The main contracts involved in this phase are:

- `PartyCrowdfundFactory`([source](../contracts/crowdfund/PartyCrowdfundFactory.sol))
    - ...
- `PartyBuy` ([source](../contracts/crowdfund/PartyBuy.sol))
    - ...
- `PartyCollectionBuy` ([source](../contracts/crowdfund/PartyCollectionBuy.sol))
    - ...
- `PartyBid` ([source](../contracts/crowdfund/PartyBid.sol))
    - ...
- `IGateKeeper` ([source](../contracts/gateKeepers/IGateKeeper.sol))
    - ...
- `Globals` ([source](../contracts/globals/Globals.sol))
    - ...


...
