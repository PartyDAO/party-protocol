# Audit Report - PartyDAO
|                |                                                                           |
| -------------- | ------------------------------------------------------------------------- |
| **Audit Date** | 07/12/2023 - 07/14/2023                                                   |
| **Auditor**    | HollaDieWaldfee ([@HollaWaldfee100](https://twitter.com/HollaWaldfee100)) |
| **Version 1**  | 07/14/2023 Initial Report                                                 |
| **Version 2**  | 07/14/2023 Updated Findings                                               |
| **Version 3**  | 07/20/2023 Mitigation Review                                              |

# Contents
- [Disclaimer](#disclaimer)
- [About HollaDieWaldfee](#about-holladiewaldfee)
- [Scope](#scope)
- [Severity classification](#severity-classification)
- [Summary](#summary)
- [Findings](#findings)

# Disclaimer
_The following smart contract audit report is based on the information and code provided by the client, and any findings or recommendations are made solely on the basis of this information. While the Auditor has exercised due care and skill in conducting the audit, it cannot be guaranteed that all issues have been identified and that there are no undiscovered errors or vulnerabilities in the code._

_Furthermore, this report is not an endorsement or certification of the smart contract, and the Auditor does not assume any responsibility for any losses or damages that may result from the use of the smart contracts, either in their current form or in any modified version thereof._

# About HollaDieWaldfee
HollaDieWaldfee is a top ranked Smart Contract Auditor doing audits on code4rena (www.code4rena.com) and Sherlock (www.sherlock.xyz), having ranked 1st in multiple contests.<br>
On Sherlock he uses the handle "roguereddwarf" to compete in contests.<br>
He can also be booked for conducting Private Audits.

Contact: <br>

Twitter: [@HollaWaldfee100](https://twitter.com/HollaWaldfee100)

# Scope
The scope of the audit is the following Pull Request in the client's GitHub repository:
https://github.com/PartyDAO/party-protocol/pull/239/

Specifically the audited changes are the following:
* Add ERC20SwapOperator to allow Parties to swap ETH/ERC20s
* Update OperatorProposal to transfer ERC20/ERC721/ERC1155s to the Operator to use on behalf of the Party
* Update from Zora v2 to v3
* Add option for items bought through operators to be received directly by the Party instead of indirectly through the Operator

As part of the Mitigation Review the following changes have been reviewed which were not part of the original audit:  
https://github.com/PartyDAO/party-protocol/pull/235/files/f71af0aedba4c4e3f794bfa85d8d5b95797a77ce..d2d6bd93c620da7480a9d11c169be6a82cc3cfc3

# Severity Classification
| Severity               | Impact: High | Impact: Medium | Impact: Low |
| ---------------------- | ------------ | -------------- | ----------- |
| **Likelihood: High**   | ![high]      | ![high]        | ![medium]   |
| **Likelihood: Medium** | ![high]      | ![medium]      | ![low]      |
| **Likelihood: Low**    | ![medium]    | ![low]         | ![low]      |

**Impact** - the technical, economic and reputation damage of a successful attack

**Likelihood** - the chance that a particular vulnerability is discovered and exploited

![improvement]: Findings in this category are recommended changes that are not related to security but can improve structure, usability and overall effectiveness of the protocol.


# Summary

| Severity       | Total | Fixed | Acknowledged | Disputed | Reported |
| -------------- | ----- | ----- | ------------ | -------- | -------- |
| ![high]        | 1     | 1     | 0            | 0        | 0        |
| ![medium]      | 2     | 2     | 0            | 0        | 0        |
| ![low]         | 2     | 2     | 0            | 0        | 0        |
| ![improvement] | 1     | 1     | 0            | 0        | 0        |

| #   | Title                                                                                                                                                                                          | Severity       | Status   |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | -------- |
| 1   | [OperatorProposal: assets can be accessed by operator contracts when it should be restricted](#1-operatorproposal-assets-can-be-accessed-by-operator-contracts-when-it-should-be-restricted--) | ![high]        | ![fixed] |
| 2   | [CollectionBatchBuyOperator: Operator can steal funds by purchasing NFT multiple times](#2-collectionbatchbuyoperator-operator-can-steal-funds-by-purchasing-nft-multiple-times--)             | ![medium]      | ![fixed] |
| 3   | [ERC20SwapOperator: Operator can steal funds and minReceivedAmount is checked incorrectly](#3-erc20swapoperator-operator-can-steal-funds-and-minreceivedamount-is-checked-incorrectly--)       | ![medium]      | ![fixed] |
| 4   | [ERC20SwapOperator: leftover fromToken amount is not refunded](#4-erc20swapoperator-leftover-fromtoken-amount-is-not-refunded--)                                                               | ![low]         | ![fixed] |
| 5   | [CollectionBatchBuyOperator: contract might not be able to receive NFTs](#5-collectionbatchbuyoperator-contract-might-not-be-able-to-receive-nfts--)                                           | ![low]         | ![fixed] |
| 6   | [ListOnZoraProposal: Zora auction module is approved multiple times](#6-listonzoraproposal-zora-auction-module-is-approved-multiple-times--)                                                   | ![improvement] | ![fixed] |


# Findings
## High Risk Findings (1)
### 1. OperatorProposal: assets can be accessed by operator contracts when it should be restricted ![high] ![fixed]
**Description:**<br>
As part of the audited changes, the `OperatorProposal` contract now has the ability to not only send ETH to an operator contract but also ERC20, ERC721 and ERC1155 tokens ([Link](https://github.com/PartyDAO/party-protocol/pull/239/files#diff-3933d98f4e5ccd810218c03b9281238253301893dbcad35eceda78c7403ceae2R68-R84)).  

The ability for the `OperatorProposal` contract to transfer ETH can be restricted by the `allowOperatorsToSpendPartyEth` variable ([Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/proposals/ProposalStorage.sol#L24-L26)).  

Since there is now the ability to transfer these four kinds of assets, the `allowOperatorsToSpendPartyEth` variable fails to protect against proposals accessing assets via operator contracts.  

**Impact:**<br>
Security assumptions are broken with regards to how assets can be transferred out of the Party.  

As discussed with the client, it should e.g. not be possible for a "precious NFT" to be transferred out of a Party via an operator proposal since they generally do not require an unanimous vote.  

E.g. 40% of the voting power (assuming this is the threshold for a successful proposal) should not have unbounded access to a "precious NFT".  

Since the very assets that should be protected within the Party are at risk I assess this issue to be of "High" severity.  

The severity is higher than that of **Finding 2** and **Finding 3** since all assets (except ETH) within the Party are at risk (not just the fraction of assets transferred to the operator contract).  

**Recommendation:**<br>
As discussed with the client, the `allowOperatorsToSpendPartyEth` variable should now manage access to all four kinds of assets.  

If it is set to `false` it should not be possible for operator proposals to access ANY assets within the Party.  

**Fix:**<br>
The fix has been implemented in the following commit:  
https://github.com/PartyDAO/party-protocol/commit/fa7459de75b26034da23eef5cb414aa8e97a7c84  

While it was recommended to change the `allowOperatorsToSpendPartyEth` variable such that it manages access to all four asset types (i.e. operator proposals are always possible if they don't access any assets of the party), the client chose to implement a slightly different fix.  

The `allowOperatorsToSpendPartyEth` variable has been renamed to `allowOperators` and therefore this variable now determines if operators are enabled at all.  

In the case that `allowOperators=false`, the `ProposalExecutionEngine` prohibits the execution of any operator proposal.  

Therefore parties with precious NFTs would have their NFTs protected from unauthorized use in an operator contract.  

## Medium Risk Findings (2)

### 2. CollectionBatchBuyOperator: Operator can steal funds by purchasing NFT multiple times ![medium] ![fixed]
**Description:**<br>
As part of the audited changes, NFTs that are bought via the `CollectionBatchBuyOperator` contract can now be sent to the Party directly by setting `isReceivedDirectly=true`.  

These changes introduced as a side-effect the ability for an operator to cause significant damage, i.e. to steal funds that were intended to purchase certain NFTs.  

Previously only the `CollectionBatchBuyOperator` contract was able to receive the NFTs, i.e. the Party could not directly act as the receiver of the NFTs and it was not possible for the operator to buy an NFT once and then "buy" it again while actually sending the funds to himself.  

That's because the NFT would be transferred to the Party twice and the second attempt would fail ([Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/operators/CollectionBatchBuyOperator.sol#L195-L199)).

However now the Party can act as the receiver. Therefore the operator can buy the NFT once and then "buy" it again but actually just transferring ETH to himself.  

Downstream there would be no revert because it would not be attempted to transfer the NFT.  

An exploit might look like this:  
* Actually buy NFT A from a marketplace for 1 ETH
* "buy" NFT A again but just transfer 1 ETH to operator

**Impact:**<br>
In principle the operator is a trusted actor in the context of the NFT purchase.  

However the `CollectionBatchBuyOperator` contract DOES employ safety measures to limit the trust that the Party needs to put into the operator (e.g. only allow to buy certain NFTs).  

Not being able to buy NFTs "twice" and thereby to steal funds is a safety measure that existed previously and is now broken.  

Therefore, even though the operator is in principle trusted, this is a security vulnerability.  

Since the operator is trusted and the amount of funds that can be stolen is limited to those sent to the `CollectionBatchBuyOperator` (i.e. funds that stay in the Party are safe) this is an issue of "Medium" severity.  

**Recommendation:**<br>
I recommend a check before each purchase of an NFT that the NFT is not already owned by the `receiver`. This prevents the NFT from being purchased "twice".  

```diff
diff --git a/contracts/operators/CollectionBatchBuyOperator.sol b/contracts/operators/CollectionBatchBuyOperator.sol
index 8be587a..a24c611 100644
--- a/contracts/operators/CollectionBatchBuyOperator.sol
+++ b/contracts/operators/CollectionBatchBuyOperator.sol
@@ -78,6 +78,7 @@ contract CollectionBatchBuyOperator is IOperator {
     error CallProhibitedError(address target, bytes data);
     error NumOfTokensCannotBeLessThanMin(uint256 numOfTokens, uint256 min);
     error EthUsedForFailedBuyError(uint256 expectedEthUsed, uint256 actualEthUsed);
+    error AlreadyOwnerError();
 
     function execute(
         bytes memory operatorData,
@@ -123,6 +124,10 @@ contract CollectionBatchBuyOperator is IOperator {
             for (uint256 j; j < call.tokensToBuy.length; ++j) {
                 TokenToBuy memory tokenToBuy = call.tokensToBuy[j];
 
+                if (op.nftContract.safeOwnerOf(tokenToBuy.tokenId) == receiver) {
+                    revert AlreadyOwnerError();
+                }
+
                 if (op.nftTokenIdsMerkleRoot != bytes32(0)) {
                     // Verify the token ID is in the merkle tree.
                     _verifyTokenId(tokenToBuy.tokenId, op.nftTokenIdsMerkleRoot, tokenToBuy.proof);
```

**Fix:**<br>
The fix has been implemented in the following commit:  
https://github.com/PartyDAO/party-protocol/commit/fe41c97d576a2b856043962a67290e6a533abddb  

The fix implements the recommended change. However the fix checks if `msg.sender` (the party) is the owner of the NFT as opposed to checking `receiver` as I recommended. But this is equivalent in that it prevents the described attack, and so the attack is successfully mitigated.   

(In the case that the party is the receiver of the NFT it is obviously not possible to buy an NFT "twice" since `msg.sender=receiver`. In the case that the operator contract is the receiver it is not obvious that the check works. We must first notice that it is not possible for the same NFT to be contained twice within one `BuyCall` because `tokenIds` within a `BuyCall` must now be strictly increasing. If the same NFT was to be bought "twice" via subsequent `BuyCalls` we end up with the correct check since the NFTs are now transferred to the party after each `BuyCall` (as opposed to after all `BuyCalls`))

In addition, there are more changes as part of the commit which were checked by reviewing the `CollectionBatchBuyOperator` in its entirety to ensure there are no new issues that aren't apparent when looking at the fix for this issue in isolation.  

### 3. ERC20SwapOperator: Operator can steal funds and minReceivedAmount is checked incorrectly ![medium] ![fixed]
**Description:**<br>
This finding is in principle similar to **Finding 2** in that it deals with how the operator can steal funds.  

The root cause is how the `ERC20SwapOperator` contract calculates the amount of received `toToken`:  

[Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/operators/ERC20SwapOperator.sol#L134-L137)  
```solidity
// Get the received amount.
uint256 receivedAmount = op.toToken == ETH_TOKEN_ADDRESS
    ? receiver.balance
    : op.toToken.balanceOf(receiver);
```

Assume the case where `receiver` is the address of the Party.  

Assuming that the Party already owns some amount of `toToken` before the swap, the calculated `receivedAmount` is incorrect.  

Therefore the subsequent check might succeed even though it should not:  
[Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/operators/ERC20SwapOperator.sol#L139-L142)  
```solidity
// Check that the received amount is at least the minimum specified.
if (receivedAmount < op.minReceivedAmount) {
    revert InsufficientReceivedAmountError(receivedAmount, op.minReceivedAmount);
}
```

This allows the operator to steal funds by setting himself as the receiver of some or all of the tokens in the swap calldata.  

In addition to that we must not overlook the fact that the `minReceivedAmount` might fail to serve its purpose of protectiong against executing the swap at an unintended price.  

**Impact:**<br>
The reasoning here is similar to that in **Finding 2**.  

The operator is generally trusted and the amount of funds that can be stolen is limited to those that the Party sends to the `ERC20SwapOperator`.  

Considering that `minReceivedAmount` fails to protect against swaps at an unintended price, this finding has an even higher impact than **Finding 2**.  

Still, the severity is "Medium" due to the fact that the operator is a trusted actor and executing the swap at an unintended price does not raise the issue to a "High" impact.  

**Recommendation:**<br>
In the case that the Party is the receiver, the `toToken` balance of the Party before the swap should be compared with that after the swap in order to get the correct `receivedAmount`.  

```diff
diff --git a/contracts/operators/ERC20SwapOperator.sol b/contracts/operators/ERC20SwapOperator.sol
index ee9e862..e9d6722 100644
--- a/contracts/operators/ERC20SwapOperator.sol
+++ b/contracts/operators/ERC20SwapOperator.sol
@@ -117,6 +117,15 @@ contract ERC20SwapOperator is IOperator {
             op.fromToken.approve(ex.target, amount);
         }
 
+        uint256 balanceBefore;
+        if (ex.isReceivedDirectly) {
+            if (op.toToken == ETH_TOKEN_ADDRESS) {
+                balanceBefore = address(msg.sender).balance;
+            } else {
+                balanceBefore = op.toToken.balanceOf(address(msg.sender));
+            }
+        }
+
         // Perform the swap.
         {
             uint256 value = op.fromToken == ETH_TOKEN_ADDRESS ? amount : 0;
@@ -135,6 +144,7 @@ contract ERC20SwapOperator is IOperator {
         uint256 receivedAmount = op.toToken == ETH_TOKEN_ADDRESS
             ? receiver.balance
             : op.toToken.balanceOf(receiver);
+        receivedAmount -= balanceBefore;
 
         // Check that the received amount is at least the minimum specified.
         if (receivedAmount < op.minReceivedAmount) {
```

**Fix:**<br>
The fix has been implemented in the following commit:  
https://github.com/PartyDAO/party-protocol/commit/b35407f53a75e9da59cea67cfb43857f4e614fdc  

The fix is as recommended above (with minor optimization but semantically equivalent).  

## Low Risk Findings (2)

### 4. ERC20SwapOperator: leftover fromToken amount is not refunded ![low] ![fixed]
**Description:**<br>
The `ERC20SwapOperator` contract allows a Party to swap Token A for Token B.  

The issue is that any leftover amount of Token A is not refunded to the party.  

There is a whitelist of swap targets and the operator can provide arbitrary calldata. Therefore it's possible that the swap is executed partially (e.g. due to slippage protection).  

It must also be considered that the `CollectionBatchBuyOperator` DOES perform a refund ([Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/operators/CollectionBatchBuyOperator.sol#L202-L210)) so the new `ERC20SwapOperator` should do it as well so as not to break assumptions.  

**Impact:**<br>
Since the `ERC20SwapOperator.execute` function can be called by anyone, the leftover tokens can be stolen by anyone (by swapping them for another token).  

Even though the operator is trusted it is possible that this issue occurs by mistake (-> partial swap).  

Under the assumption that `minReceivedAmount` is chosen such that the operator could not meaningfully profit from an exploitation by e.g. partially swapping `fromToken -> intermediate Token -> toToken` and thereby leaving some amount of "intermediate Token" which would not get refunded, adding a basic refund to the contract is a sufficient mitigation.  

**Recommendation:**<br>
```diff
diff --git a/contracts/operators/ERC20SwapOperator.sol b/contracts/operators/ERC20SwapOperator.sol
index ee9e862..a3a9372 100644
--- a/contracts/operators/ERC20SwapOperator.sol
+++ b/contracts/operators/ERC20SwapOperator.sol
@@ -157,6 +157,18 @@ contract ERC20SwapOperator is IOperator {
             }
         }
 
+        uint256 refundAmount = op.fromToken == ETH_TOKEN_ADDRESS
+            ? receiver.balance
+            : op.fromToken.balanceOf(receiver);
+        
+        if (refundAmount != 0) {
+            if (op.fromToken == ETH_TOKEN_ADDRESS) {
+                payable(msg.sender).transferEth(refundAmount);
+            } else {
+                op.fromToken.compatTransfer(msg.sender, refundAmount);
+            }
+        }
+
         emit ERC20SwapOperationExecuted(
             Party(payable(msg.sender)),
             op.fromToken,
```

**Fix:**<br>
The fix has been implemented in the following commit:  
https://github.com/PartyDAO/party-protocol/commit/cfb70c608d6bbd8dac73979b48b42aa8faf17255  

The fix is as recommended above.  


### 5. CollectionBatchBuyOperator: contract might not be able to receive NFTs ![low] ![fixed]
**Description:**<br>
The `CollectionBatchBuyOperator` contract allows a Party to purchase NFTs.  

Assuming a NFT is purchased, the NFT is either sent to the Party directly (`isReceivedDirectly=true`) or it is sent to the `CollectionBatchBuyOperator` (`isReceivedDirectly=false`) which then forwards it to the Party.  

The problem here is that the `CollectionBatchBuyOperator` contract does not implement the `onERC721Received` function which means that it cannot receive NFTs if they're transferred to it via a `safeTransfer` function.  

**Impact:**<br>
Due to the behavior described above, the `CollectionBatchBuyOperator` could not be used as intended when an NFT is attempted to be transferred via a `safeTransfer` function.  

There is no loss of funds or other substantial impact.  

Still I estimate this as Low impact since the contract breaks its intended behavior, causing unintended reverts.  

**Recommendation:**<br>
I recommend that the `CollectionBatchBuyOperator` contract inherits from `ERC721Receiver` ([Link](https://github.com/PartyDAO/party-protocol/blob/audit/contracts/tokens/ERC721Receiver.sol)) such that it can receive NFTs when they are transferred via a `safeTransfer` function.  

**Fix:**<br>
The fix has been implemented in the following commit:  
https://github.com/PartyDAO/party-protocol/commit/bbd9fbf421fd4f9c8e72e179dd79414d7dc7b5f0  

The fix is as recommended above.  

## Improvement Findings (1)
### 6. ListOnZoraProposal: Zora auction module is approved multiple times ![improvement] ![fixed]
**Description:**<br>
The `ListOnZoraProposal` contract contains the following check:  

[Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/proposals/ListOnZoraProposal.sol#L145-L147)  
```solidity
if (!zoraAuctionModuleApproved) {
    ZORA_TRANSFER_HELPER.ZMM().setApprovalForModule(address(ZORA), true);
}
```

The purpose of this is to ensure that the Zora `ReserveAuctionCoreEth` contract is allowed to transfer the auctioned NFT from the Party to the bidder.  

The intention of the `zoraAuctionModuleApproved` variable is to only make the approval once.  

However the `zoraAuctionModuleApproved` variable is never set and always evaluates to `false`.  

Since the `ProposalExecutionEngine` contract, which inherits from `ListOnZoraProposal`, is delegatecall'ed into by the Party, we must consider storage collisions and can not just simply set `zoraAuctionModuleApproved=true` without further consideration.  

**Impact:**<br>
There is no security impact to this finding.  
It's just that the approval would be set multiple times when once would be sufficient.  

**Recommendation:**<br>
As explained above, the Party performs a delegatecall into the `ProposalExecutionEngine` and so setting the `zoraAuctionModuleApproved` variable to `true` in the `if` block from above would actually cause a storage collision with the variables defined in the Party.  

I propose to adopt the unstructured storage pattern that's already used for the `ProposalEngineOpts` struct: [Link](https://github.com/PartyDAO/party-protocol/blob/b0c85da2a4e65df2afcefd9435ef25d3e826dc0f/contracts/proposals/ProposalStorage.sol#L32-L33)  

**Fix:**<br>
The fix has been implemented in the following commit:  
https://github.com/PartyDAO/party-protocol/pull/240/commits/15812f5d037c88f850ae24fdd7b10d739770b62a  

The fix is in line with the recommendation:  
* the unstructured storage pattern for the `zoraAuctionModuleApproved` variable has been adopted.  
* this variable is now set to `true` after granting approval for the first time.  




[high]: https://img.shields.io/badge/-HIGH-b02319 "HIGH"
[medium]: https://img.shields.io/badge/-MEDIUM-orange "MEDIUM"
[low]: https://img.shields.io/badge/-LOW-FFD700 "LOW"
[improvement]: https://img.shields.io/badge/-IMPROVEMENT-darkgreen "IMPROVEMENT"
[fixed]: https://img.shields.io/badge/-FIXED-brightgreen "FIXED"
[acknowledged]: https://img.shields.io/badge/-ACKNOWLEDGED-blue "ACKNOWLEDGED"
[disputed]: https://img.shields.io/badge/-DISPUTED-lightgrey "DISPUTED"
[reported]: https://img.shields.io/badge/-REPORTED-lightblue "REPORTED"