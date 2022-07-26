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

- `PartyFactory` ([code](../contracts/party/PartyFactory.sol))
    - Creates new proxified `Party` instances.
- `Party` ([code](../contracts/party/Party.sol))
    - The governance contract that also custodies the precious NFTs. This is also the voting card 721 contract.
- `ProposalExecutionEngine` ([code](../contracts/proposals/ProposalExecutionEngine.sol))
    - An upgradable contract for executing each proposal type from the context of the `Party`.
- `TokenDistributor` ([code](../contracts/distributions/TokenDistributor.sol))
    - Distributes deposited ETH, ERC20, and ERC1155 tokens to members of parties.
- `Globals` ([code](../contracts/globals/Globals.sol))
    - A contract that defines global configuration values referenced by other contracts across the entire protocol.

![contracts](./governance-contracts.png)

## Party Creation

### Sequence

Parties are created through the `PartyFactory` contract. This is typically automatically done
by a crowdfund instance after it wins, but it is also a valid use case to interact with the PartyFactory contract directly to, for example, form a governance party around an existing NFT.

The sequence of events is:

1. Call `PartyFactory.createParty()` defined as:
    ```solidity
    function createParty(
        address authority,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
    ```
    - `authority` will be the address that can mint tokens on the created Party (indirectly through `PartyFactory.mint()`). In typical flow, the crowdfund contract will set this to itself.
    - `opts` are (mostly) immutable [configuration parameters](#governance-options) for the Party, defining the Party name and symbol (the Party instance will also be an ERC721) and governance parameters.
    - `preciousTokens` and `preciousTokenIds` together define the NFTs the Party will custody and enforce extra restrictions on so they are not easily transferred out of the Party. This list cannot be changed after Party creation.
2. Transfer assets to the created Party, which will typically be the precious NFTs.
3. As the `authority`, mint voting cards to members of the party by calling `PartyFactory.mint()`.
    - In typical flow, the crowdfund contract will call this when contributors burn their contribution NFTs.
4. Optionally, call `PartyFactory.abdicate()`, as the `authority`, to revoke minting privilege once all voting cards have been minted.
5. At any step after the party creation, members with voting cards can perform governance actions, though they may not be able to reach consensus if the total supply of voting power hasn't been minted/distributed yet.

## Governance Options

Parties are initialized with fixed governance options which will (mostly) never change for the Party's lifetime. They are defined in the `PartyGovernance.GovernanceOpts` struct with the fields:

- `hosts`: Array of initial party hosts. This is the only configuration that can change because hosts can transfer their privilege to other accounts.
- `voteDuration`: Duration in seconds a proposal can be voted on after it has been proposed.
- `executionDelay`: Duration in seconds a proposal must wait after being passed before it can be executed. This gives hosts time to veto malicious proposals that have passed.
- `passThresholdBps`: Minimum ratio of votes vs total voting power supply to consider a proposal passed. This is expressed in bps, i.e., 1e4 = 100%.
- `totalVotingPower`: Total voting power of the Party. This should be the sum of weights of all (possible) voting cards given to members. Note that nowhere is this assumption enforced, as there may be use-cases for minting more than 100% of voting power, but the logic in crowdfund contracts cannot mint more than `totalVotingPower`.
- `feeBps`: The fee taken out of this Party's [distributions](#distributions) to reserve for `feeRecipient` to claim. Typically this will be set to an address controlled by PartyDAO.
- `feeRecipient`: The address that can claim distribution fees for this Party.

## Voting Power

### Voting Cards
Voting power within the governance Party is represented and held by "voting cards," which are NFTs (721s) minted for each member of the Party. Each voting card has a distinct voting power/weight associated with it. The total (intrinsic) voting power a member has is the sum of all the voting power in all the voting cards they possess at a given block.

### Delegation
Owners of voting cards can call `Party.delegateVotingPower()` to delegate their intrinsic *total* voting power (at the time of the call) to another account. The minter of the voting card can also set an initial delegate for the owner, meaning any voting cards held by the owner will be delegated by default. If a user transfers their voting card, the voting power will be delegated to the recipient's existing delegate.

The chosen delegate does not need to own a voting card. Delegating voting power strips the owner of their entire voting power until they redelegate to themselves, meaning they will not be able to vote on proposals created afterwards. Voting card owners can recover their voting power for future proposals if they delegate to themselves or to the zero address.

### Calculating Effective Voting Power
The effective voting power of a user is the sum of all undelegated (or self-delegated) voting power from their voting cards plus the sum of all voting power delegated to them by other users.

The effective voting power of a user at a given time can be found by calling `Party.getVotingPowerAt()`.

### Voting Power Snapshots
The voting power applied when a user votes on a proposal is their effective voting power at the time the proposal was proposed. This prevents people from acquiring large amounts of voting cards to influence the outcome of an active proposal. The `Party` contract appends a record of a user's total delegated (to them) and intrinsic voting power each time any of the following occurs:

- A user receives a voting card (transfer or minting).
- A user transfers their voting card to another user.
- A user (un)delegates their voting power.
- A user gets voting power (un)delegated to them.

When determining the effective voting power of a user, we binary search a user's voting power records for the most recent record <= the proposal time.

## Distributions

TODO:
- What they are and how to trigger one
- How they're created (call sequence)
    - Off-chain storage
- How to claim
- Fees
- Emergency backdoors

## Governance Lifecycle

TODO:
- Proposal properties
    - Off-chain storage
- Stages/status of a proposal
- Proposing
    - Required states
- Voting
    - Required states
    - Unanimous consensus (+ definition)
- Vetos
- Execution
    - minExecutableTime
    - Multi-step proposals, progress data
    - Replay protection
- Cancelling
    - Rationale

## The ProposalExecutionEngine

TODO:
- Rationale
- Single execution enforcement
- Progress data enforcement
- Upgrades

## Proposal Types

### ListOnOpenSea Proposal Type

TODO:
- Proposal properties
- Steps
    - Create zora auction
    - Cancel/Finalize zora auction
    - Create OS listing
    - Finalize OS listing
- Behavior when unanimous

### ListOnZora Proposal Type

TODO:
- Proposal properties
- Steps
    - Create zora auction
    - Cancel/Finalize zora auction

### Fractionalize Proposal Type

...

### ArbitraryCalls Proposal Type

TODO:
- Proposal/Call properties
- Restricted operations
- Behavior when unanimous
- Attaching ETH

### UpgradeProposalEngineImpl Proposal Type

TODO:
- Proposal properties (none)
- Use of Global
- Security concerns
    - Bricking parties

## Emergency Backdoors

TODO:
- Rationale
- Revoking
