// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleTypes} from "../interfaces/IPolyOracleTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PolyOracleBase
/// @notice Abstract base contract for PolyOracleMulti with immutable configuration
/// @dev Contains shared logic for dominance checking, payout calculation, and config validation
abstract contract PolyOracleBase is IPolyOracleTypes, ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    // --------------------------- Immutables ---------------------------

    /// @notice The USDC token used for bonds, rewards, and stakes
    IERC20 public immutable USDC;

    /// @notice Duration a proposal must remain undisputed before it can be resolved
    uint32 public immutable LIVENESS_PERIOD;

    /// @notice Duration one side must maintain 2x dominance for dispute resolution
    uint32 public immutable VOTING_DOMINANCE_PERIOD;

    /// @notice Total stake threshold that triggers escalation to admin resolution
    uint256 public immutable ESCALATION_THRESHOLD;

    // --------------------------- Constructor ---------------------------

    /// @notice Initialize the oracle with immutable configuration
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
    ) Ownable(admin) {
        if (usdc == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (livenessPeriod == 0) revert InvalidConfig();
        if (votingDominancePeriod == 0) revert InvalidConfig();
        if (escalationThreshold == 0) revert InvalidConfig();

        USDC = IERC20(usdc);
        LIVENESS_PERIOD = livenessPeriod;
        VOTING_DOMINANCE_PERIOD = votingDominancePeriod;
        ESCALATION_THRESHOLD = escalationThreshold;
    }

    // --------------------------- Internal Functions ---------------------------

    /// @notice Check if one side has achieved 2x dominance over the other
    /// @param proposerStake Total stake for proposer
    /// @param disputeStake Total stake for disputer
    /// @return hasDominance True if one side has 2x dominance
    /// @return proposerDominant True if proposer is the dominant side
    function _checkDominance(uint256 proposerStake, uint256 disputeStake)
        internal
        pure
        returns (bool hasDominance, bool proposerDominant)
    {
        if (proposerStake > disputeStake * 2) {
            return (true, true);
        }
        if (disputeStake > proposerStake * 2) {
            return (true, false);
        }
        return (false, false);
    }

    /// @notice Update dominance tracking after a vote
    /// @param _proposerStake Total stake for proposer
    /// @param _disputerStake Total stake for disputer
    /// @param _currentDominanceStartedAt Current dominance start timestamp
    /// @param _currentProposerWasDominant Whether proposer was previously dominant
    /// @return newDominanceStartedAt Updated dominance start timestamp
    /// @return newProposerWasDominant Updated dominant side
    function _updateDominance(
        uint256 _proposerStake,
        uint256 _disputerStake,
        uint64 _currentDominanceStartedAt,
        bool _currentProposerWasDominant
    ) internal view returns (uint64 newDominanceStartedAt, bool newProposerWasDominant) {
        (bool hasDominance, bool proposerDominant) = _checkDominance(_proposerStake, _disputerStake);

        if (!hasDominance) {
            // No dominance - reset tracking
            return (0, false);
        }

        // Check if dominance just started or switched sides
        if (_currentDominanceStartedAt == 0) {
            // Dominance just achieved
            return (uint64(block.timestamp), proposerDominant);
        } else if (_currentProposerWasDominant != proposerDominant) {
            // Dominant side switched - reset the timer
            return (uint64(block.timestamp), proposerDominant);
        }

        // Same side still dominant, keep existing timestamp
        return (_currentDominanceStartedAt, _currentProposerWasDominant);
    }

    /// @notice Calculate payout for a voter on the winning side
    /// @param _voterStake The voter's stake on the winning side
    /// @param _winnerPool Total stake of the winning side
    /// @param _loserPool Total stake of the losing side
    /// @return payout The calculated payout amount
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
