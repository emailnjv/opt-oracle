// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleTypes} from "./IPolyOracleTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IPolyOracleFactory
/// @notice Interface for the PolyOracle factory using EIP-1167 minimal proxy clones
interface IPolyOracleFactory is IPolyOracleTypes {
    // --------------------------- Events ---------------------------

    /// @notice Emitted when a new oracle clone is created
    event OracleCreated(address indexed oracle, address indexed requester, uint256 reward, uint256 bondAmount);

    /// @notice Emitted when default config is updated
    event DefaultConfigUpdated(Config oldConfig, Config newConfig);

    // --------------------------- Core Functions ---------------------------

    /// @notice Create a new oracle clone for a request
    /// @param reward The reward amount in USDC for the proposer
    /// @param bondAmount The bond amount required from proposer and disputer
    /// @param description Description of the data being requested
    /// @return oracle The address of the newly created oracle clone
    function createOracle(uint256 reward, uint256 bondAmount, bytes calldata description)
        external
        returns (address oracle);

    /// @notice Update the default configuration for new oracles (admin only)
    /// @param config The new default configuration
    function updateDefaultConfig(Config calldata config) external;

    // --------------------------- View Functions ---------------------------

    /// @notice Get the USDC token contract
    function USDC() external view returns (IERC20);

    /// @notice Get the implementation contract address
    function IMPLEMENTATION() external view returns (address);

    /// @notice Get the current default configuration
    function defaultConfig()
        external
        view
        returns (uint32 livenessPeriod, uint32 votingDominancePeriod, uint256 escalationThreshold);

    /// @notice Get the total number of oracles created
    function oracleCount() external view returns (uint256);

    /// @notice Get an oracle address by index
    /// @param index The index in the oracle list
    /// @return oracle The oracle address
    function getOracle(uint256 index) external view returns (address oracle);

    /// @notice Check if an address is a valid oracle created by this factory
    /// @param oracle The address to check
    /// @return isValid True if the address is a valid oracle
    function isOracle(address oracle) external view returns (bool isValid);
}
