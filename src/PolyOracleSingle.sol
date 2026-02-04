// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleSingle} from "./interfaces/IPolyOracleSingle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PolyOracleSingle
/// @notice Single-request oracle deployed as EIP-1167 minimal proxy clone
/// @dev Clone address serves as the unique identifier - no requestId needed
contract PolyOracleSingle is IPolyOracleSingle, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --------------------------- Storage ---------------------------

    /// @notice The USDC token used for bonds, rewards, and stakes
    address public usdc;

    /// @notice The factory that created this clone
    address public factory;

    /// @notice Duration a proposal must remain undisputed before resolution
    uint32 public livenessPeriod;

    /// @notice Duration one side must maintain 2x dominance for resolution
    uint32 public votingDominancePeriod;

    /// @notice Total stake threshold that triggers escalation
    uint256 public escalationThreshold;

    /// @notice Whether this clone has been initialized
    bool private _initialized;

    /// @notice The oracle request data
    Request internal _request;

    /// @notice The proposal data
    Proposal internal _proposal;

    /// @notice The dispute data
    Dispute internal _dispute;

    /// @notice Voter stakes by voter address
    mapping(address => VoterStake) internal _voterStakes;

    /// @notice The final result
    bytes internal _finalResult;

    // --------------------------- Modifiers ---------------------------

    /// @notice Ensures only factory admin can call
    modifier onlyFactoryAdmin() {
        _checkFactoryAdmin();
        _;
    }

    function _checkFactoryAdmin() internal view {
        if (msg.sender != Ownable2Step(factory).owner()) revert Unauthorized();
    }

    // --------------------------- Initialization ---------------------------

    /// @inheritdoc IPolyOracleSingle
    function initialize(
        address usdcAddress,
        address factoryAddress,
        address requester,
        uint256 reward,
        uint256 bondAmount,
        bytes calldata description,
        uint32 livenessPeriodValue,
        uint32 votingDominancePeriodValue,
        uint256 escalationThresholdValue
    ) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        if (usdcAddress == address(0)) revert ZeroAddress();
        if (factoryAddress == address(0)) revert ZeroAddress();
        if (requester == address(0)) revert ZeroAddress();
        if (reward == 0) revert ZeroAmount();
        if (bondAmount == 0) revert ZeroAmount();
        if (livenessPeriodValue == 0) revert InvalidConfig();
        if (votingDominancePeriodValue == 0) revert InvalidConfig();
        if (escalationThresholdValue == 0) revert InvalidConfig();

        usdc = usdcAddress;
        factory = factoryAddress;
        livenessPeriod = livenessPeriodValue;
        votingDominancePeriod = votingDominancePeriodValue;
        escalationThreshold = escalationThresholdValue;

        _request = Request({
            requester: requester,
            reward: reward,
            bondAmount: bondAmount,
            description: description,
            state: RequestState.Initialized,
            createdAt: uint64(block.timestamp)
        });

        emit RequestInitializedSingle(requester, reward, bondAmount, description);
    }

    // --------------------------- Core Functions ---------------------------

    /// @inheritdoc IPolyOracleSingle
    function propose(bytes calldata result) external nonReentrant {
        if (_request.state != RequestState.Initialized) {
            revert InvalidStateSingle(_request.state, RequestState.Initialized);
        }

        // Transfer bond from proposer
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), _request.bondAmount);

        uint64 livenessEndsAt = uint64(block.timestamp) + livenessPeriod;

        _proposal = Proposal({
            proposer: msg.sender, result: result, proposedAt: uint64(block.timestamp), livenessEndsAt: livenessEndsAt
        });

        _request.state = RequestState.Proposed;

        emit ProposalSubmittedSingle(msg.sender, result, livenessEndsAt);
    }

    /// @inheritdoc IPolyOracleSingle
    function dispute() external nonReentrant {
        if (_request.state != RequestState.Proposed) {
            revert InvalidStateSingle(_request.state, RequestState.Proposed);
        }

        if (block.timestamp >= _proposal.livenessEndsAt) {
            revert LivenessPeriodEndedSingle();
        }

        // Transfer bond from disputer
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), _request.bondAmount);

        _dispute = Dispute({
            disputer: msg.sender,
            disputedAt: uint64(block.timestamp),
            proposerStake: 0,
            disputerStake: 0,
            dominanceStartedAt: 0,
            proposerWasDominant: false,
            outcome: DisputeOutcome.None
        });

        _request.state = RequestState.Disputed;

        emit DisputeRaisedSingle(msg.sender);
    }

    /// @inheritdoc IPolyOracleSingle
    function vote(bool forProposer, uint256 amount) external nonReentrant {
        if (_request.state != RequestState.Disputed) {
            revert InvalidStateSingle(_request.state, RequestState.Disputed);
        }

        if (amount == 0) revert ZeroAmount();

        // Transfer stake from voter
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);

        VoterStake storage vs = _voterStakes[msg.sender];

        if (forProposer) {
            _dispute.proposerStake += amount;
            vs.proposerStake += amount;
        } else {
            _dispute.disputerStake += amount;
            vs.disputerStake += amount;
        }

        // Update dominance tracking
        (_dispute.dominanceStartedAt, _dispute.proposerWasDominant) = _updateDominance(
            _dispute.proposerStake, _dispute.disputerStake, _dispute.dominanceStartedAt, _dispute.proposerWasDominant
        );

        // Check escalation threshold
        uint256 totalStake = _dispute.proposerStake + _dispute.disputerStake;
        if (totalStake >= escalationThreshold) {
            _request.state = RequestState.Escalated;
            emit RequestEscalatedSingle(totalStake);
        }

        emit VoteStakedSingle(msg.sender, forProposer, amount);
    }

    /// @inheritdoc IPolyOracleSingle
    function resolveUndisputed() external nonReentrant {
        if (_request.state != RequestState.Proposed) {
            revert InvalidStateSingle(_request.state, RequestState.Proposed);
        }

        if (block.timestamp < _proposal.livenessEndsAt) {
            revert LivenessPeriodNotEndedSingle(_proposal.livenessEndsAt);
        }

        _request.state = RequestState.Resolved;
        _finalResult = _proposal.result;

        // Create dispute record for consistent outcome tracking
        _dispute.outcome = DisputeOutcome.ProposerWins;

        // Proposer gets reward + bond back
        uint256 payout = _request.reward + _request.bondAmount;
        IERC20(usdc).safeTransfer(_proposal.proposer, payout);

        emit RequestResolvedSingle(DisputeOutcome.ProposerWins, _proposal.result);
    }

    /// @inheritdoc IPolyOracleSingle
    function resolveDispute() external nonReentrant {
        if (_request.state != RequestState.Disputed) {
            revert InvalidStateSingle(_request.state, RequestState.Disputed);
        }

        // Check dominance condition
        (bool hasDominance, bool proposerDominant) = _checkDominance(_dispute.proposerStake, _dispute.disputerStake);
        if (!hasDominance) {
            revert NoDominanceSingle();
        }

        // Check duration requirement
        if (_dispute.dominanceStartedAt == 0 || block.timestamp < _dispute.dominanceStartedAt + votingDominancePeriod) {
            revert DominancePeriodNotMetSingle();
        }

        _request.state = RequestState.Resolved;

        if (proposerDominant) {
            _dispute.outcome = DisputeOutcome.ProposerWins;
            _finalResult = _proposal.result;

            // Proposer gets: reward + their bond + disputer's bond
            uint256 proposerPayout = _request.reward + (_request.bondAmount * 2);
            IERC20(usdc).safeTransfer(_proposal.proposer, proposerPayout);

            emit RequestResolvedSingle(DisputeOutcome.ProposerWins, _proposal.result);
        } else {
            _dispute.outcome = DisputeOutcome.DisputerWins;

            // Disputer gets: reward + proposer's bond + their bond back
            uint256 disputerPayout = _request.reward + (_request.bondAmount * 2);
            IERC20(usdc).safeTransfer(_dispute.disputer, disputerPayout);

            emit RequestResolvedSingle(DisputeOutcome.DisputerWins, "");
        }
    }

    /// @inheritdoc IPolyOracleSingle
    function adminResolve(bool proposerWins, bytes calldata result) external onlyFactoryAdmin nonReentrant {
        if (_request.state != RequestState.Escalated) {
            revert InvalidStateSingle(_request.state, RequestState.Escalated);
        }

        _request.state = RequestState.Resolved;
        _finalResult = result;

        if (proposerWins) {
            _dispute.outcome = DisputeOutcome.ProposerWins;
            uint256 proposerPayout = _request.reward + (_request.bondAmount * 2);
            IERC20(usdc).safeTransfer(_proposal.proposer, proposerPayout);
            emit RequestResolvedSingle(DisputeOutcome.ProposerWins, result);
        } else {
            _dispute.outcome = DisputeOutcome.DisputerWins;
            uint256 disputerPayout = _request.reward + (_request.bondAmount * 2);
            IERC20(usdc).safeTransfer(_dispute.disputer, disputerPayout);
            emit RequestResolvedSingle(DisputeOutcome.DisputerWins, result);
        }
    }

    /// @inheritdoc IPolyOracleSingle
    function claimWinnings() external nonReentrant {
        if (_request.state != RequestState.Resolved) {
            revert InvalidStateSingle(_request.state, RequestState.Resolved);
        }

        VoterStake storage vs = _voterStakes[msg.sender];

        if (vs.claimed) revert AlreadyClaimed();

        uint256 payout;
        if (_dispute.outcome == DisputeOutcome.ProposerWins) {
            if (vs.proposerStake == 0) revert NothingToClaim();
            payout = _calculatePayout(vs.proposerStake, _dispute.proposerStake, _dispute.disputerStake);
        } else if (_dispute.outcome == DisputeOutcome.DisputerWins) {
            if (vs.disputerStake == 0) revert NothingToClaim();
            payout = _calculatePayout(vs.disputerStake, _dispute.disputerStake, _dispute.proposerStake);
        } else {
            revert NothingToClaim();
        }

        vs.claimed = true;
        IERC20(usdc).safeTransfer(msg.sender, payout);

        emit RewardsClaimedSingle(msg.sender, payout);
    }

    // --------------------------- View Functions ---------------------------

    /// @inheritdoc IPolyOracleSingle
    function getResult() external view returns (bytes memory) {
        if (_request.state != RequestState.Resolved) {
            revert InvalidStateSingle(_request.state, RequestState.Resolved);
        }
        return _finalResult;
    }

    /// @inheritdoc IPolyOracleSingle
    function getRequest()
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
        return (
            _request.requester,
            _request.reward,
            _request.bondAmount,
            _request.description,
            _request.state,
            _request.createdAt
        );
    }

    /// @inheritdoc IPolyOracleSingle
    function getProposal()
        external
        view
        returns (address proposer, bytes memory result, uint64 proposedAt, uint64 livenessEndsAt)
    {
        return (_proposal.proposer, _proposal.result, _proposal.proposedAt, _proposal.livenessEndsAt);
    }

    /// @inheritdoc IPolyOracleSingle
    function getDispute()
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
        return (
            _dispute.disputer,
            _dispute.disputedAt,
            _dispute.proposerStake,
            _dispute.disputerStake,
            _dispute.dominanceStartedAt,
            _dispute.proposerWasDominant,
            _dispute.outcome
        );
    }

    /// @inheritdoc IPolyOracleSingle
    function getVoterStake(address voter)
        external
        view
        returns (uint256 proposerStake, uint256 disputerStake, bool claimed)
    {
        VoterStake storage vs = _voterStakes[voter];
        return (vs.proposerStake, vs.disputerStake, vs.claimed);
    }

    /// @inheritdoc IPolyOracleSingle
    function canResolveDispute() external view returns (bool canResolve, string memory reason) {
        if (_request.state != RequestState.Disputed) {
            return (false, "Not in disputed state");
        }

        (bool hasDominance,) = _checkDominance(_dispute.proposerStake, _dispute.disputerStake);
        if (!hasDominance) {
            return (false, "No side has 2x dominance");
        }

        if (_dispute.dominanceStartedAt == 0) {
            return (false, "Dominance not tracked");
        }

        if (block.timestamp < _dispute.dominanceStartedAt + votingDominancePeriod) {
            return (false, "Dominance period not met");
        }

        return (true, "Can resolve");
    }

    // --------------------------- Internal Functions ---------------------------

    /// @notice Check if one side has achieved 2x dominance over the other
    function _checkDominance(uint256 _proposerStake, uint256 _disputerStake)
        internal
        pure
        returns (bool hasDominance, bool proposerDominant)
    {
        if (_proposerStake > _disputerStake * 2) {
            return (true, true);
        }
        if (_disputerStake > _proposerStake * 2) {
            return (true, false);
        }
        return (false, false);
    }

    /// @notice Update dominance tracking after a vote
    function _updateDominance(
        uint256 _proposerStake,
        uint256 _disputerStake,
        uint64 _currentDominanceStartedAt,
        bool _currentProposerWasDominant
    ) internal view returns (uint64 newDominanceStartedAt, bool newProposerWasDominant) {
        (bool hasDominance, bool proposerDominant) = _checkDominance(_proposerStake, _disputerStake);

        if (!hasDominance) {
            return (0, false);
        }

        if (_currentDominanceStartedAt == 0) {
            return (uint64(block.timestamp), proposerDominant);
        } else if (_currentProposerWasDominant != proposerDominant) {
            return (uint64(block.timestamp), proposerDominant);
        }

        return (_currentDominanceStartedAt, _currentProposerWasDominant);
    }

    /// @notice Calculate payout for a voter on the winning side
    function _calculatePayout(uint256 _voterStake, uint256 _winnerPool, uint256 _loserPool)
        internal
        pure
        returns (uint256 payout)
    {
        if (_winnerPool > 0) {
            payout = _voterStake + (_voterStake * _loserPool / _winnerPool);
        } else {
            payout = _voterStake;
        }
    }
}
