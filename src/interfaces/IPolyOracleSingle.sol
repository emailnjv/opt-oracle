// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleTypes} from "./IPolyOracleTypes.sol";

/// @title IPolyOracleSingle
/// @notice Interface for single-request PolyOracle (deployed as EIP-1167 clone)
/// @dev Each clone handles exactly one oracle request - clone address serves as unique identifier
interface IPolyOracleSingle is IPolyOracleTypes {
    // --------------------------- Initialization ---------------------------

    /// @notice Initialize the oracle clone (called by factory)
    /// @param usdcAddress The USDC token address
    /// @param factoryAddress The factory contract address
    /// @param requester The address creating the request
    /// @param reward The reward amount in USDC
    /// @param bondAmount The bond amount required
    /// @param description Description of the data being requested
    /// @param livenessPeriodValue The liveness period in seconds
    /// @param votingDominancePeriodValue The voting dominance period in seconds
    /// @param escalationThresholdValue The escalation threshold in USDC
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
    ) external;

    // --------------------------- Core Functions ---------------------------

    /// @notice Submit a proposed result
    /// @param result The proposed result bytes
    function propose(bytes calldata result) external;

    /// @notice Dispute the existing proposal
    function dispute() external;

    /// @notice Stake USDC to support either proposer or disputer
    /// @param forProposer True to support proposer, false to support disputer
    /// @param amount Amount of USDC to stake
    function vote(bool forProposer, uint256 amount) external;

    /// @notice Resolve a proposal that passed liveness without dispute
    function resolveUndisputed() external;

    /// @notice Resolve a dispute where one side achieved 2x dominance for required duration
    function resolveDispute() external;

    /// @notice Admin resolves an escalated dispute
    /// @param proposerWins True if proposer should win
    /// @param result Final result to store
    function adminResolve(bool proposerWins, bytes calldata result) external;

    /// @notice Claim voting winnings from a resolved dispute
    function claimWinnings() external;

    // --------------------------- View Functions ---------------------------

    /// @notice Get the USDC token address
    function usdc() external view returns (address);

    /// @notice Get the factory address
    function factory() external view returns (address);

    /// @notice Get the liveness period in seconds
    function livenessPeriod() external view returns (uint32);

    /// @notice Get the voting dominance period in seconds
    function votingDominancePeriod() external view returns (uint32);

    /// @notice Get the escalation threshold in USDC
    function escalationThreshold() external view returns (uint256);

    /// @notice Get the final result
    /// @return result The final result bytes
    function getResult() external view returns (bytes memory result);

    /// @notice Get request info
    /// @return requester The address that created the request
    /// @return reward The reward amount
    /// @return bondAmount The bond amount required
    /// @return description The request description
    /// @return state The current request state
    /// @return createdAt The timestamp when the request was created
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
        );

    /// @notice Get proposal info
    /// @return proposer The address that submitted the proposal
    /// @return result The proposed result
    /// @return proposedAt The timestamp when proposed
    /// @return livenessEndsAt The timestamp when liveness period ends
    function getProposal()
        external
        view
        returns (address proposer, bytes memory result, uint64 proposedAt, uint64 livenessEndsAt);

    /// @notice Get dispute info
    /// @return disputer The address that raised the dispute
    /// @return disputedAt The timestamp when disputed
    /// @return proposerStake Total stake supporting the proposer
    /// @return disputerStake Total stake supporting the disputer
    /// @return dominanceStartedAt When current dominance began
    /// @return proposerWasDominant Whether proposer side is dominant
    /// @return outcome The dispute outcome
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
        );

    /// @notice Get voter stake info
    /// @param voter The voter address
    /// @return proposerStake Amount staked for proposer
    /// @return disputerStake Amount staked for disputer
    /// @return claimed Whether winnings have been claimed
    function getVoterStake(address voter)
        external
        view
        returns (uint256 proposerStake, uint256 disputerStake, bool claimed);

    /// @notice Check if dispute can be resolved
    /// @return canResolve Whether the dispute can be resolved
    /// @return reason Explanation of the result
    function canResolveDispute() external view returns (bool canResolve, string memory reason);
}
