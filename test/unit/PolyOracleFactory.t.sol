// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PolyOracleFactory} from "../../src/PolyOracleFactory.sol";
import {PolyOracleSingle} from "../../src/PolyOracleSingle.sol";
import {IPolyOracleFactory} from "../../src/interfaces/IPolyOracleFactory.sol";
import {IPolyOracleSingle} from "../../src/interfaces/IPolyOracleSingle.sol";
import {IPolyOracleTypes} from "../../src/interfaces/IPolyOracleTypes.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PolyOracleFactoryTest is Test {
    PolyOracleFactory public factory;
    PolyOracleSingle public implementation;
    MockUSDC public usdc;

    address public admin = address(0x1);
    address public requester = address(0x2);
    address public proposer = address(0x3);
    address public disputer = address(0x4);
    address public voter1 = address(0x5);
    address public voter2 = address(0x6);

    uint256 public constant REWARD = 100e6; // 100 USDC
    uint256 public constant BOND = 50e6; // 50 USDC
    uint32 public constant LIVENESS_PERIOD = 1 hours;
    uint32 public constant VOTING_DOMINANCE_PERIOD = 30 minutes;
    uint256 public constant ESCALATION_THRESHOLD = 100_000e6; // 100k USDC
    bytes public constant DESCRIPTION = "What is the price of ETH?";
    bytes public constant RESULT = abi.encode(3500e8);

    IPolyOracleTypes.Config defaultConfig;

    function setUp() public {
        usdc = new MockUSDC();
        implementation = new PolyOracleSingle();

        defaultConfig = IPolyOracleTypes.Config({
            livenessPeriod: LIVENESS_PERIOD,
            votingDominancePeriod: VOTING_DOMINANCE_PERIOD,
            escalationThreshold: ESCALATION_THRESHOLD
        });

        factory = new PolyOracleFactory(address(usdc), admin, address(implementation), defaultConfig);

        // Fund accounts
        usdc.mint(requester, 10_000e6);
        usdc.mint(proposer, 1000e6);
        usdc.mint(disputer, 1000e6);
        usdc.mint(voter1, 10_000e6);
        usdc.mint(voter2, 10_000e6);

        // Approve factory
        vm.prank(requester);
        usdc.approve(address(factory), type(uint256).max);
    }

    // --------------------------- Constructor Tests ---------------------------

    function test_Constructor_SetsImmutables() public view {
        assertEq(address(factory.USDC()), address(usdc));
        assertEq(factory.IMPLEMENTATION(), address(implementation));
        assertEq(factory.owner(), admin);

        (uint256 livenessPeriod, uint256 votingDominancePeriod, uint256 escalationThreshold) = factory.defaultConfig();
        assertEq(livenessPeriod, LIVENESS_PERIOD);
        assertEq(votingDominancePeriod, VOTING_DOMINANCE_PERIOD);
        assertEq(escalationThreshold, ESCALATION_THRESHOLD);
    }

    function test_Constructor_RevertZeroUsdc() public {
        vm.expectRevert(IPolyOracleTypes.ZeroAddress.selector);
        new PolyOracleFactory(address(0), admin, address(implementation), defaultConfig);
    }

    function test_Constructor_RevertZeroAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new PolyOracleFactory(address(usdc), address(0), address(implementation), defaultConfig);
    }

    function test_Constructor_RevertZeroImplementation() public {
        vm.expectRevert(IPolyOracleTypes.ZeroAddress.selector);
        new PolyOracleFactory(address(usdc), admin, address(0), defaultConfig);
    }

    function test_Constructor_RevertInvalidConfig_ZeroLivenessPeriod() public {
        IPolyOracleTypes.Config memory badConfig = IPolyOracleTypes.Config({
            livenessPeriod: 0, votingDominancePeriod: VOTING_DOMINANCE_PERIOD, escalationThreshold: ESCALATION_THRESHOLD
        });

        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        new PolyOracleFactory(address(usdc), admin, address(implementation), badConfig);
    }

    function test_Constructor_RevertInvalidConfig_ZeroVotingDominancePeriod() public {
        IPolyOracleTypes.Config memory badConfig = IPolyOracleTypes.Config({
            livenessPeriod: LIVENESS_PERIOD, votingDominancePeriod: 0, escalationThreshold: ESCALATION_THRESHOLD
        });

        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        new PolyOracleFactory(address(usdc), admin, address(implementation), badConfig);
    }

    function test_Constructor_RevertInvalidConfig_ZeroEscalationThreshold() public {
        IPolyOracleTypes.Config memory badConfig = IPolyOracleTypes.Config({
            livenessPeriod: LIVENESS_PERIOD, votingDominancePeriod: VOTING_DOMINANCE_PERIOD, escalationThreshold: 0
        });

        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        new PolyOracleFactory(address(usdc), admin, address(implementation), badConfig);
    }

    // --------------------------- Create Oracle Tests ---------------------------

    function test_CreateOracle_Success() public {
        vm.prank(requester);
        address oracleAddr = factory.createOracle(REWARD, BOND, DESCRIPTION);

        assertTrue(oracleAddr != address(0));
        assertTrue(factory.isOracle(oracleAddr));
        assertEq(factory.oracleCount(), 1);
        assertEq(factory.getOracle(0), oracleAddr);

        // Check oracle is properly initialized
        IPolyOracleSingle oracle = IPolyOracleSingle(oracleAddr);

        assertEq(oracle.usdc(), address(usdc));
        assertEq(oracle.factory(), address(factory));
        assertEq(oracle.livenessPeriod(), LIVENESS_PERIOD);
        assertEq(oracle.votingDominancePeriod(), VOTING_DOMINANCE_PERIOD);
        assertEq(oracle.escalationThreshold(), ESCALATION_THRESHOLD);

        (address req, uint256 reward, uint256 bondAmount, bytes memory desc, IPolyOracleTypes.RequestState state,) =
            oracle.getRequest();

        assertEq(req, requester);
        assertEq(reward, REWARD);
        assertEq(bondAmount, BOND);
        assertEq(keccak256(desc), keccak256(DESCRIPTION));
        assertEq(uint256(state), uint256(IPolyOracleTypes.RequestState.Initialized));
    }

    function test_CreateOracle_TransfersReward() public {
        uint256 requesterBalanceBefore = usdc.balanceOf(requester);

        vm.prank(requester);
        address oracleAddr = factory.createOracle(REWARD, BOND, DESCRIPTION);

        assertEq(usdc.balanceOf(requester), requesterBalanceBefore - REWARD);
        assertEq(usdc.balanceOf(oracleAddr), REWARD);
    }

    function test_CreateOracle_EmitsEvent() public {
        vm.prank(requester);
        vm.expectEmit(false, true, false, true);
        emit IPolyOracleFactory.OracleCreated(address(0), requester, REWARD, BOND);
        factory.createOracle(REWARD, BOND, DESCRIPTION);
    }

    function test_CreateOracle_MultipleOracles() public {
        vm.startPrank(requester);

        address oracle1 = factory.createOracle(REWARD, BOND, "Request 1");
        address oracle2 = factory.createOracle(REWARD, BOND, "Request 2");
        address oracle3 = factory.createOracle(REWARD, BOND, "Request 3");

        vm.stopPrank();

        assertEq(factory.oracleCount(), 3);
        assertEq(factory.getOracle(0), oracle1);
        assertEq(factory.getOracle(1), oracle2);
        assertEq(factory.getOracle(2), oracle3);

        assertTrue(factory.isOracle(oracle1));
        assertTrue(factory.isOracle(oracle2));
        assertTrue(factory.isOracle(oracle3));
        assertFalse(factory.isOracle(address(0x999)));
    }

    function test_CreateOracle_RevertZeroReward() public {
        vm.prank(requester);
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        factory.createOracle(0, BOND, DESCRIPTION);
    }

    function test_CreateOracle_RevertZeroBond() public {
        vm.prank(requester);
        vm.expectRevert(IPolyOracleTypes.ZeroAmount.selector);
        factory.createOracle(REWARD, 0, DESCRIPTION);
    }

    // --------------------------- Update Default Config Tests ---------------------------

    function test_UpdateDefaultConfig_Success() public {
        IPolyOracleTypes.Config memory newConfig = IPolyOracleTypes.Config({
            livenessPeriod: 2 hours, votingDominancePeriod: 1 hours, escalationThreshold: 200_000e6
        });

        vm.prank(admin);
        factory.updateDefaultConfig(newConfig);

        (uint256 livenessPeriod, uint256 votingDominancePeriod, uint256 escalationThreshold) = factory.defaultConfig();
        assertEq(livenessPeriod, 2 hours);
        assertEq(votingDominancePeriod, 1 hours);
        assertEq(escalationThreshold, 200_000e6);
    }

    function test_UpdateDefaultConfig_EmitsEvent() public {
        IPolyOracleTypes.Config memory newConfig = IPolyOracleTypes.Config({
            livenessPeriod: 2 hours, votingDominancePeriod: 1 hours, escalationThreshold: 200_000e6
        });

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IPolyOracleFactory.DefaultConfigUpdated(defaultConfig, newConfig);
        factory.updateDefaultConfig(newConfig);
    }

    function test_UpdateDefaultConfig_AffectsNewOracles() public {
        // Create oracle with original config
        vm.prank(requester);
        address oracle1 = factory.createOracle(REWARD, BOND, "Request 1");

        // Update config
        IPolyOracleTypes.Config memory newConfig = IPolyOracleTypes.Config({
            livenessPeriod: 2 hours, votingDominancePeriod: 1 hours, escalationThreshold: 200_000e6
        });
        vm.prank(admin);
        factory.updateDefaultConfig(newConfig);

        // Create oracle with new config
        vm.prank(requester);
        address oracle2 = factory.createOracle(REWARD, BOND, "Request 2");

        // First oracle has old config
        IPolyOracleSingle o1 = IPolyOracleSingle(oracle1);
        assertEq(o1.livenessPeriod(), LIVENESS_PERIOD);
        assertEq(o1.votingDominancePeriod(), VOTING_DOMINANCE_PERIOD);
        assertEq(o1.escalationThreshold(), ESCALATION_THRESHOLD);

        // Second oracle has new config
        IPolyOracleSingle o2 = IPolyOracleSingle(oracle2);
        assertEq(o2.livenessPeriod(), 2 hours);
        assertEq(o2.votingDominancePeriod(), 1 hours);
        assertEq(o2.escalationThreshold(), 200_000e6);
    }

    function test_UpdateDefaultConfig_RevertNotOwner() public {
        IPolyOracleTypes.Config memory newConfig = IPolyOracleTypes.Config({
            livenessPeriod: 2 hours, votingDominancePeriod: 1 hours, escalationThreshold: 200_000e6
        });

        vm.prank(requester);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, requester));
        factory.updateDefaultConfig(newConfig);
    }

    function test_UpdateDefaultConfig_RevertInvalidConfig() public {
        IPolyOracleTypes.Config memory badConfig = IPolyOracleTypes.Config({
            livenessPeriod: 0, votingDominancePeriod: VOTING_DOMINANCE_PERIOD, escalationThreshold: ESCALATION_THRESHOLD
        });

        vm.prank(admin);
        vm.expectRevert(IPolyOracleTypes.InvalidConfig.selector);
        factory.updateDefaultConfig(badConfig);
    }

    // --------------------------- Admin Resolve Through Factory Tests ---------------------------

    function test_AdminResolve_ViaFactory() public {
        // Create oracle
        vm.prank(requester);
        address oracleAddr = factory.createOracle(REWARD, BOND, DESCRIPTION);
        IPolyOracleSingle oracle = IPolyOracleSingle(oracleAddr);

        // Approve oracle for proposer and disputer
        vm.prank(proposer);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(disputer);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(voter1);
        usdc.approve(oracleAddr, type(uint256).max);

        // Propose
        vm.prank(proposer);
        oracle.propose(RESULT);

        // Dispute
        vm.prank(disputer);
        oracle.dispute();

        // Escalate
        uint256 threshold = oracle.escalationThreshold();
        usdc.mint(voter1, threshold);
        vm.prank(voter1);
        oracle.vote(true, threshold);

        // Factory admin can resolve
        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);

        vm.prank(admin);
        oracle.adminResolve(true, RESULT);

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);
    }

    // --------------------------- Ownership Tests ---------------------------

    function test_TransferOwnership() public {
        address newAdmin = address(0x99);

        vm.prank(admin);
        factory.transferOwnership(newAdmin);

        assertEq(factory.pendingOwner(), newAdmin);
        assertEq(factory.owner(), admin);

        vm.prank(newAdmin);
        factory.acceptOwnership();

        assertEq(factory.owner(), newAdmin);
        assertEq(factory.pendingOwner(), address(0));
    }

    // --------------------------- Integration Tests ---------------------------

    function test_FullLifecycle_ViaFactory() public {
        // Create oracle
        vm.prank(requester);
        address oracleAddr = factory.createOracle(REWARD, BOND, DESCRIPTION);
        IPolyOracleSingle oracle = IPolyOracleSingle(oracleAddr);

        // Approve oracle
        vm.prank(proposer);
        usdc.approve(oracleAddr, type(uint256).max);

        // Propose
        vm.prank(proposer);
        oracle.propose(RESULT);

        // Wait for liveness
        vm.warp(block.timestamp + LIVENESS_PERIOD + 1);

        // Resolve
        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        oracle.resolveUndisputed();

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND);

        bytes memory result = oracle.getResult();
        assertEq(keccak256(result), keccak256(RESULT));
    }

    function test_FullLifecycle_DisputeViaFactory() public {
        // Create oracle
        vm.prank(requester);
        address oracleAddr = factory.createOracle(REWARD, BOND, DESCRIPTION);
        IPolyOracleSingle oracle = IPolyOracleSingle(oracleAddr);

        // Approve oracle
        vm.prank(proposer);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(disputer);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(voter1);
        usdc.approve(oracleAddr, type(uint256).max);
        vm.prank(voter2);
        usdc.approve(oracleAddr, type(uint256).max);

        // Propose
        vm.prank(proposer);
        oracle.propose(RESULT);

        // Dispute
        vm.prank(disputer);
        oracle.dispute();

        // Vote
        vm.prank(voter1);
        oracle.vote(true, 3000e6);

        vm.prank(voter2);
        oracle.vote(false, 1000e6);

        // Wait for dominance period
        vm.warp(block.timestamp + VOTING_DOMINANCE_PERIOD + 1);

        // Resolve
        uint256 proposerBalanceBefore = usdc.balanceOf(proposer);
        oracle.resolveDispute();

        assertEq(usdc.balanceOf(proposer), proposerBalanceBefore + REWARD + BOND * 2);

        // Claim winnings
        vm.prank(voter1);
        oracle.claimWinnings();

        vm.prank(voter2);
        vm.expectRevert(IPolyOracleTypes.NothingToClaim.selector);
        oracle.claimWinnings();
    }
}
