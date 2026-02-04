// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IPolyOracleTypes
/// @notice Shared types, errors, and events for PolyOracle contracts
interface IPolyOracleTypes {
    // --------------------------- Enums ---------------------------

    /// @notice Request lifecycle states
    enum RequestState {
        Uninitialized, // 0 - Default
        Initialized, // 1 - Request created, awaiting proposal
        Proposed, // 2 - Proposal submitted, in liveness period
        Disputed, // 3 - Dispute raised, voting in progress
        Escalated, // 4 - Stake threshold exceeded, admin resolution required
        Resolved // 5 - Final result determined
    }

    /// @notice Outcome of a disputed request
    enum DisputeOutcome {
        None, // 0 - No dispute or not resolved yet
        ProposerWins, // 1 - Original proposal was correct
        DisputerWins // 2 - Disputer's challenge was correct
    }

    // --------------------------- Structs ---------------------------

    /// @notice Core request data
    struct Request {
        address requester;
        uint256 reward;
        uint256 bondAmount;
        bytes description;
        RequestState state;
        uint64 createdAt;
    }

    /// @notice Proposal data for a request
    struct Proposal {
        address proposer;
        uint64 proposedAt;
        bytes result;
        uint64 livenessEndsAt;
    }

    /// @notice Dispute data for a request
    struct Dispute {
        address disputer;
        uint64 disputedAt;
        uint256 proposerStake;
        uint256 disputerStake;
        uint64 dominanceStartedAt;
        bool proposerWasDominant;
        DisputeOutcome outcome;
    }

    /// @notice Individual voter stake record
    struct VoterStake {
        uint256 proposerStake;
        uint256 disputerStake;
        bool claimed;
    }

    /// @notice Configuration parameters
    struct Config {
        uint32 livenessPeriod;
        uint32 votingDominancePeriod;
        uint256 escalationThreshold;
    }

    // --------------------------- Errors ---------------------------

    error InvalidState(bytes32 requestId, RequestState current, RequestState expected);
    error InvalidStateSingle(RequestState current, RequestState expected);
    error RequestNotFound(bytes32 requestId);
    error LivenessPeriodNotEnded(bytes32 requestId, uint64 endsAt);
    error LivenessPeriodNotEndedSingle(uint64 endsAt);
    error LivenessPeriodEnded(bytes32 requestId);
    error LivenessPeriodEndedSingle();
    error DominancePeriodNotMet(bytes32 requestId);
    error DominancePeriodNotMetSingle();
    error NoDominance(bytes32 requestId);
    error NoDominanceSingle();
    error Unauthorized();
    error ZeroAmount();
    error ZeroAddress();
    error NothingToClaim();
    error AlreadyClaimed();
    error InvalidConfig();
    error AlreadyInitialized();
    error NotInitialized();

    // --------------------------- Events ---------------------------

    event RequestInitialized(
        bytes32 indexed requestId, address indexed requester, uint256 reward, uint256 bondAmount, bytes description
    );
    event RequestInitializedSingle(address indexed requester, uint256 reward, uint256 bondAmount, bytes description);
    event ProposalSubmitted(bytes32 indexed requestId, address indexed proposer, bytes result, uint256 livenessEndsAt);
    event ProposalSubmittedSingle(address indexed proposer, bytes result, uint256 livenessEndsAt);
    event DisputeRaised(bytes32 indexed requestId, address indexed disputer);
    event DisputeRaisedSingle(address indexed disputer);
    event VoteStaked(bytes32 indexed requestId, address indexed voter, bool forProposer, uint256 amount);
    event VoteStakedSingle(address indexed voter, bool forProposer, uint256 amount);
    event RequestEscalated(bytes32 indexed requestId, uint256 totalStake);
    event RequestEscalatedSingle(uint256 totalStake);
    event RequestResolved(bytes32 indexed requestId, DisputeOutcome outcome, bytes result);
    event RequestResolvedSingle(DisputeOutcome outcome, bytes result);
    event RewardsClaimed(bytes32 indexed requestId, address indexed claimant, uint256 amount);
    event RewardsClaimedSingle(address indexed claimant, uint256 amount);
    event ConfigUpdated(string parameter, uint256 oldValue, uint256 newValue);
}
