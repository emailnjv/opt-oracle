// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PolyOracleSingle} from "../../src/PolyOracleSingle.sol";
import {IPolyOracleSingle} from "../../src/interfaces/IPolyOracleSingle.sol";
import {IPolyOracleTypes} from "../../src/interfaces/IPolyOracleTypes.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFactory is Ownable2Step {
    constructor(address _admin) Ownable(_admin) {}
}

contract PolyOracleSingleTest is Test {
    PolyOracleSingle public oracle;
    MockUSDC public usdc;
    MockFactory public factory;

    address public admin = address(0x1);
    address public requester = address(0x2);
    address public proposer = address(0x3);
    address public disputer = address(0x4);
    address public voter1 = address(0x5);
    address public voter2 = address(0x6);
    address public voter3 = address(0x7);

    uint256 public constant REWARD = 100e6; // 100 USDC
    uint256 public constant BOND = 50e6; // 50 USDC
    uint32 public constant LIVENESS_PERIOD = 1 hours;
    uint32 public constant VOTING_DOMINANCE_PERIOD = 30 minutes;
    uint256 public constant ESCALATION_THRESHOLD = 100_000e6; // 100k USDC
    bytes public constant DESCRIPTION = "What is the price of ETH?";
    bytes public constant RESULT = abi.encode(3500e8);

    function setUp() public {
        usdc = new MockUSDC();
        factory = new MockFactory(admin);
        oracle = new PolyOracleSingle();

        // Fund the oracle with reward (simulating what factory would do)
        usdc.mint(address(oracle), REWARD);

        // Initialize the oracle
        oracle.initialize(
            address(usdc),
            address(factory),
            requester,
            REWARD,
            BOND,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );

        // Fund accounts
        usdc.mint(proposer, 1000e6);
        usdc.mint(disputer, 1000e6);
        usdc.mint(voter1, 10_000e6);
        usdc.mint(voter2, 10_000e6);
        usdc.mint(voter3, 10_000e6);

        // Approve oracle
        vm.prank(proposer);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(disputer);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter2);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter3);
        usdc.approve(address(oracle), type(uint256).max);
    }

    // --------------------------- Initialization Tests ---------------------------

    function test_Initialize_Success() public view {
        assertEq(oracle.usdc(), address(usdc));
        assertEq(oracle.factory(), address(factory));
        assertEq(oracle.livenessPeriod(), LIVENESS_PERIOD);
        assertEq(oracle.votingDominancePeriod(), VOTING_DOMINANCE_PERIOD);
        assertEq(oracle.escalationThreshold(), ESCALATION_THRESHOLD);

        (
            address req,
            uint256 reward,
            uint256 bondAmount,
            bytes memory desc,
            IPolyOracleTypes.RequestState state,
            uint256 createdAt
        ) = oracle.getRequest();

        assertEq(req, requester);
        assertEq(reward, REWARD);
        assertEq(bondAmount, BOND);
        assertEq(keccak256(desc), keccak256(DESCRIPTION));
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Initialized));
        assertTrue(createdAt > 0);
    }

    function test_Initialize_RevertAlreadyInitialized() public {
        vm.expectRevert(IPolyOracleTypes.AlreadyInitialized.selector);
        oracle.initialize(
            address(usdc),
            address(factory),
            requester,
            REWARD,
            BOND,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    function test_Initialize_RevertZeroUsdc() public {
        PolyOracleSingle newOracle = new PolyOracleSingle();
        vm.expectRevert(IPolyOracleTypes.ZeroAddress.selector);
        newOracle.initialize(
            address(0),
            address(factory),
            requester,
            REWARD,
            BOND,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    function test_Initialize_RevertZeroFactory() public {
        PolyOracleSingle newOracle = new PolyOracleSingle();
        vm.expectRevert(IPolyOracleTypes.ZeroAddress.selector);
        newOracle.initialize(
            address(usdc),
            address(0),
            requester,
            REWARD,
            BOND,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    function test_Initialize_RevertZeroRequester() public {
        PolyOracleSingle newOracle = new PolyOracleSingle();
        vm.expectRevert(IPolyOracleTypes.ZeroAddress.selector);
        newOracle.initialize(
            address(usdc),
            address(factory),
            address(0),
            REWARD,
            BOND,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    function test_Initialize_RevertZeroReward() public {
        PolyOracleSingle newOracle = new PolyOracleSingle();
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        newOracle.initialize(
            address(usdc),
            address(factory),
            requester,
            0,
            BOND,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    function test_Initialize_RevertZeroBond() public {
        PolyOracleSingle newOracle = new PolyOracleSingle();
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        newOracle.initialize(
            address(usdc),
            address(factory),
            requester,
            REWARD,
            0,
            DESCRIPTION,
            LIVENESS_PERIOD,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    function test_Initialize_RevertInvalidConfig() public {
        PolyOracleSingle newOracle = new PolyOracleSingle();
        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        newOracle.initialize(
            address(usdc),
            address(factory),
            requester,
            REWARD,
            BOND,
            DESCRIPTION,
            0,
            VOTING_DOMINANCE_PERIOD,
            ESCALATION_THRESHOLD
        );
    }

    // --------------------------- Proposal Tests ---------------------------

    function test_Propose_Success() public {
        vm.prank(proposer);
        oracle.propose(RESULT);

        (address prop, bytes memory result, uint256 proposedAt, uint256 livenessEndsAt) = oracle.getProposal();

        assertEq(prop, proposer);
        assertEq(keccak256(result), keccak256(RESULT));
        assertEq(proposedAt, block.timestamp);
        assertEq(livenessEndsAt, block.timestamp + oracle.livenessPeriod());

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest();
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Proposed));
    }

    function test_Propose_TransfersBond() public {
        uint256 balanceBefore = usdc.balanceOf(proposer);

        vm.prank(proposer);
        oracle.propose(RESULT);

        assertEq(usdc.balanceOf(proposer), balanceBefore - BOND);
    }

    function test_Propose_RevertInvalidState() public {
        vm.prank(proposer);
        oracle.propose(RESULT);

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidStateSingle.selector,
                IPolyOracleTypes.RequestState.Proposed,
                IPolyOracleTypes.RequestState.Initialized
            )
        );
        oracle.propose(RESULT);
    }

    // --------------------------- Dispute Tests ---------------------------

    function test_Dispute_Success() public {
        _propose();

        vm.prank(disputer);
        oracle.dispute();

        (address disp, uint256 disputedAt,,,,, IPolyOracleTypes.DisputeOutcome outcome) = oracle.getDispute();

        assertEq(disp, disputer);
        assertEq(disputedAt, block.timestamp);
        assertEq(uint256(outcome), uint256(IPolyOracleTypes.DisputeOutcome.None));

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest();
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Disputed));
    }

    function test_Dispute_TransfersBond() public {
        _propose();
        uint256 balanceBefore = usdc.balanceOf(disputer);

        vm.prank(disputer);
        oracle.dispute();

        assertEq(usdc.balanceOf(disputer), balanceBefore - BOND);
    }

    function test_Dispute_RevertAfterLiveness() public {
        _propose();

        vm.warp(block.timestamp + oracle.livenessPeriod() + 1);

        vm.prank(disputer);
        vm.expectRevert(IPolyOracleTypes.LivenessPeriodEndedSingle.selector);
        oracle.dispute();
    }

    function test_Dispute_RevertInvalidState() public {
        vm.prank(disputer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidStateSingle.selector,
                IPolyOracleTypes.RequestState.Initialized,
                IPolyOracleTypes.RequestState.Proposed
            )
        );
        oracle.dispute();
    }

    // --------------------------- Voting Tests ---------------------------

    function test_Vote_ForProposer() public {
        _proposeAndDispute();
        uint256 stakeAmount = 1000e6;

        vm.prank(voter1);
        oracle.vote(true, stakeAmount);

        (,, uint256 proposerStake, uint256 disputerStake,,,) = oracle.getDispute();
        assertEq(proposerStake, stakeAmount);
        assertEq(disputerStake, 0);

        (uint256 voterProposerStake, uint256 voterDisputerStake, bool claimed) = oracle.getVoterStake(voter1);
        assertEq(voterProposerStake, stakeAmount);
        assertEq(voterDisputerStake, 0);
        assertFalse(claimed);
    }

    function test_Vote_ForDisputer() public {
        _proposeAndDispute();
        uint256 stakeAmount = 1000e6;

        vm.prank(voter1);
        oracle.vote(false, stakeAmount);

        (,, uint256 proposerStake, uint256 disputerStake,,,) = oracle.getDispute();
        assertEq(proposerStake, 0);
        assertEq(disputerStake, stakeAmount);
    }

    function test_Vote_MultipleVoters() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 1000e6);

        vm.prank(voter2);
        oracle.vote(false, 500e6);

        vm.prank(voter3);
        oracle.vote(true, 2000e6);

        (,, uint256 proposerStake, uint256 disputerStake,,,) = oracle.getDispute();
        assertEq(proposerStake, 3000e6);
        assertEq(disputerStake, 500e6);
    }

    function test_Vote_TracksDominance() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        (,,,, uint256 dominanceStartedAt, bool proposerWasDominant,) = oracle.getDispute();
        assertTrue(dominanceStartedAt > 0);
        assertTrue(proposerWasDominant);
    }

    function test_Vote_TriggersEscalation() public {
        _proposeAndDispute();

        uint256 threshold = oracle.escalationThreshold();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);

        vm.prank(voter1);
        oracle.vote(true, threshold);

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest();
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Escalated));
    }

    function test_Vote_RevertZeroAmount() public {
        _proposeAndDispute();

        vm.prank(voter1);
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        oracle.vote(true, 0);
    }

    function test_Vote_RevertInvalidState() public {
        _propose();

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidStateSingle.selector,
                IPolyOracleTypes.RequestState.Proposed,
                IPolyOracleTypes.RequestState.Disputed
            )
        );
        oracle.vote(true, 1000e6);
    }

    // --------------------------- Resolution Tests ---------------------------

    function test_ResolveUndisputed_Success() public {
        _propose();

        vm.warp(block.timestamp + oracle.livenessPeriod() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        oracle.resolveUndisputed();

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest();
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Resolved));

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND);

        bytes memory result = oracle.getResult();
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_ResolveUndisputed_RevertBeforeLiveness() public {
        _propose();

        (,,, uint256 livenessEndsAt) = oracle.getProposal();

        vm.expectRevert(abi.encodeWithSelector(IPolyOracleTypes.LivenessPeriodNotEndedSingle.selector, livenessEndsAt));
        oracle.resolveUndisputed();
    }

    function test_ResolveDispute_ProposerWins() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        oracle.resolveDispute();

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest();
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Resolved));

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);

        (,,,,,, IPolyOracleTypes.DisputeOutcome outcome) = oracle.getDispute();
        assertEq(uint256(outcome), uint256(IPolyOracleTypes.DisputeOutcome.ProposerWins));
    }

    function test_ResolveDispute_DisputerWins() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 1000e6);

        vm.prank(voter2);
        oracle.vote(false, 3000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);

        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);

        oracle.resolveDispute();

        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + REWARD + BOND * 2);

        (,,,,,, IPolyOracleTypes.DisputeOutcome outcome) = oracle.getDispute();
        assertEq(uint256(outcome), uint256(IPolyOracleTypes.DisputeOutcome.DisputerWins));
    }

    function test_ResolveDispute_RevertNoDominance() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 1000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);

        vm.expectRevert(IPolyOracleTypes.NoDominanceSingle.selector);
        oracle.resolveDispute();
    }

    function test_ResolveDispute_RevertDominancePeriodNotMet() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.expectRevert(IPolyOracleTypes.DominancePeriodNotMetSingle.selector);
        oracle.resolveDispute();
    }

    function test_AdminResolve_ProposerWins() public {
        _proposeAndDispute();

        uint256 threshold = oracle.escalationThreshold();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(true, threshold);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        vm.prank(admin);
        oracle.adminResolve(true, RESULT);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);
    }

    function test_AdminResolve_DisputerWins() public {
        _proposeAndDispute();

        uint256 threshold = oracle.escalationThreshold();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(true, threshold);

        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);

        vm.prank(admin);
        oracle.adminResolve(false, "");

        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + REWARD + BOND * 2);
    }

    function test_AdminResolve_RevertNotFactoryAdmin() public {
        _proposeAndDispute();

        uint256 threshold = oracle.escalationThreshold();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(true, threshold);

        vm.prank(requester);
        vm.expectRevert(IPolyOracleTypes.Unauthorized.selector);
        oracle.adminResolve(true, RESULT);
    }

    function test_AdminResolve_RevertNotEscalated() public {
        _proposeAndDispute();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidStateSingle.selector,
                IPolyOracleTypes.RequestState.Disputed,
                IPolyOracleTypes.RequestState.Escalated
            )
        );
        oracle.adminResolve(true, RESULT);
    }

    // --------------------------- Claim Tests ---------------------------

    function test_ClaimWinnings_ProposerWinsVoterClaims() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);
        oracle.resolveDispute();

        uint256 voter1BalanceBefore = usdc.balanceOf(voter1);

        vm.prank(voter1);
        oracle.claimWinnings();

        uint256 expectedPayout = 3000e6 + 1000e6;
        assertEq(usdc.balanceOf(voter1), voter1BalanceBefore + expectedPayout);
    }

    function test_ClaimWinnings_DisputerWinsVoterClaims() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 1000e6);

        vm.prank(voter2);
        oracle.vote(false, 3000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);
        oracle.resolveDispute();

        uint256 voter2BalanceBefore = usdc.balanceOf(voter2);

        vm.prank(voter2);
        oracle.claimWinnings();

        uint256 expectedPayout = 3000e6 + 1000e6;
        assertEq(usdc.balanceOf(voter2), voter2BalanceBefore + expectedPayout);
    }

    function test_ClaimWinnings_RevertAlreadyClaimed() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);
        oracle.resolveDispute();

        vm.prank(voter1);
        oracle.claimWinnings();

        vm.prank(voter1);
        vm.expectRevert(IPolyOracleTypes.AlreadyClaimed.selector);
        oracle.claimWinnings();
    }

    function test_ClaimWinnings_RevertNothingToClaim() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);
        oracle.resolveDispute();

        vm.prank(voter2);
        vm.expectRevert(IPolyOracleTypes.NothingToClaim.selector);
        oracle.claimWinnings();
    }

    function test_ClaimWinnings_RevertNotResolved() public {
        _proposeAndDispute();

        vm.prank(voter1);
        oracle.vote(true, 1000e6);

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidStateSingle.selector,
                IPolyOracleTypes.RequestState.Disputed,
                IPolyOracleTypes.RequestState.Resolved
            )
        );
        oracle.claimWinnings();
    }

    // --------------------------- View Function Tests ---------------------------

    function test_GetResult_Success() public {
        _propose();
        vm.warp(block.timestamp + oracle.livenessPeriod() + 1);
        oracle.resolveUndisputed();

        bytes memory result = oracle.getResult();
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_GetResult_RevertNotResolved() public {
        _propose();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidStateSingle.selector,
                IPolyOracleTypes.RequestState.Proposed,
                IPolyOracleTypes.RequestState.Resolved
            )
        );
        oracle.getResult();
    }

    function test_CanResolveDispute() public {
        _proposeAndDispute();

        (bool canResolve1, string memory reason1) = oracle.canResolveDispute();
        assertFalse(canResolve1);
        assertEq(reason1, "No side has 2x dominance");

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        (bool canResolve2, string memory reason2) = oracle.canResolveDispute();
        assertFalse(canResolve2);
        assertEq(reason2, "Dominance period not met");

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);

        (bool canResolve3, string memory reason3) = oracle.canResolveDispute();
        assertTrue(canResolve3);
        assertEq(reason3, "Can resolve");
    }

    // --------------------------- Integration Tests ---------------------------

    function test_FullLifecycle_NoDispute() public {
        vm.prank(proposer);
        oracle.propose(RESULT);

        vm.warp(block.timestamp + oracle.livenessPeriod() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        oracle.resolveUndisputed();

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND);
        bytes memory result = oracle.getResult();
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_FullLifecycle_DisputeProposerWins() public {
        vm.prank(proposer);
        oracle.propose(RESULT);

        vm.prank(disputer);
        oracle.dispute();

        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        vm.warp(block.timestamp + oracle.votingDominancePeriod() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        oracle.resolveDispute();

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);

        vm.prank(voter1);
        oracle.claimWinnings();

        vm.prank(voter2);
        vm.expectRevert(IPolyOracleTypes.NothingToClaim.selector);
        oracle.claimWinnings();
    }

    function test_FullLifecycle_Escalation() public {
        vm.prank(proposer);
        oracle.propose(RESULT);

        vm.prank(disputer);
        oracle.dispute();

        uint256 threshold = oracle.escalationThreshold();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(true, threshold);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        vm.prank(admin);
        oracle.adminResolve(true, RESULT);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);
    }

    // --------------------------- Helper Functions ---------------------------

    function _propose() internal {
        vm.prank(proposer);
        oracle.propose(RESULT);
    }

    function _proposeAndDispute() internal {
        _propose();
        vm.prank(disputer);
        oracle.dispute();
    }
}
