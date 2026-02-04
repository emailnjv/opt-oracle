// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PolyOracleMulti} from "../../src/PolyOracleMulti.sol";
import {IPolyOracleMulti} from "../../src/interfaces/IPolyOracleMulti.sol";
import {IPolyOracleTypes} from "../../src/interfaces/IPolyOracleTypes.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PolyOracleMultiTest is Test {
    PolyOracleMulti public oracle;
    MockUSDC public usdc;

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
        oracle =
            new PolyOracleMulti(address(usdc), admin, LIVENESS_PERIOD, VOTING_DOMINANCE_PERIOD, ESCALATION_THRESHOLD);

        // Fund accounts
        usdc.mint(requester, 1000e6);
        usdc.mint(proposer, 1000e6);
        usdc.mint(disputer, 1000e6);
        usdc.mint(voter1, 10_000e6);
        usdc.mint(voter2, 10_000e6);
        usdc.mint(voter3, 10_000e6);

        // Approve oracle
        vm.prank(requester);
        usdc.approve(address(oracle), type(uint256).max);
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

    // --------------------------- Constructor Tests ---------------------------

    function test_Constructor_SetsImmutables() public view {
        assertEq(address(oracle.USDC()), address(usdc));
        assertEq(oracle.LIVENESS_PERIOD(), LIVENESS_PERIOD);
        assertEq(oracle.VOTING_DOMINANCE_PERIOD(), VOTING_DOMINANCE_PERIOD);
        assertEq(oracle.ESCALATION_THRESHOLD(), ESCALATION_THRESHOLD);
        assertEq(oracle.owner(), admin);
    }

    function test_Constructor_RevertZeroUsdc() public {
        vm.expectRevert(IPolyOracleTypes.ZeroAddress.selector);
        new PolyOracleMulti(address(0), admin, LIVENESS_PERIOD, VOTING_DOMINANCE_PERIOD, ESCALATION_THRESHOLD);
    }

    function test_Constructor_RevertZeroAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new PolyOracleMulti(address(usdc), address(0), LIVENESS_PERIOD, VOTING_DOMINANCE_PERIOD, ESCALATION_THRESHOLD);
    }

    function test_Constructor_RevertZeroLivenessPeriod() public {
        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        new PolyOracleMulti(address(usdc), admin, 0, VOTING_DOMINANCE_PERIOD, ESCALATION_THRESHOLD);
    }

    function test_Constructor_RevertZeroVotingDominancePeriod() public {
        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        new PolyOracleMulti(address(usdc), admin, LIVENESS_PERIOD, 0, ESCALATION_THRESHOLD);
    }

    function test_Constructor_RevertZeroEscalationThreshold() public {
        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        new PolyOracleMulti(address(usdc), admin, LIVENESS_PERIOD, VOTING_DOMINANCE_PERIOD, 0);
    }

    // --------------------------- Initialization Tests ---------------------------

    function test_InitializeRequest_Success() public {
        vm.prank(requester);
        bytes32 requestId = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);

        (
            address req,
            uint256 reward,
            uint256 bondAmount,
            bytes memory desc,
            IPolyOracleTypes.RequestState state,
            uint256 createdAt
        ) = oracle.getRequest(requestId);

        assertEq(req, requester);
        assertEq(reward, REWARD);
        assertEq(bondAmount, BOND);
        assertEq(keccak256(desc), keccak256(DESCRIPTION));
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Initialized));
        assertEq(createdAt, block.timestamp);
    }

    function test_InitializeRequest_TransfersUSDC() public {
        uint256 balanceBefore = usdc.balanceOf(requester);

        vm.prank(requester);
        oracle.initializeRequest(REWARD, BOND, DESCRIPTION);

        assertEq(usdc.balanceOf(requester), balanceBefore - REWARD);
        assertEq(usdc.balanceOf(address(oracle)), REWARD);
    }

    function test_InitializeRequest_RevertZeroReward() public {
        vm.prank(requester);
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        oracle.initializeRequest(0, BOND, DESCRIPTION);
    }

    function test_InitializeRequest_RevertZeroBond() public {
        vm.prank(requester);
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        oracle.initializeRequest(REWARD, 0, DESCRIPTION);
    }

    function test_InitializeRequest_GeneratesUniqueIds() public {
        vm.startPrank(requester);
        bytes32 id1 = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);
        bytes32 id2 = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);
        vm.stopPrank();

        assertTrue(id1 != id2);
    }

    // --------------------------- Proposal Tests ---------------------------

    function test_Propose_Success() public {
        bytes32 requestId = _createRequest();

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        (address prop, bytes memory result, uint256 proposedAt, uint256 livenessEndsAt) = oracle.getProposal(requestId);

        assertEq(prop, proposer);
        assertEq(keccak256(result), keccak256(RESULT));
        assertEq(proposedAt, block.timestamp);
        assertEq(livenessEndsAt, block.timestamp + oracle.LIVENESS_PERIOD());

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest(requestId);
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Proposed));
    }

    function test_Propose_TransfersBond() public {
        bytes32 requestId = _createRequest();
        uint256 balanceBefore = usdc.balanceOf(proposer);

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        assertEq(usdc.balanceOf(proposer), balanceBefore - BOND);
    }

    function test_Propose_RevertInvalidState() public {
        bytes32 requestId = _createRequest();

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidState.selector,
                requestId,
                IPolyOracleTypes.RequestState.Proposed,
                IPolyOracleTypes.RequestState.Initialized
            )
        );
        oracle.propose(requestId, RESULT);
    }

    // --------------------------- Dispute Tests ---------------------------

    function test_Dispute_Success() public {
        bytes32 requestId = _createAndPropose();

        vm.prank(disputer);
        oracle.dispute(requestId);

        (address disp, uint256 disputedAt,,,,, IPolyOracleTypes.DisputeOutcome outcome) = oracle.getDispute(requestId);

        assertEq(disp, disputer);
        assertEq(disputedAt, block.timestamp);
        assertEq(uint256(outcome), uint256(IPolyOracleTypes.DisputeOutcome.None));

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest(requestId);
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Disputed));
    }

    function test_Dispute_TransfersBond() public {
        bytes32 requestId = _createAndPropose();
        uint256 balanceBefore = usdc.balanceOf(disputer);

        vm.prank(disputer);
        oracle.dispute(requestId);

        assertEq(usdc.balanceOf(disputer), balanceBefore - BOND);
    }

    function test_Dispute_RevertAfterLiveness() public {
        bytes32 requestId = _createAndPropose();

        vm.warp(block.timestamp + oracle.LIVENESS_PERIOD() + 1);

        vm.prank(disputer);
        vm.expectRevert(abi.encodeWithSelector(IPolyOracleTypes.LivenessPeriodEnded.selector, requestId));
        oracle.dispute(requestId);
    }

    function test_Dispute_RevertInvalidState() public {
        bytes32 requestId = _createRequest();

        vm.prank(disputer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidState.selector,
                requestId,
                IPolyOracleTypes.RequestState.Initialized,
                IPolyOracleTypes.RequestState.Proposed
            )
        );
        oracle.dispute(requestId);
    }

    // --------------------------- Voting Tests ---------------------------

    function test_Vote_ForProposer() public {
        bytes32 requestId = _createProposeAndDispute();
        uint256 stakeAmount = 1000e6;

        vm.prank(voter1);
        oracle.vote(requestId, true, stakeAmount);

        (,, uint256 proposerStake, uint256 disputerStake,,,) = oracle.getDispute(requestId);
        assertEq(proposerStake, stakeAmount);
        assertEq(disputerStake, 0);

        (uint256 voterProposerStake, uint256 voterDisputerStake, bool claimed) = oracle.getVoterStake(requestId, voter1);
        assertEq(voterProposerStake, stakeAmount);
        assertEq(voterDisputerStake, 0);
        assertFalse(claimed);
    }

    function test_Vote_ForDisputer() public {
        bytes32 requestId = _createProposeAndDispute();
        uint256 stakeAmount = 1000e6;

        vm.prank(voter1);
        oracle.vote(requestId, false, stakeAmount);

        (,, uint256 proposerStake, uint256 disputerStake,,,) = oracle.getDispute(requestId);
        assertEq(proposerStake, 0);
        assertEq(disputerStake, stakeAmount);
    }

    function test_Vote_MultipleVoters() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 500e6);

        vm.prank(voter3);
        oracle.vote(requestId, true, 2000e6);

        (,, uint256 proposerStake, uint256 disputerStake,,,) = oracle.getDispute(requestId);
        assertEq(proposerStake, 3000e6);
        assertEq(disputerStake, 500e6);
    }

    function test_Vote_TracksDominance() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        (,,,, uint256 dominanceStartedAt, bool proposerWasDominant,) = oracle.getDispute(requestId);
        assertTrue(dominanceStartedAt > 0);
        assertTrue(proposerWasDominant);
    }

    function test_Vote_DominanceSwitches() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        (,,,, uint256 dominanceStartedAt1, bool proposerWasDominant1,) = oracle.getDispute(requestId);
        assertTrue(proposerWasDominant1);
        uint256 firstDominanceTime = dominanceStartedAt1;

        vm.warp(block.timestamp + 10 minutes);

        vm.prank(voter3);
        oracle.vote(requestId, false, 9000e6);

        (,,,, uint256 dominanceStartedAt2, bool proposerWasDominant2,) = oracle.getDispute(requestId);
        assertFalse(proposerWasDominant2);
        assertTrue(dominanceStartedAt2 > firstDominanceTime);
    }

    function test_Vote_TriggersEscalation() public {
        bytes32 requestId = _createProposeAndDispute();

        uint256 threshold = oracle.ESCALATION_THRESHOLD();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);

        vm.prank(voter1);
        oracle.vote(requestId, true, threshold);

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest(requestId);
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Escalated));
    }

    function test_Vote_RevertZeroAmount() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        oracle.vote(requestId, true, 0);
    }

    function test_Vote_RevertInvalidState() public {
        bytes32 requestId = _createAndPropose();

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidState.selector,
                requestId,
                IPolyOracleTypes.RequestState.Proposed,
                IPolyOracleTypes.RequestState.Disputed
            )
        );
        oracle.vote(requestId, true, 1000e6);
    }

    // --------------------------- Resolution Tests ---------------------------

    function test_ResolveUndisputed_Success() public {
        bytes32 requestId = _createAndPropose();

        vm.warp(block.timestamp + oracle.LIVENESS_PERIOD() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        oracle.resolveUndisputed(requestId);

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest(requestId);
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Resolved));

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND);

        bytes memory result = oracle.getResult(requestId);
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_ResolveUndisputed_RevertBeforeLiveness() public {
        bytes32 requestId = _createAndPropose();

        (,,, uint256 livenessEndsAt) = oracle.getProposal(requestId);

        vm.expectRevert(
            abi.encodeWithSelector(IPolyOracleTypes.LivenessPeriodNotEnded.selector, requestId, livenessEndsAt)
        );
        oracle.resolveUndisputed(requestId);
    }

    function test_ResolveDispute_ProposerWins() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        oracle.resolveDispute(requestId);

        (,,,, IPolyOracleTypes.RequestState state,) = oracle.getRequest(requestId);
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Resolved));

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);

        (,,,,,, IPolyOracleTypes.DisputeOutcome outcome) = oracle.getDispute(requestId);
        assertEq(uint256(outcome), uint256(IPolyOracleTypes.DisputeOutcome.ProposerWins));
    }

    function test_ResolveDispute_DisputerWins() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 3000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);

        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);

        oracle.resolveDispute(requestId);

        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + REWARD + BOND * 2);

        (,,,,,, IPolyOracleTypes.DisputeOutcome outcome) = oracle.getDispute(requestId);
        assertEq(uint256(outcome), uint256(IPolyOracleTypes.DisputeOutcome.DisputerWins));
    }

    function test_ResolveDispute_RevertNoDominance() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);

        vm.expectRevert(abi.encodeWithSelector(IPolyOracleTypes.NoDominance.selector, requestId));
        oracle.resolveDispute(requestId);
    }

    function test_ResolveDispute_RevertDominancePeriodNotMet() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.expectRevert(abi.encodeWithSelector(IPolyOracleTypes.DominancePeriodNotMet.selector, requestId));
        oracle.resolveDispute(requestId);
    }

    function test_AdminResolve_ProposerWins() public {
        bytes32 requestId = _createProposeAndDispute();

        uint256 threshold = oracle.ESCALATION_THRESHOLD();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(requestId, true, threshold);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        vm.prank(admin);
        oracle.adminResolve(requestId, true, RESULT);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);
    }

    function test_AdminResolve_DisputerWins() public {
        bytes32 requestId = _createProposeAndDispute();

        uint256 threshold = oracle.ESCALATION_THRESHOLD();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(requestId, true, threshold);

        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);

        vm.prank(admin);
        oracle.adminResolve(requestId, false, "");

        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + REWARD + BOND * 2);
    }

    function test_AdminResolve_RevertNotOwner() public {
        bytes32 requestId = _createProposeAndDispute();

        uint256 threshold = oracle.ESCALATION_THRESHOLD();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(requestId, true, threshold);

        vm.prank(requester);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, requester));
        oracle.adminResolve(requestId, true, RESULT);
    }

    function test_AdminResolve_RevertNotEscalated() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidState.selector,
                requestId,
                IPolyOracleTypes.RequestState.Disputed,
                IPolyOracleTypes.RequestState.Escalated
            )
        );
        oracle.adminResolve(requestId, true, RESULT);
    }

    // --------------------------- Claim Tests ---------------------------

    function test_ClaimWinnings_ProposerWinsVoterClaims() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);
        oracle.resolveDispute(requestId);

        uint256 voter1BalanceBefore = usdc.balanceOf(voter1);

        vm.prank(voter1);
        oracle.claimWinnings(requestId);

        uint256 expectedPayout = 3000e6 + 1000e6;
        assertEq(usdc.balanceOf(voter1), voter1BalanceBefore + expectedPayout);
    }

    function test_ClaimWinnings_DisputerWinsVoterClaims() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 3000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);
        oracle.resolveDispute(requestId);

        uint256 voter2BalanceBefore = usdc.balanceOf(voter2);

        vm.prank(voter2);
        oracle.claimWinnings(requestId);

        uint256 expectedPayout = 3000e6 + 1000e6;
        assertEq(usdc.balanceOf(voter2), voter2BalanceBefore + expectedPayout);
    }

    function test_ClaimWinnings_MultipleWinnersClaim() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 2000e6);

        vm.prank(voter3);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);
        oracle.resolveDispute(requestId);

        uint256 voter1BalanceBefore = usdc.balanceOf(voter1);
        vm.prank(voter1);
        oracle.claimWinnings(requestId);
        uint256 voter1Stake = 2000e6;
        uint256 totalWinnerPool = 3000e6;
        uint256 loserPool = 1000e6;
        uint256 voter1Expected = voter1Stake + (voter1Stake * loserPool / totalWinnerPool);
        assertEq(usdc.balanceOf(voter1), voter1BalanceBefore + voter1Expected);

        uint256 voter3BalanceBefore = usdc.balanceOf(voter3);
        vm.prank(voter3);
        oracle.claimWinnings(requestId);
        uint256 voter3Stake = 1000e6;
        uint256 voter3Expected = voter3Stake + (voter3Stake * loserPool / totalWinnerPool);
        assertEq(usdc.balanceOf(voter3), voter3BalanceBefore + voter3Expected);
    }

    function test_ClaimWinnings_RevertAlreadyClaimed() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);
        oracle.resolveDispute(requestId);

        vm.prank(voter1);
        oracle.claimWinnings(requestId);

        vm.prank(voter1);
        vm.expectRevert(IPolyOracleTypes.AlreadyClaimed.selector);
        oracle.claimWinnings(requestId);
    }

    function test_ClaimWinnings_RevertNothingToClaim() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);
        oracle.resolveDispute(requestId);

        vm.prank(voter2);
        vm.expectRevert(IPolyOracleTypes.NothingToClaim.selector);
        oracle.claimWinnings(requestId);
    }

    function test_ClaimWinnings_RevertNotResolved() public {
        bytes32 requestId = _createProposeAndDispute();

        vm.prank(voter1);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidState.selector,
                requestId,
                IPolyOracleTypes.RequestState.Disputed,
                IPolyOracleTypes.RequestState.Resolved
            )
        );
        oracle.claimWinnings(requestId);
    }

    // --------------------------- View Function Tests ---------------------------

    function test_GetResult_Success() public {
        bytes32 requestId = _createAndPropose();
        vm.warp(block.timestamp + oracle.LIVENESS_PERIOD() + 1);
        oracle.resolveUndisputed(requestId);

        bytes memory result = oracle.getResult(requestId);
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_GetResult_RevertNotResolved() public {
        bytes32 requestId = _createAndPropose();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPolyOracleTypes.InvalidState.selector,
                requestId,
                IPolyOracleTypes.RequestState.Proposed,
                IPolyOracleTypes.RequestState.Resolved
            )
        );
        oracle.getResult(requestId);
    }

    function test_CanResolveDispute() public {
        bytes32 requestId = _createProposeAndDispute();

        (bool canResolve1, string memory reason1) = oracle.canResolveDispute(requestId);
        assertFalse(canResolve1);
        assertEq(reason1, "No side has 2x dominance");

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        (bool canResolve2, string memory reason2) = oracle.canResolveDispute(requestId);
        assertFalse(canResolve2);
        assertEq(reason2, "Dominance period not met");

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);

        (bool canResolve3, string memory reason3) = oracle.canResolveDispute(requestId);
        assertTrue(canResolve3);
        assertEq(reason3, "Can resolve");
    }

    // --------------------------- Admin Tests ---------------------------

    function test_TransferOwnership() public {
        address newAdmin = address(0x99);

        vm.prank(admin);
        oracle.transferOwnership(newAdmin);

        assertEq(oracle.pendingOwner(), newAdmin);
        assertEq(oracle.owner(), admin);

        vm.prank(newAdmin);
        oracle.acceptOwnership();

        assertEq(oracle.owner(), newAdmin);
        assertEq(oracle.pendingOwner(), address(0));
    }

    function test_TransferOwnership_RevertNotOwner() public {
        vm.prank(requester);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, requester));
        oracle.transferOwnership(address(0x99));
    }

    function test_AcceptOwnership_RevertUnauthorized() public {
        vm.prank(admin);
        oracle.transferOwnership(address(0x99));

        vm.prank(requester);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, requester));
        oracle.acceptOwnership();
    }

    // --------------------------- Integration Tests ---------------------------

    function test_FullLifecycle_NoDispute() public {
        vm.prank(requester);
        bytes32 requestId = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        vm.warp(block.timestamp + oracle.LIVENESS_PERIOD() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        oracle.resolveUndisputed(requestId);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND);
        bytes memory result = oracle.getResult(requestId);
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_FullLifecycle_DisputeProposerWins() public {
        vm.prank(requester);
        bytes32 requestId = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        vm.prank(disputer);
        oracle.dispute(requestId);

        vm.prank(voter1);
        oracle.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 1000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        oracle.resolveDispute(requestId);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);

        vm.prank(voter1);
        oracle.claimWinnings(requestId);

        vm.prank(voter2);
        vm.expectRevert(IPolyOracleTypes.NothingToClaim.selector);
        oracle.claimWinnings(requestId);
    }

    function test_FullLifecycle_DisputeDisputerWins() public {
        vm.prank(requester);
        bytes32 requestId = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        vm.prank(disputer);
        oracle.dispute(requestId);

        vm.prank(voter1);
        oracle.vote(requestId, true, 1000e6);

        vm.prank(voter2);
        oracle.vote(requestId, false, 3000e6);

        vm.warp(block.timestamp + oracle.VOTING_DOMINANCE_PERIOD() + 1);

        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);
        oracle.resolveDispute(requestId);

        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + REWARD + BOND * 2);
    }

    function test_FullLifecycle_Escalation() public {
        vm.prank(requester);
        bytes32 requestId = oracle.initializeRequest(REWARD, BOND, DESCRIPTION);

        vm.prank(proposer);
        oracle.propose(requestId, RESULT);

        vm.prank(disputer);
        oracle.dispute(requestId);

        uint256 threshold = oracle.ESCALATION_THRESHOLD();

        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        usdc.approve(address(oracle), type(uint256).max);
        vm.prank(voter1);
        oracle.vote(requestId, true, threshold);

        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        vm.prank(admin);
        oracle.adminResolve(requestId, true, RESULT);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);
    }

    // --------------------------- Helper Functions ---------------------------

    function _createRequest() internal returns (bytes32) {
        vm.prank(requester);
        return oracle.initializeRequest(REWARD, BOND, DESCRIPTION);
    }

    function _createAndPropose() internal returns (bytes32) {
        bytes32 requestId = _createRequest();
        vm.prank(proposer);
        oracle.propose(requestId, RESULT);
        return requestId;
    }

    function _createProposeAndDispute() internal returns (bytes32) {
        bytes32 requestId = _createAndPropose();
        vm.prank(disputer);
        oracle.dispute(requestId);
        return requestId;
    }
}
