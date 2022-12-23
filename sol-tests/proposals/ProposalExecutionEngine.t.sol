// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/tokens/IERC721.sol";

import "../TestUtils.sol";

import "./TestableProposalExecutionEngine.sol";
import "./DummyProposalEngineImpl.sol";

contract ProposalExecutionEngineTest is Test, TestUtils {
    // From TestableProposalExecutionEngine
    event TestEcho(uint256 indexed v);
    // From DummyProposalEngineImpl
    event TestInitializeCalled(address oldImpl, bytes32 initDataHash);

    TestableProposalExecutionEngine eng;
    DummyProposalEngineImpl newEngImpl;
    Globals globals;

    constructor() {}

    function setUp() public {
        newEngImpl = new DummyProposalEngineImpl();
        globals = new Globals(address(this));
        globals.setAddress(
            LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL,
            // We will test upgrades to this impl.
            address(newEngImpl)
        );
        eng = new TestableProposalExecutionEngine(
            globals,
            IOpenseaExchange(_randomAddress()),
            IOpenseaConduitController(_randomAddress()),
            IZoraAuctionHouse(_randomAddress()),
            IFractionalV1VaultFactory(_randomAddress())
        );
    }

    function _createTestProposal(
        bytes memory proposalData
    ) private view returns (IProposalExecutionEngine.ExecuteProposalParams memory executeParams) {
        executeParams = IProposalExecutionEngine.ExecuteProposalParams({
            proposalId: _randomUint256(),
            proposalData: proposalData,
            progressData: "",
            extraData: "",
            flags: 0,
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0)
        });
    }

    function _createTwoStepProposalData(
        uint256 emitValue1,
        uint256 emitValue2
    ) private pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnOpensea)),
                emitValue1,
                emitValue2
            );
    }

    function _createOneStepProposalData(uint256 emitValue) private pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnZora)),
                emitValue
            );
    }

    function _createUpgradeProposalData(
        address expectedEngineImpl,
        bytes memory initData
    ) private pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.UpgradeProposalEngineImpl)),
                expectedEngineImpl,
                initData
            );
    }

    function test_executeProposal_rejectsBadProgressData() public {
        // This is a two-step proposal. We will execute the first step
        // then execute again with progressData that does not match
        // the progressData for the next step.
        (uint256 emitValue1, uint256 emitValue2) = (_randomUint256(), _randomUint256());
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createTwoStepProposalData(emitValue1, emitValue2)
        );
        vm.expectEmit(true, false, false, false, address(eng));
        emit TestEcho(emitValue1);
        assertFalse(_executeProposal(executeParams));
        // Use bad progressData for the next step.
        executeParams.progressData = abi.encode("poop");
        vm.expectRevert(
            abi.encodeWithSelector(
                ProposalExecutionEngine.ProposalProgressDataInvalidError.selector,
                keccak256(executeParams.progressData),
                keccak256(eng.t_nextProgressData())
            )
        );
        _executeProposal(executeParams);
    }

    function test_executeProposal_onlyOneProposalAtATime() public {
        // Start a two-step proposal then try to execute a different one-step
        // proposal, which should fail.
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createTwoStepProposalData(_randomUint256(), _randomUint256())
        );
        assertFalse(_executeProposal(executeParams));
        // Execute a different proposal while the first one is incomplete.
        executeParams = _createTestProposal(_createOneStepProposalData(_randomUint256()));
        vm.expectRevert(
            abi.encodeWithSelector(
                ProposalExecutionEngine.ProposalExecutionBlockedError.selector,
                executeParams.proposalId,
                eng.getCurrentInProgressProposalId()
            )
        );
        _executeProposal(executeParams);
    }

    function test_executeProposal_twoStepWorks() public {
        (uint256 emitValue1, uint256 emitValue2) = (_randomUint256(), _randomUint256());
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createTwoStepProposalData(emitValue1, emitValue2)
        );
        vm.expectEmit(true, false, false, false, address(eng));
        emit TestEcho(emitValue1);
        assertFalse(_executeProposal(executeParams));
        // Update the progressData for the next step.
        // Normally this would be captured from event logs, but we don't
        // have access to logs so the test contract surfaces it through a
        // public variable.
        executeParams.progressData = eng.t_nextProgressData();
        vm.expectEmit(true, false, false, false, address(eng));
        emit TestEcho(emitValue2);
        assertTrue(_executeProposal(executeParams));
    }

    function test_executeProposal_oneStepWorks() public {
        uint256 emitValue = _randomUint256();
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createOneStepProposalData(emitValue)
        );
        vm.expectEmit(true, false, false, false, address(eng));
        emit TestEcho(emitValue);
        assertTrue(_executeProposal(executeParams));
    }

    function test_executeProposal_upgradeImplementationWorks() public {
        bytes memory initData = abi.encode("yooo");
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createUpgradeProposalData(address(newEngImpl), initData)
        );
        vm.expectEmit(true, false, false, false, address(eng));
        emit TestInitializeCalled(address(eng), keccak256(initData));
        assertTrue(_executeProposal(executeParams));
        assertEq(address(eng.getProposalEngineImpl()), address(newEngImpl));
    }

    function test_executeProposal_upgradeImplementationFailsIfExpectedEngineIsNotActual() public {
        bytes memory initData = abi.encode("yooo");
        address expectedEngImpl = _randomAddress();
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createUpgradeProposalData(expectedEngImpl, initData)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ProposalExecutionEngine.UnexpectedProposalEngineImplementationError.selector,
                address(newEngImpl),
                expectedEngImpl
            )
        );
        _executeProposal(executeParams);
    }

    // Execute a two-step proposal, then try to cancel a different one.
    function test_cancelProposal_cannotCancelNonCurrentProposal() public {
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams = _createTestProposal(
            _createTwoStepProposalData(_randomUint256(), _randomUint256())
        );
        assertFalse(_executeProposal(executeParams));
        uint256 otherProposalId = _randomUint256();
        vm.expectRevert(
            abi.encodeWithSelector(
                ProposalExecutionEngine.ProposalNotInProgressError.selector,
                otherProposalId
            )
        );
        eng.cancelProposal(otherProposalId);
    }

    // Execute a two-step proposal, cancel it, then execute another one-step proposal.
    function test_cancelProposal_works() public {
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams1 = _createTestProposal(
            _createTwoStepProposalData(_randomUint256(), _randomUint256())
        );
        assertFalse(_executeProposal(executeParams1));
        assertTrue(eng.getCurrentInProgressProposalId() != 0);
        assertTrue(eng.getNextProgressDataHash() != 0);
        eng.cancelProposal(executeParams1.proposalId);
        assertEq(eng.getCurrentInProgressProposalId(), 0);
        assertEq(eng.getNextProgressDataHash(), 0);
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams2 = _createTestProposal(
            _createOneStepProposalData(_randomUint256())
        );
        assertTrue(_executeProposal(executeParams2));
        assertEq(eng.getCurrentInProgressProposalId(), 0);
        assertEq(eng.getNextProgressDataHash(), 0);
    }

    function _executeProposal(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) private returns (bool completed) {
        return eng.executeProposal(params).length == 0;
    }
}
