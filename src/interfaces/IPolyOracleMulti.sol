// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleTypes} from "./IPolyOracleTypes.sol";

/// @title IPolyOracleMulti
/// @notice Interface for the multi-request PolyOracle contract
interface IPolyOracleMulti is IPolyOracleTypes {
    // --------------------------- Core Functions ---------------------------

    /// @notice Initialize a new oracle request
    /// @param reward The reward amount in USDC for the proposer
    /// @param bond The bond amount required from proposer and disputer
    /// @param description Description of the data being requested
    /// @return requestId The unique identifier for this request
    function initializeRequest(uint256 reward, uint256 bond, bytes memory description)
        external
        returns (bytes32 requestId);

    /// @notice Submit a proposed result for a request
    /// @param requestId The request to propose for
    /// @param result The proposed result bytes
    function propose(bytes32 requestId, bytes calldata result) external;

    /// @notice Dispute an existing proposal
    /// @param requestId The request with the proposal to dispute
    function dispute(bytes32 requestId) external;

    /// @notice Stake USDC to support either proposer or disputer
    /// @param requestId The disputed request
    /// @param forProposer True to support proposer, false to support disputer
    /// @param amount Amount of USDC to stake
    function vote(bytes32 requestId, bool forProposer, uint256 amount) external;

    /// @notice Resolve a proposal that passed liveness without dispute
    /// @param requestId The request to resolve
    function resolveUndisputed(bytes32 requestId) external;

    /// @notice Resolve a dispute where one side achieved 2x dominance for required duration
    /// @param requestId The request to resolve
    function resolveDispute(bytes32 requestId) external;

    /// @notice Admin resolves an escalated dispute
    /// @param requestId The escalated request
    /// @param proposerWins True if proposer should win
    /// @param result Final result to store
    function adminResolve(bytes32 requestId, bool proposerWins, bytes calldata result) external;

    /// @notice Claim voting winnings from a resolved dispute
    /// @param requestId The resolved request
    function claimWinnings(bytes32 requestId) external;

    // --------------------------- View Functions ---------------------------

    /// @notice Get the current request nonce
    function requestNonce() external view returns (uint256);

    /// @notice Get the final result for a resolved request
    /// @param requestId The request ID
    /// @return result The final result bytes
    function getResult(bytes32 requestId) external view returns (bytes memory result);

    /// @notice Get request info
    /// @param requestId The request ID
    /// @return requester The address that created the request
    /// @return reward The reward amount
    /// @return bondAmount The bond amount required
    /// @return description The request description
    /// @return state The current request state
    /// @return createdAt The timestamp when the request was created
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
        );

    /// @notice Get proposal info
    /// @param requestId The request ID
    /// @return proposer The address that submitted the proposal
    /// @return result The proposed result
    /// @return proposedAt The timestamp when proposed
    /// @return livenessEndsAt The timestamp when liveness period ends
    function getProposal(bytes32 requestId)
        external
        view
        returns (address proposer, bytes memory result, uint64 proposedAt, uint64 livenessEndsAt);

    /// @notice Get dispute info
    /// @param requestId The request ID
    /// @return disputer The address that raised the dispute
    /// @return disputedAt The timestamp when disputed
    /// @return proposerStake Total stake supporting the proposer
    /// @return disputerStake Total stake supporting the disputer
    /// @return dominanceStartedAt When current dominance began
    /// @return proposerWasDominant Whether proposer side is dominant
    /// @return outcome The dispute outcome
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
        );

    /// @notice Get voter stake info
    /// @param requestId The request ID
    /// @param voter The voter address
    /// @return proposerStake Amount staked for proposer
    /// @return disputerStake Amount staked for disputer
    /// @return claimed Whether winnings have been claimed
    function getVoterStake(bytes32 requestId, address voter)
        external
        view
        returns (uint256 proposerStake, uint256 disputerStake, bool claimed);

    /// @notice Check if dispute can be resolved
    /// @param requestId The request ID
    /// @return canResolve Whether the dispute can be resolved
    /// @return reason Explanation of the result
    function canResolveDispute(bytes32 requestId) external view returns (bool canResolve, string memory reason);
}
