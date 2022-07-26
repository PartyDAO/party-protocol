# Governance Contracts

After a crowdfund has acquired its NFTs, they transfer it to a governance `Party` around it, where the contributors are minted voting power equivalent to their contribution during the crowdfund and use that voting power to vote on proposals to be executed as the party.

## Key Concepts

- **Precious**: An NFT custodied by the governance contract (`Party`), conventionally acquired by the crowdfund phase. These are protected assets and are subject to extra restrictions in proposals vs other assets.
- **Voting Cards**: An NFT (721) representing voting power within the governance Party.
- **Party**: The governance contract itself, which custodies the NFT, tracks voting power, manages the lifecycle of proposals, and is simultaneously is the governance token (Voting Cards).
- **Proposals**: On-chain actions that will be executed as the party that must progress through the entire governance lifecycle (voting, etc).
- **Distributions**: An (ungoverned) mechanism by which parties can distribute ETH, ERC20, and ERC1155 tokens held by the party to members proportional to their relative voting power (voting cards).
- **Party Hosts**: Predefined accounts that can unilaterally veto proposals in the party. Conventionally defined when the crowdfund is created.
- **Globals**: A single contract that holds configuration values, referenced by several ecosystem contracts.
- **Proxies**: All `Party` instances are deployed as simple [`Proxy`](../contracts/utils/Proxy.sol) contracts that forward calls to a `Party` implementation contract.
- **ProposalExecutionEngine**: An upgradable contract the `Party` contract delegatecalls into that implements the logic for executing specific proposal types.  

## Contracts

The main contracts involved in this phase are:

- [`PartyFactory`](./PartyFactory.md) ([code](../contracts/party/PartyFactory.sol))
    - Creates new proxified `Party` instances.
- [`Party`](./Party.md) ([code](../contracts/party/Party.sol))
    - The governance contract that also custodies the precious NFTs. This is also the voting card 721 contract.
- [`ProposalExecutionEngine`](./ProposalExecutionEngine.md) ([code](../contracts/proposals/ProposalExecutionEngine.sol))
    - An upgradable contract for executing each proposal type from the context of the `Party`.
- [`TokenDistributor`](./TokenDistributor.md) ([code](../contracts/distributions/TokenDistributor.sol))
    - Distributes deposited ETH, ERC20, and ERC1155 tokens to members of parties.
- [`Globals`](../Globals.md) ([code](../contracts/globals/Globals.sol))
    - A contract that shares global configuration values referenced by contracts across the entire protocol.

![contracts](./governance-contracts.png)

## Party Creation

TODO:
- How parties get created
- Governance options
- Party hosts
- Minting voting cards
- Preciouses

## Voting Power

TODO:
- Voting cards
    - Weight
    - NFT
- Delegation
- Voting power snapshots

## Distributions

TODO:
- What they are and how to trigger one
- How they're created (call sequence)
- How to claim
- Fees
- Emergency backdoors

## Governance Lifecycle

TODO:
- Proposal properties
- Stages of a proposal
- Proposing
- Voting
    - Unanimous consensus
- Vetos
- Execution
    - Multi-step proposals, progress data
    - Replay protection
- Cancelling

## The ProposalExecutionEngine

TODO:
- Rationale
- Single execution enforcement
- Progress data enforcement
- Upgrades

## Proposal Types

### ListOnOpenSea Proposal Type
### ListOnZora Proposal Type
### Fractionalize Proposal Type
### ArbitraryCalls Proposal Type
### UpgradeProposalEngineImpl Proposal Type

## Emergency Backdoors
- Rationale
- Revoking
