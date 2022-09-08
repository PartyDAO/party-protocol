// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../contracts/crowdfund/Crowdfund.sol";


contract TestableCrowdfund is Crowdfund {

    uint256 public finalPrice;
    CrowdfundLifecycle public lifeCycle = CrowdfundLifecycle.Active;
    FixedGovernanceOpts public govOpts;

    constructor(IGlobals globals, CrowdfundOptions memory opts)
        payable
        Crowdfund(globals)
    {
        _initialize(opts);
        govOpts = opts.governanceOpts;
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
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party)
    {
        return _createParty(_getPartyFactory(), govOpts_, preciousTokens, preciousTokenIds);
    }

    function testSetWon(
        uint256 finalPrice_,
        FixedGovernanceOpts memory govOpts_,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party)
    {
        finalPrice = finalPrice_;
        lifeCycle = CrowdfundLifecycle.Won;
        return _createParty(_getPartyFactory(), govOpts_, preciousTokens, preciousTokenIds);
    }

    function getCrowdfundLifecycle()
        public
        virtual
        override
        view
        returns (CrowdfundLifecycle)
    {
        return lifeCycle;
    }

    function _getFinalPrice() internal virtual override view returns (uint256) {
        return finalPrice;
    }

    function hashFixedGovernanceOpts(FixedGovernanceOpts memory opts)
        public
        pure
        returns (bytes16 h)
    {
        return _hashFixedGovernanceOpts(opts);
    }
}
