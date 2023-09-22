# Audit Report - PartyDAO
|                |                                                                           |
| -------------- | ------------------------------------------------------------------------- |
| **Audit Date** | 09/13/2023 - 09/14/2023                                                   |
| **Auditor**    | HollaDieWaldfee ([@HollaWaldfee100](https://twitter.com/HollaWaldfee100)) |
| **Version 1**  | 09/14/2023 Initial Report                                                 |
| **Version 2**  | 09/20/2023 Mitigation Review                                              |

# Contents
- [Audit Report - PartyDAO](#audit-report---partydao)
- [Contents](#contents)
- [Disclaimer](#disclaimer)
- [About HollaDieWaldfee](#about-holladiewaldfee)
- [Scope](#scope)
- [Severity Classification](#severity-classification)
- [Summary](#summary)
- [Findings](#findings)
  - [High Risk Findings (1)](#high-risk-findings-1)
    - [1. Excess `ETH` is lost when `maxTotalContributions` is reached  ](#1-excess-eth-is-lost-when-maxtotalcontributions-is-reached--)
  - [Medium Risk Findings (2)](#medium-risk-findings-2)
    - [2. `OWNER` can change `feePerMint` at any time to any value  ](#2-owner-can-change-feepermint-at-any-time-to-any-value--)
    - [3. `gateKeeper` checks rely on `msg.sender`  ](#3-gatekeeper-checks-rely-on-msgsender--)
  - [Low Risk Findings (1)](#low-risk-findings-1)
    - [4. User making contribution to himself through `ContributionRouter` cannot set `delegate`  ](#4-user-making-contribution-to-himself-through-contributionrouter-cannot-set-delegate--)

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
https://github.com/PartyDAO/party-protocol/pull/282

Specifically, the Pull Request adds the `ContributionRouter` contract to the protocol which allows to charge a fee for crowdfund contributions.  

The commit for the initial audit is _9b5f379c86ee6a02644cc8e5986a41eca655109d_ and the commit for the mitigation review is _2c36c3ffd0b0d14668fed7524b604d3a231541c0_.  

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
| ![medium]      | 2     | 1     | 1            | 0        | 0        |
| ![low]         | 1     | 0     | 1            | 0        | 0        |
| ![improvement] | 0     | 0     | 0            | 0        | 0        |

| #   | Title                                                                                                                                                                             | Severity  | Status          |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | --------------- |
| 1   | [Excess `ETH` is lost when `maxTotalContributions` is reached](#1-excess-eth-is-lost-when-maxtotalcontributions-is-reached--)                                                     | ![high]   | ![fixed]        |
| 2   | [`OWNER` can change `feePerMint` at any time to any value](#2-owner-can-change-feepermint-at-any-time-to-any-value--)                                                             | ![medium] | ![acknowledged] |
| 3   | [`gateKeeper` checks rely on `msg.sender`](#3-gatekeeper-checks-rely-on-msgsender--)                                                                                              | ![medium] | ![fixed]        |
| 4   | [User making contribution on himself through `ContributionRouter` cannot set `delegate`](#4-user-making-contribution-to-himself-through-contributionrouter-cannot-set-delegate--) | ![low]    | ![acknowledged] |


# Findings
## High Risk Findings (1)
### 1. Excess `ETH` is lost when `maxTotalContributions` is reached ![high] ![fixed]
**Description:**<br>
It is not possible to know before making a contribution how much `ETH` the crowdfund can actually accept.  

Both the `InitialETHCrowdfund` and `ReraiseETHCrowdfund` downstream call `ETHCrowdfundBase._processContribution` which makes a refund to `msg.sender` if `maxTotalContributions` is exceeded ([Link](https://github.com/PartyDAO/party-protocol/blob/9b5f379c86ee6a02644cc8e5986a41eca655109d/contracts/crowdfund/ETHCrowdfundBase.sol#L228-L241)).  

The refund is then sent back to the `ContributionRouter` where the `fallback` function is executed again with empty calldata.  

Thereby `msg.value - feeAmount` is sent to `address(0)` ([Link](https://github.com/PartyDAO/party-protocol/blob/9b5f379c86ee6a02644cc8e5986a41eca655109d/contracts/crowdfund/ContributionRouter.sol#L70)).  

In the context of this issue it's important to bring up another problem in the `ETHCrowdfundBase` contract which is not explicitly in scope of the current audit.  

If a contribution is made via `batchContributeFor` (in `InitialETHCrowdfund` or `ReraiseETHCrowdfund`) by a user directly, even without the `ContributionRouter`, the crowdfund contract will `call` itself ([Link](https://github.com/PartyDAO/party-protocol/blob/9b5f379c86ee6a02644cc8e5986a41eca655109d/contracts/crowdfund/InitialETHCrowdfund.sol#L263)). So `msg.sender` is actually the crowdfund contract. The crowdfund contract reverts when `ETH` is sent to it with empty calldata. This behavior leads to unexpected reverts and the `batchContributeFor` function cannot be used when a contribution would make `totalContributions` exceed `maxTotalContributions`.  

**Impact:**<br>
This case can be triggered by accident or intentionially by an attacker (by front-running the user and moving the total contribution closer to `maxTotalContributions`).  

The attacker would not profit from this attack but there is no way to recover the funds.  
Together with the ease of the attack, this issue is of "High" severity.  

**Recommendation:**<br>
As explained above, there are actually two issues that need to be addressed.  

It's possible to implement a `receive` function that always reverts in the `ContributionRouter`.  

Thereby a contribution that triggers a refund to the `ContributionRouter` would fail.  

This still leaves a small griefing concern. A user that wants to exactly match `maxTotalContributions` could be front-run by a tiny contribution.  
I consider the risk of this acceptable.  

What remains though is the issue that if a contribution is made through `InitialETHCrowdfund.batchContributeFor` or `ReraiseETHCrowdfund.batchContributeFor`, `msg.sender` points to the crowdfund itself, not the `ContributionRouter` or the user which leads to unexpected reverts.  

This is an architectural problem of the crowdfund contracts, not the `ContributionRouter`. How to fix this also depends on how issues 3 and 4 will be addressed.  

**Mitigation Review:**<br>
This issue has been fixed by implementing two different mitigations.  

Firstly, the `ContributionRouter` now implements a `receive` function which always reverts ([Link](https://github.com/PartyDAO/party-protocol/blob/2c36c3ffd0b0d14668fed7524b604d3a231541c0/contracts/crowdfund/ContributionRouter.sol#L94-L96)). Therefore a refund triggers the revert and there's no loss of funds anymore.  

The second problem that `batchContributorFor` will cause the wrong `msg.sender` to be passed on has been addressed by refactoring the `batchContributeFor` functions in the `InitialETHCrowdfund` ([Link](https://github.com/PartyDAO/party-protocol/blob/2c36c3ffd0b0d14668fed7524b604d3a231541c0/contracts/crowdfund/InitialETHCrowdfund.sol#L253-L271)), `ReraiseETHCrowdfund` ([Link]()) and `Crowdfund` ([Link](https://github.com/PartyDAO/party-protocol/blob/2c36c3ffd0b0d14668fed7524b604d3a231541c0/contracts/crowdfund/Crowdfund.sol#L370-L392)) contracts.  

They now make use of internal calls which means that `msg.sender` does not change and remains the original caller of the crowdfund.  

## Medium Risk Findings (2)
### 2. `OWNER` can change `feePerMint` at any time to any value ![medium] ![acknowledged]
**Description:**<br>
The fee that the `ContributionRouter` charges is determined by the `feePerMint` variable and can be set by the `OWNER` at any time to any value via the `setFeePerMint` function ([Link](https://github.com/PartyDAO/party-protocol/blob/9b5f379c86ee6a02644cc8e5986a41eca655109d/contracts/crowdfund/ContributionRouter.sol#L36-L40)).  

This means that the user cannot be sure at the time of using the `ContributionRouter` what the fee amount is that will be charged.  

**Impact:**<br>
The `OWNER` can either intentionally front-run the user and charge a higher fee on purpose which introduces a centralization risk or it might just happen by accident that a user uses the `ContributionRouter` at a time when the fee is increased.  

**Recommendation:**<br>
Use a timelock for setting `feePerMint`.  
A reasonable value would be one day.  
Thereby when a user uses the `ContributionRouter` he can be sure of the fee he has to pay.  

```diff
diff --git a/contracts/crowdfund/ContributionRouter.sol b/contracts/crowdfund/ContributionRouter.sol
index 109b9be..c70b5a9 100644
--- a/contracts/crowdfund/ContributionRouter.sol
+++ b/contracts/crowdfund/ContributionRouter.sol
@@ -20,10 +20,13 @@ contract ContributionRouter {
 
     /// @notice The amount of fees to pay to the DAO per mint.
     uint96 public feePerMint;
+    uint96 public pendingFeePerMint;
+    uint48 public timestampPendingFeePerMint;
 
     constructor(address owner, uint96 initialFeePerMint) {
         OWNER = owner;
         feePerMint = initialFeePerMint;
+        pendingFeePerMint = initialFeePerMint;
     }
 
     modifier onlyOwner() {
@@ -33,10 +36,17 @@ contract ContributionRouter {
 
     /// @notice Set the fee per mint. Only the owner can call.
     /// @param newFeePerMint The new amount to set fee per mint to.
-    function setFeePerMint(uint96 newFeePerMint) external onlyOwner {
-        emit FeePerMintUpdated(feePerMint, newFeePerMint);
+    function setPendingFeePerMint(uint96 newPendingFeePerMint) external onlyOwner {
+        pendingFeePerMint = newPendingFeePerMint;
+        timestampPendingFeePerMint = uint48(block.timestamp);
+    }
 
-        feePerMint = newFeePerMint;
+    function setFeePerMint() external {
+        if (timestampPendingFeePerMint + 1 days < block.timestamp) {
+            uint96 _pendingFeePerMint = pendingFeePerMint;
+            emit FeePerMintUpdated(feePerMint, _pendingFeePerMint);
+            feePerMint = _pendingFeePerMint;
+        }
     }
 
     /// @notice Claim fees from the contract. Only the owner can call.
```

**Mitigation Review<br>**
This finding has been acknowledged.  
The `OWNER` must be trusted to not suddenly increase the `feePerMint`.  


### 3. `gateKeeper` checks rely on `msg.sender` ![medium] ![fixed]
**Description:**<br>
This is essentially the same issue that I reported in a previous audit ([Link](https://github.com/code-423n4/2023-04-party-findings/issues/6)) and can now be applied to a new situation.  

The `gateKeeper` uses `msg.sender` for its check which is not the address of the user but the address of the `ContributionRouter`.  

This is a known issue ([Link](https://github.com/code-423n4/2023-04-party-findings/issues/6#issuecomment-1512009109)) which has not been fixed yet.  

**Impact:**<br>
The `gateKeeper` checks the wrong address which means that a user that should not be able to make contributions might be able to make contributions and vice versa (depending on how exactly the `gateKeeper` is set up).  

**Recommendation:**<br>
Fixing this issue requires changes to components that are outside the scope of the current audit.  
As this has not been fixed previously it is fair to assume that there won't be a fix this time.  
Still I want to make it clear that there is this new instance of the issue.  

**Mitigation Review:**<br>
There are two different aspects to this fix.  

One is that the `batchContributeFor` functions now make internal calls such that `msg.sender` is always the caller of the crowdfund contract.  

In addition, the gatekeepr contracts (`AllowListGatekeeper` and `TokenGateKeeper`) now check whether the crowdfund was called by the `ContributionRouter` and in this case fetch the recent `caller` from `ContributionRouter`.  

In between the `ContributionRouter` calling the crowdfund and the `GateKeeper` doing its check, there are no external calls which ensures that the `caller` cannot be changed via reentrancy to potentially mess with the `GateKeeper` check.  

## Low Risk Findings (1)
### 4. User making contribution to himself through `ContributionRouter` cannot set `delegate` ![low] ![acknowledged]
**Description:**<br>
For all crowdfunds the `delegate` of a `contributor` can only be updated from a non-zero value by the `contributor` himself.  

This is ensured by checking whether `msg.sender == contributor` in `Crowdfund._setDelegate` ([Link](https://github.com/PartyDAO/party-protocol/blob/9b5f379c86ee6a02644cc8e5986a41eca655109d/contracts/crowdfund/Crowdfund.sol#L609-L621)) and `ETHCrowdfundBase._processContribution` ([Link](https://github.com/PartyDAO/party-protocol/blob/9b5f379c86ee6a02644cc8e5986a41eca655109d/contracts/crowdfund/ETHCrowdfundBase.sol#L201-L207)).  

**Impact:**<br>
A user making a contribution through the `ContributionRouter` on behalf of himself might assume that he updates his `delegate` if he doesn't fully understand the intricacies of the actual code that is being executed.  

I consider this a user error since, as opposed to issue 3, it is not clear here that the issue lies in the contract itself and requires a code change.  

Similar to issue 1 and 3, the same problem occurs when `batchContributeFor` is called regardless of the `ContributionRouter`.  

**Recommendation:**<br>
Provide clear documentation to the users of the `ContributionRouter` that they cannot update their `delegate` from a non-zero address.  

**Mitigation Review:**<br>
This finding has been acknowledged.  
A user cannot update his `delegate` to a non-zero value if the contribution is made through the `ContributionRouter`.  

The issue has been addressed with regards to the `batchContributeFor` functions by refactoring the functions such that they now make internal calls.  

[high]: https://img.shields.io/badge/-HIGH-b02319 "HIGH"
[medium]: https://img.shields.io/badge/-MEDIUM-orange "MEDIUM"
[low]: https://img.shields.io/badge/-LOW-FFD700 "LOW"
[improvement]: https://img.shields.io/badge/-IMPROVEMENT-darkgreen "IMPROVEMENT"
[fixed]: https://img.shields.io/badge/-FIXED-brightgreen "FIXED"
[acknowledged]: https://img.shields.io/badge/-ACKNOWLEDGED-blue "ACKNOWLEDGED"
[disputed]: https://img.shields.io/badge/-DISPUTED-lightgrey "DISPUTED"
[reported]: https://img.shields.io/badge/-REPORTED-lightblue "REPORTED"