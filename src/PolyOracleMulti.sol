// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleMulti} from "./interfaces/IPolyOracleMulti.sol";
import {PolyOracleBase} from "./abstracts/PolyOracleBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PolyOracleMulti
/// @notice Multi-request oracle contract with immutable configuration
/// @dev Handles multiple oracle requests with USDC-based dispute resolution
contract PolyOracleMulti is IPolyOracleMulti, PolyOracleBase {
    using SafeERC20 for IERC20;

    // --------------------------- Storage ---------------------------

    /// @notice Incrementing nonce for generating unique request IDs
    uint256 public requestNonce;

    /// @notice Request data by request ID
    mapping(bytes32 => Request) internal _requests;

    /// @notice Proposal data by request ID
    mapping(bytes32 => Proposal) internal _proposals;

    /// @notice Dispute data by request ID
    mapping(bytes32 => Dispute) internal _disputes;

    /// @notice Voter stakes by request ID and voter address
    mapping(bytes32 => mapping(address => VoterStake)) internal _voterStakes;

    /// @notice Final results by request ID
    mapping(bytes32 => bytes) internal _finalResults;

    // --------------------------- Constructor ---------------------------

    /// @notice Initialize the multi-request oracle
    /// @param usdc The USDC token address
    /// @param admin The admin address (owner)
    /// @param livenessPeriod The liveness period in seconds
    /// @param votingDominancePeriod The voting dominance period in seconds
    /// @param escalationThreshold The escalation threshold in USDC
    constructor(
        address usdc,
        address admin,
        uint32 livenessPeriod,
        uint32 votingDominancePeriod,
        uint256 escalationThreshold
    ) PolyOracleBase(usdc, admin, livenessPeriod, votingDominancePeriod, escalationThreshold) {}

    // --------------------------- Core Functions ---------------------------

    /// @inheritdoc IPolyOracleMulti
    function initializeRequest(uint256 reward, uint256 bond, bytes memory description)
        external
        nonReentrant
        returns (bytes32 requestId)
    {
        if (reward == 0) revert ZeroAmount();
        if (bond == 0) revert ZeroAmount();

        // Create pseudo-unique request ID & increment the requestNonce
        requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, requestNonce++));

        // Store the Request
        _requests[requestId] = Request({
            requester: msg.sender,
            reward: reward,
            bondAmount: bond,
            description: description,
            state: RequestState.Initialized,
            createdAt: uint64(block.timestamp)
        });

        // Transfer reward from requester
        USDC.safeTransferFrom(msg.sender, address(this), reward);

        emit RequestInitialized(requestId, msg.sender, reward, bond, description);
    }

    /// @inheritdoc IPolyOracleMulti
    function propose(bytes32 requestId, bytes calldata result) external nonReentrant {
        Request storage request = _requests[requestId];

        if (request.state != RequestState.Initialized) {
            revert InvalidState(requestId, request.state, RequestState.Initialized);
        }

        // Transfer bond from proposer
        USDC.safeTransferFrom(msg.sender, address(this), request.bondAmount);

        uint64 livenessEndsAt = uint64(block.timestamp) + LIVENESS_PERIOD;

        _proposals[requestId] = Proposal({
            proposer: msg.sender, result: result, proposedAt: uint64(block.timestamp), livenessEndsAt: livenessEndsAt
        });

        request.state = RequestState.Proposed;

        emit ProposalSubmitted(requestId, msg.sender, result, livenessEndsAt);
    }

    /// @inheritdoc IPolyOracleMulti
    function dispute(bytes32 requestId) external nonReentrant {
        Request storage request = _requests[requestId];

        if (request.state != RequestState.Proposed) {
            revert InvalidState(requestId, request.state, RequestState.Proposed);
        }

        Proposal storage proposal = _proposals[requestId];
        if (block.timestamp >= proposal.livenessEndsAt) {
            revert LivenessPeriodEnded(requestId);
        }

        // Transfer bond from disputer
        USDC.safeTransferFrom(msg.sender, address(this), request.bondAmount);

        _disputes[requestId] = Dispute({
            disputer: msg.sender,
            disputedAt: uint64(block.timestamp),
            proposerStake: 0,
            disputerStake: 0,
            dominanceStartedAt: 0,
            proposerWasDominant: false,
            outcome: DisputeOutcome.None
        });

        request.state = RequestState.Disputed;

        emit DisputeRaised(requestId, msg.sender);
    }

    /// @inheritdoc IPolyOracleMulti
    function vote(bytes32 requestId, bool forProposer, uint256 amount) external nonReentrant {
        Request storage request = _requests[requestId];

        if (request.state != RequestState.Disputed) {
            revert InvalidState(requestId, request.state, RequestState.Disputed);
        }

        if (amount == 0) revert ZeroAmount();

        // Transfer stake from voter
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        Dispute storage d = _disputes[requestId];
        VoterStake storage vs = _voterStakes[requestId][msg.sender];

        if (forProposer) {
            d.proposerStake += amount;
            vs.proposerStake += amount;
        } else {
            d.disputerStake += amount;
            vs.disputerStake += amount;
        }

        // Update dominance tracking
        (d.dominanceStartedAt, d.proposerWasDominant) =
            _updateDominance(d.proposerStake, d.disputerStake, d.dominanceStartedAt, d.proposerWasDominant);

        // Check escalation threshold
        uint256 totalStake = d.proposerStake + d.disputerStake;
        if (totalStake >= ESCALATION_THRESHOLD) {
            request.state = RequestState.Escalated;
            emit RequestEscalated(requestId, totalStake);
        }

        emit VoteStaked(requestId, msg.sender, forProposer, amount);
    }

    /// @inheritdoc IPolyOracleMulti
    function resolveUndisputed(bytes32 requestId) external nonReentrant {
        Request storage request = _requests[requestId];
        if (request.state != RequestState.Proposed) {
            revert InvalidState(requestId, request.state, RequestState.Proposed);
        }

        Proposal storage proposal = _proposals[requestId];
        if (block.timestamp < proposal.livenessEndsAt) {
            revert LivenessPeriodNotEnded(requestId, proposal.livenessEndsAt);
        }

        request.state = RequestState.Resolved;
        _finalResults[requestId] = proposal.result;

        // Create a dispute record to track outcome consistently
        _disputes[requestId].outcome = DisputeOutcome.ProposerWins;

        // Proposer gets reward + bond back
        uint256 payout = request.reward + request.bondAmount;
        USDC.safeTransfer(proposal.proposer, payout);

        emit RequestResolved(requestId, DisputeOutcome.ProposerWins, proposal.result);
    }

    /// @inheritdoc IPolyOracleMulti
    function resolveDispute(bytes32 requestId) external nonReentrant {
        Request storage request = _requests[requestId];
        if (request.state != RequestState.Disputed) {
            revert InvalidState(requestId, request.state, RequestState.Disputed);
        }

        Dispute storage d = _disputes[requestId];

        // Check dominance condition
        (bool hasDominance, bool proposerDominant) = _checkDominance(d.proposerStake, d.disputerStake);
        if (!hasDominance) {
            revert NoDominance(requestId);
        }

        // Check duration requirement
        if (d.dominanceStartedAt == 0 || block.timestamp < d.dominanceStartedAt + VOTING_DOMINANCE_PERIOD) {
            revert DominancePeriodNotMet(requestId);
        }

        request.state = RequestState.Resolved;
        Proposal storage proposal = _proposals[requestId];

        if (proposerDominant) {
            d.outcome = DisputeOutcome.ProposerWins;
            _finalResults[requestId] = proposal.result;

            // Proposer gets: reward + their bond + disputer's bond
            uint256 proposerPayout = request.reward + (request.bondAmount * 2);
            USDC.safeTransfer(proposal.proposer, proposerPayout);

            emit RequestResolved(requestId, DisputeOutcome.ProposerWins, proposal.result);
        } else {
            d.outcome = DisputeOutcome.DisputerWins;

            // Disputer gets: reward + proposer's bond + their bond back
            uint256 disputerPayout = request.reward + (request.bondAmount * 2);
            USDC.safeTransfer(d.disputer, disputerPayout);

            emit RequestResolved(requestId, DisputeOutcome.DisputerWins, "");
        }
    }

    /// @inheritdoc IPolyOracleMulti
    function adminResolve(bytes32 requestId, bool proposerWins, bytes calldata result) external onlyOwner nonReentrant {
        Request storage request = _requests[requestId];
        if (request.state != RequestState.Escalated) {
            revert InvalidState(requestId, request.state, RequestState.Escalated);
        }

        request.state = RequestState.Resolved;
        _finalResults[requestId] = result;

        Dispute storage d = _disputes[requestId];
        Proposal storage proposal = _proposals[requestId];

        if (proposerWins) {
            d.outcome = DisputeOutcome.ProposerWins;
            uint256 proposerPayout = request.reward + (request.bondAmount * 2);
            USDC.safeTransfer(proposal.proposer, proposerPayout);
            emit RequestResolved(requestId, DisputeOutcome.ProposerWins, result);
        } else {
            d.outcome = DisputeOutcome.DisputerWins;
            uint256 disputerPayout = request.reward + (request.bondAmount * 2);
            USDC.safeTransfer(d.disputer, disputerPayout);
            emit RequestResolved(requestId, DisputeOutcome.DisputerWins, result);
        }
    }

    /// @inheritdoc IPolyOracleMulti
    function claimWinnings(bytes32 requestId) external nonReentrant {
        Request storage request = _requests[requestId];
        if (request.state != RequestState.Resolved) {
            revert InvalidState(requestId, request.state, RequestState.Resolved);
        }

        Dispute storage d = _disputes[requestId];
        VoterStake storage vs = _voterStakes[requestId][msg.sender];

        if (vs.claimed) revert AlreadyClaimed();

        uint256 payout;
        if (d.outcome == DisputeOutcome.ProposerWins) {
            if (vs.proposerStake == 0) revert NothingToClaim();
            payout = _calculatePayout(vs.proposerStake, d.proposerStake, d.disputerStake);
        } else if (d.outcome == DisputeOutcome.DisputerWins) {
            if (vs.disputerStake == 0) revert NothingToClaim();
            payout = _calculatePayout(vs.disputerStake, d.disputerStake, d.proposerStake);
        } else {
            revert NothingToClaim();
        }

        vs.claimed = true;
        USDC.safeTransfer(msg.sender, payout);

        emit RewardsClaimed(requestId, msg.sender, payout);
    }

    // --------------------------- View Functions ---------------------------

    /// @inheritdoc IPolyOracleMulti
    function getResult(bytes32 requestId) external view returns (bytes memory) {
        Request storage request = _requests[requestId];
        if (request.state != RequestState.Resolved) {
            revert InvalidState(requestId, request.state, RequestState.Resolved);
        }
        return _finalResults[requestId];
    }

    /// @inheritdoc IPolyOracleMulti
    function getRequest(bytes32 requestId)
        external
        view
        returns (
            address requester,
            uint256 reward,
            uint256 bondAmount,
            bytes memory description,
            RequestState state,
            uint64 createdAt
        )
    {
        Request storage r = _requests[requestId];
        return (r.requester, r.reward, r.bondAmount, r.description, r.state, r.createdAt);
    }

    /// @inheritdoc IPolyOracleMulti
    function getProposal(bytes32 requestId)
        external
        view
        returns (address proposer, bytes memory result, uint64 proposedAt, uint64 livenessEndsAt)
    {
        Proposal storage p = _proposals[requestId];
        return (p.proposer, p.result, p.proposedAt, p.livenessEndsAt);
    }

    /// @inheritdoc IPolyOracleMulti
    function getDispute(bytes32 requestId)
        external
        view
        returns (
            address disputer,
            uint64 disputedAt,
            uint256 proposerStake,
            uint256 disputerStake,
            uint64 dominanceStartedAt,
            bool proposerWasDominant,
            DisputeOutcome outcome
        )
    {
        Dispute storage d = _disputes[requestId];
        return (
            d.disputer,
            d.disputedAt,
            d.proposerStake,
            d.disputerStake,
            d.dominanceStartedAt,
            d.proposerWasDominant,
            d.outcome
        );
    }

    /// @inheritdoc IPolyOracleMulti
    function getVoterStake(bytes32 requestId, address voter)
        external
        view
        returns (uint256 proposerStake, uint256 disputerStake, bool claimed)
    {
        VoterStake storage vs = _voterStakes[requestId][voter];
        return (vs.proposerStake, vs.disputerStake, vs.claimed);
    }

    /// @inheritdoc IPolyOracleMulti
    function canResolveDispute(bytes32 requestId) external view returns (bool canResolve, string memory reason) {
        Request storage request = _requests[requestId];
        if (request.state != RequestState.Disputed) {
            return (false, "Not in disputed state");
        }

        Dispute storage d = _disputes[requestId];
        (bool hasDominance,) = _checkDominance(d.proposerStake, d.disputerStake);
        if (!hasDominance) {
            return (false, "No side has 2x dominance");
        }

        if (d.dominanceStartedAt == 0) {
            return (false, "Dominance not tracked");
        }

        if (block.timestamp < d.dominanceStartedAt + VOTING_DOMINANCE_PERIOD) {
            return (false, "Dominance period not met");
        }

        return (true, "Can resolve");
    }
}
