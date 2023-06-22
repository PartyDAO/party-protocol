// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../contracts/crowdfund/Crowdfund.sol";

contract TestableCrowdfund is Crowdfund {
    uint256 public finalPrice;
    CrowdfundLifecycle public lifeCycle;
    FixedGovernanceOpts public govOpts;

    constructor(IGlobals globals) Crowdfund(globals) {}

    function initialize(CrowdfundOptions memory opts) external payable {
        lifeCycle = CrowdfundLifecycle.Active;
        govOpts = opts.governanceOpts;
        _initialize(opts);
    }

    function getContributionEntriesByContributorCount(
        address contributor
    ) external view returns (uint256) {
        return _contributionsByContributor[contributor].length;
    }

    function testSetFinalPrice(uint256 finalPrice_) external {
        finalPrice = finalPrice_;
    }

    function testSetLifeCycle(CrowdfundLifecycle lc) external {
        lifeCycle = lc;
    }

    function getFixedGovernanceOpts() external view returns (FixedGovernanceOpts memory) {
        return govOpts;
    }

    function testCreateParty(
        FixedGovernanceOpts memory govOpts_,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external returns (Party party) {
        return _createParty(govOpts_, proposalEngineOpts, false, preciousTokens, preciousTokenIds);
    }

    function testSetWon(
        uint256 finalPrice_,
        FixedGovernanceOpts memory govOpts_,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external returns (Party party) {
        finalPrice = finalPrice_;
        lifeCycle = CrowdfundLifecycle.Won;
        return _createParty(govOpts_, proposalEngineOpts, false, preciousTokens, preciousTokenIds);
    }

    function getCrowdfundLifecycle() public view virtual override returns (CrowdfundLifecycle) {
        return lifeCycle;
    }

    function _getFinalPrice() internal view virtual override returns (uint256) {
        return finalPrice;
    }

    function hashOpts(
        FixedGovernanceOpts memory _govOpts,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts
    ) public pure returns (bytes32 h) {
        return _hashOpts(_govOpts, proposalEngineOpts);
    }
}
