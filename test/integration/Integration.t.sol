// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PolyOracleMulti} from "../../src/PolyOracleMulti.sol";
import {PolyOracleFactory} from "../../src/PolyOracleFactory.sol";
import {PolyOracleSingle} from "../../src/PolyOracleSingle.sol";
import {IPolyOracleMulti} from "../../src/interfaces/IPolyOracleMulti.sol";
import {IPolyOracleSingle} from "../../src/interfaces/IPolyOracleSingle.sol";
import {IPolyOracleTypes} from "../../src/interfaces/IPolyOracleTypes.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

/// @title Integration Tests
/// @notice End-to-end tests for PolyOracle contracts
contract IntegrationTest is Test {
    PolyOracleMulti public oracleMulti;
    PolyOracleFactory public factory;
    PolyOracleSingle public implementation;
    MockUSDC public usdc;

    address public admin = address(0x1);
    address public requester1 = address(0x2);
    address public requester2 = address(0x3);
    address public proposer1 = address(0x4);
    address public proposer2 = address(0x5);
    address public disputer = address(0x6);
    address public voter1 = address(0x7);
    address public voter2 = address(0x8);
    address public voter3 = address(0x9);

    uint32 public constant LIVENESS_PERIOD = 1 hours;
    uint32 public constant VOTING_DOMINANCE_PERIOD = 30 minutes;
    uint256 public constant ESCALATION_THRESHOLD = 100_000e6;

    function setUp() public {
        usdc = new MockUSDC();

        // Deploy PolyOracleMulti
        oracleMulti =
            new PolyOracleMulti(address(usdc), admin, LIVENESS_PERIOD, VOTING_DOMINANCE_PERIOD, ESCALATION_THRESHOLD);

        // Deploy PolyOracleFactory with implementation
        implementation = new PolyOracleSingle();
        IPolyOracleTypes.Config memory config = IPolyOracleTypes.Config({
            livenessPeriod: LIVENESS_PERIOD,
            votingDominancePeriod: VOTING_DOMINANCE_PERIOD,
            escalationThreshold: ESCALATION_THRESHOLD
        });
        factory = new PolyOracleFactory(address(usdc), admin, address(implementation), config);

        // Fund all participants
        address[] memory participants = new address[](7);
        participants[0] = requester1;
        participants[1] = requester2;
        participants[2] = proposer1;
        participants[3] = proposer2;
        participants[4] = disputer;
        participants[5] = voter1;
        participants[6] = voter2;

        for (uint256 i = 0; i < participants.length; i++) {
            usdc.mint(participants[i], 1_000_000e6);
            vm.prank(participants[i]);
            usdc.approve(address(oracleMulti), type(uint256).max);
            vm.prank(participants[i]);
            usdc.approve(address(factory), type(uint256).max);
        }

        usdc.mint(voter3, 1_000_000e6);
    }

    // --------------------------- Multi-Request Oracle Integration Tests ---------------------------

    function test_Integration_Multi_ConcurrentRequests() public {
        // Create multiple concurrent requests
        uint256 reward = 100e6;
        uint256 bond = 50e6;

        vm.prank(requester1);
        bytes32 request1 = oracleMulti.initializeRequest(reward, bond, "ETH price?");

        vm.prank(requester2);
        bytes32 request2 = oracleMulti.initializeRequest(reward, bond, "BTC price?");

        // Different proposers submit to different requests
        vm.prank(proposer1);
        oracleMulti.propose(request1, abi.encode(3500e8));

        vm.prank(proposer2);
        oracleMulti.propose(request2, abi.encode(65000e8));

        // Request 1 gets disputed, Request 2 goes through undisputed
        vm.prank(disputer);
        oracleMulti.dispute(request1);

        // Wait for liveness on request 2
        vm.warp(block.timestamp + LIVENESS_PERIOD + 1);

        // Resolve request 2 (undisputed)
        uint256 proposer2BalanceBefore = usdc.balanceOf(proposer2);
        oracleMulti.resolveUndisputed(request2);
        assertEq(usdc.balanceOf(proposer2), proposer2BalanceBefore + reward + bond);

        // Vote on request 1
        vm.prank(voter1);
        oracleMulti.vote(request1, true, 3000e6);

        vm.prank(voter2);
        oracleMulti.vote(request1, false, 1000e6);

        // Wait for dominance period
        vm.warp(block.timestamp + VOTING_DOMINANCE_PERIOD + 1);

        // Resolve request 1
        uint256 proposer1BalanceBefore = usdc.balanceOf(proposer1);
        oracleMulti.resolveDispute(request1);
        assertEq(usdc.balanceOf(proposer1), proposer1BalanceBefore + reward + bond * 2);

        // Both results accessible
        bytes memory result1 = oracleMulti.getResult(request1);
        bytes memory result2 = oracleMulti.getResult(request2);
        assertEq(abi.decode(result1, (uint256)), 3500e8);
        assertEq(abi.decode(result2, (uint256)), 65000e8);
    }

    function test_Integration_Multi_EscalationFlow() public {
        uint256 reward = 100e6;
        uint256 bond = 50e6;

        vm.prank(requester1);
        bytes32 requestId = oracleMulti.initializeRequest(reward, bond, "Complex query");

        vm.prank(proposer1);
        oracleMulti.propose(requestId, abi.encode(12345));

        vm.prank(disputer);
        oracleMulti.dispute(requestId);

        // Large stake triggers escalation
        usdc.mint(voter1, ESCALATION_THRESHOLD);
        vm.prank(voter1);
        usdc.approve(address(oracleMulti), type(uint256).max);
        vm.prank(voter1);
        oracleMulti.vote(requestId, true, ESCALATION_THRESHOLD);

        // Verify escalated
        (,,,, IPolyOracleTypes.RequestState state,) = oracleMulti.getRequest(requestId);
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Escalated));

        // Admin resolves in favor of disputer
        bytes memory adminResult = abi.encode(54321);
        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);

        vm.prank(admin);
        oracleMulti.adminResolve(requestId, false, adminResult);

        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + reward + bond * 2);

        bytes memory finalResult = oracleMulti.getResult(requestId);
        assertEq(keccak256(finalResult), keccak256(adminResult));
    }

    // --------------------------- Factory/Single Oracle Integration Tests ---------------------------

    function test_Integration_Factory_MultipleOracles() public {
        uint256 reward = 100e6;
        uint256 bond = 50e6;

        // Create multiple oracles via factory
        vm.prank(requester1);
        address oracle1Addr = factory.createOracle(reward, bond, "Oracle 1");

        vm.prank(requester2);
        address oracle2Addr = factory.createOracle(reward, bond, "Oracle 2");

        IPolyOracleSingle oracle1 = IPolyOracleSingle(oracle1Addr);
        IPolyOracleSingle oracle2 = IPolyOracleSingle(oracle2Addr);

        // Approve both oracles
        vm.prank(proposer1);
        usdc.approve(oracle1Addr, type(uint256).max);
        vm.prank(proposer2);
        usdc.approve(oracle2Addr, type(uint256).max);

        // Different outcomes for each oracle
        vm.prank(proposer1);
        oracle1.propose(abi.encode(100));

        vm.prank(proposer2);
        oracle2.propose(abi.encode(200));

        // Both resolve undisputed
        vm.warp(block.timestamp + LIVENESS_PERIOD + 1);

        oracle1.resolveUndisputed();
        oracle2.resolveUndisputed();

        // Verify results
        bytes memory result1 = oracle1.getResult();
        bytes memory result2 = oracle2.getResult();
        assertEq(abi.decode(result1, (uint256)), 100);
        assertEq(abi.decode(result2, (uint256)), 200);
    }

    function test_Integration_Factory_ConfigUpdate() public {
        uint256 reward = 100e6;
        uint256 bond = 50e6;

        // Create oracle with original config
        vm.prank(requester1);
        address oracle1Addr = factory.createOracle(reward, bond, "Oracle 1");

        // Update config
        IPolyOracleTypes.Config memory newConfig = IPolyOracleTypes.Config({
            livenessPeriod: 2 hours, votingDominancePeriod: 1 hours, escalationThreshold: 200_000e6
        });
        vm.prank(admin);
        factory.updateDefaultConfig(newConfig);

        // Create oracle with new config
        vm.prank(requester2);
        address oracle2Addr = factory.createOracle(reward, bond, "Oracle 2");

        // Verify configs differ
        IPolyOracleSingle oracle1 = IPolyOracleSingle(oracle1Addr);
        IPolyOracleSingle oracle2 = IPolyOracleSingle(oracle2Addr);

        assertEq(oracle1.livenessPeriod(), 1 hours);
        assertEq(oracle2.livenessPeriod(), 2 hours);

        assertEq(oracle1.votingDominancePeriod(), 30 minutes);
        assertEq(oracle2.votingDominancePeriod(), 1 hours);

        assertEq(oracle1.escalationThreshold(), 100_000e6);
        assertEq(oracle2.escalationThreshold(), 200_000e6);
    }

    function test_Integration_Factory_DisputeWithVoterClaims() public {
        uint256 reward = 100e6;
        uint256 bond = 50e6;

        // Create oracle
        vm.prank(requester1);
        address oracleAddr = factory.createOracle(reward, bond, "Disputed query");
        IPolyOracleSingle oracle = IPolyOracleSingle(oracleAddr);

        // Approve
        vm.prank(proposer1);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(disputer);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(voter1);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(voter2);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(voter3);
        usdc.approve(oracleAddr, type(uint256).max);

        // Propose and dispute
        vm.prank(proposer1);
        oracle.propose(abi.encode(999));

        vm.prank(disputer);
        oracle.dispute();

        // Multiple voters
        vm.prank(voter1);
        oracle.vote(true, 2000e6); // For proposer

        vm.prank(voter2);
        oracle.vote(true, 1000e6); // For proposer

        vm.prank(voter3);
        oracle.vote(false, 1000e6); // For disputer

        // Wait for dominance
        vm.warp(block.timestamp + VOTING_DOMINANCE_PERIOD + 1);

        // Record balances
        uint256 voter1Before = usdc.balanceOf(voter1);
        uint256 voter2Before = usdc.balanceOf(voter2);
        uint256 voter3Before = usdc.balanceOf(voter3);

        // Resolve
        oracle.resolveDispute();

        // Claim winnings
        vm.prank(voter1);
        oracle.claimWinnings();

        vm.prank(voter2);
        oracle.claimWinnings();

        // Voter1 gets 2000 + (2000/3000)*1000 = 2000 + 666 = 2666
        uint256 voter1Stake = 2000e6;
        uint256 winnerPool = 3000e6;
        uint256 loserPool = 1000e6;
        uint256 voter1Expected = voter1Stake + (voter1Stake * loserPool / winnerPool);
        assertEq(usdc.balanceOf(voter1), voter1Before + voter1Expected);

        // Voter2 gets 1000 + (1000/3000)*1000 = 1000 + 333 = 1333
        uint256 voter2Stake = 1000e6;
        uint256 voter2Expected = voter2Stake + (voter2Stake * loserPool / winnerPool);
        assertEq(usdc.balanceOf(voter2), voter2Before + voter2Expected);

        // Voter3 was on losing side, nothing to claim
        vm.prank(voter3);
        vm.expectRevert(IPolyOracleTypes.NothingToClaim.selector);
        oracle.claimWinnings();
        assertEq(usdc.balanceOf(voter3), voter3Before);
    }

    // --------------------------- Cross-System Comparison Tests ---------------------------

    function test_Integration_MultiVsSingle_SameBehavior() public {
        uint256 reward = 100e6;
        uint256 bond = 50e6;
        bytes memory result = abi.encode(42);

        // ---- Multi Oracle Path ----
        vm.prank(requester1);
        bytes32 multiRequestId = oracleMulti.initializeRequest(reward, bond, "Test");

        vm.prank(proposer1);
        oracleMulti.propose(multiRequestId, result);

        vm.warp(block.timestamp + LIVENESS_PERIOD + 1);

        uint256 proposer1BalanceBefore = usdc.balanceOf(proposer1);
        oracleMulti.resolveUndisputed(multiRequestId);
        uint256 multiPayout = usdc.balanceOf(proposer1) - proposer1BalanceBefore;

        // ---- Single Oracle Path ----
        // Reset proposer balance tracking
        usdc.mint(proposer2, 10_000e6);
        vm.prank(proposer2);
        usdc.approve(address(factory), type(uint256).max);

        vm.prank(requester2);
        address singleAddr = factory.createOracle(reward, bond, "Test");
        IPolyOracleSingle singleOracle = IPolyOracleSingle(singleAddr);

        vm.prank(proposer2);
        usdc.approve(singleAddr, type(uint256).max);

        vm.prank(proposer2);
        singleOracle.propose(result);

        vm.warp(block.timestamp + LIVENESS_PERIOD + 1);

        uint256 proposer2BalanceBefore = usdc.balanceOf(proposer2);
        singleOracle.resolveUndisputed();
        uint256 singlePayout = usdc.balanceOf(proposer2) - proposer2BalanceBefore;

        // Payouts should be identical
        assertEq(multiPayout, singlePayout, "Multi and Single should have same payout");
        assertEq(multiPayout, reward + bond, "Payout should equal reward + bond");

        // Results should be identical
        bytes memory multiResult = oracleMulti.getResult(multiRequestId);
        bytes memory singleResult = singleOracle.getResult();
        assertEq(keccak256(multiResult), keccak256(singleResult), "Results should match");
    }

    // --------------------------- Edge Case Tests ---------------------------

    function test_Integration_DominanceSwitchResetsTimer() public {
        uint256 reward = 100e6;
        uint256 bond = 50e6;

        vm.prank(requester1);
        bytes32 requestId = oracleMulti.initializeRequest(reward, bond, "Contested");

        vm.prank(proposer1);
        oracleMulti.propose(requestId, abi.encode(1));

        vm.prank(disputer);
        oracleMulti.dispute(requestId);

        // Proposer side achieves dominance
        vm.prank(voter1);
        oracleMulti.vote(requestId, true, 3000e6);

        vm.prank(voter2);
        oracleMulti.vote(requestId, false, 1000e6);

        // Wait almost full dominance period
        vm.warp(block.timestamp + VOTING_DOMINANCE_PERIOD - 1 minutes);

        // Disputer side flips dominance
        usdc.mint(voter3, 10_000e6);
        vm.prank(voter3);
        usdc.approve(address(oracleMulti), type(uint256).max);
        vm.prank(voter3);
        oracleMulti.vote(requestId, false, 9000e6);

        // Cannot resolve yet - timer reset
        (,,,, uint256 dominanceStartedAt, bool proposerWasDominant,) = oracleMulti.getDispute(requestId);
        assertFalse(proposerWasDominant);
        assertTrue(dominanceStartedAt > 0);

        vm.expectRevert(abi.encodeWithSelector(IPolyOracleTypes.DominancePeriodNotMet.selector, requestId));
        oracleMulti.resolveDispute(requestId);

        // Wait for new dominance period
        vm.warp(block.timestamp + VOTING_DOMINANCE_PERIOD + 1);

        // Now can resolve - disputer wins
        uint256 disputerBalanceBefore = usdc.balanceOf(disputer);
        oracleMulti.resolveDispute(requestId);
        assertEq(usdc.balanceOf(disputer), disputerBalanceBefore + reward + bond * 2);
    }
}
