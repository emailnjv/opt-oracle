// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPolyOracleFactory} from "./interfaces/IPolyOracleFactory.sol";
import {IPolyOracleSingle} from "./interfaces/IPolyOracleSingle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title PolyOracleFactory
/// @notice Factory for creating PolyOracleSingle instances using EIP-1167 minimal proxy clones
/// @dev Each clone's address serves as its unique identifier
contract PolyOracleFactory is IPolyOracleFactory, Ownable2Step {
    using SafeERC20 for IERC20;

    // --------------------------- Immutables ---------------------------

    /// @notice The USDC token used for bonds, rewards, and stakes
    IERC20 public immutable USDC;

    /// @notice The PolyOracleSingle implementation contract
    address public immutable IMPLEMENTATION;

    // --------------------------- Storage ---------------------------

    /// @notice Default configuration for new oracles
    Config internal _defaultConfig;

    /// @notice List of all created oracle addresses
    address[] internal _oracleList;

    /// @notice Mapping to check if an address is a valid oracle
    mapping(address => bool) internal _isOracle;

    // --------------------------- Constructor ---------------------------

    /// @notice Initialize the factory
    /// @param usdc The USDC token address
    /// @param admin The admin address (owner)
    /// @param implementation The PolyOracleSingle implementation address
    /// @param config The default configuration for new oracles
    constructor(address usdc, address admin, address implementation, Config memory config) Ownable(admin) {
        if (usdc == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (implementation == address(0)) revert ZeroAddress();
        if (config.livenessPeriod == 0) revert InvalidConfig();
        if (config.votingDominancePeriod == 0) revert InvalidConfig();
        if (config.escalationThreshold == 0) revert InvalidConfig();

        USDC = IERC20(usdc);
        IMPLEMENTATION = implementation;
        _defaultConfig = config;
    }

    // --------------------------- Core Functions ---------------------------

    /// @inheritdoc IPolyOracleFactory
    function createOracle(uint256 reward, uint256 bondAmount, bytes calldata description)
        external
        returns (address oracle)
    {
        if (reward == 0) revert ZeroAmount();
        if (bondAmount == 0) revert ZeroAmount();

        // Create clone
        oracle = Clones.clone(IMPLEMENTATION);

        // Transfer reward from requester to clone
        USDC.safeTransferFrom(msg.sender, oracle, reward);

        // Initialize clone
        IPolyOracleSingle(oracle)
            .initialize(
                address(USDC),
                address(this),
                msg.sender,
                reward,
                bondAmount,
                description,
                _defaultConfig.livenessPeriod,
                _defaultConfig.votingDominancePeriod,
                _defaultConfig.escalationThreshold
            );

        // Track oracle
        _oracleList.push(oracle);
        _isOracle[oracle] = true;

        emit OracleCreated(oracle, msg.sender, reward, bondAmount);
    }

    /// @inheritdoc IPolyOracleFactory
    function updateDefaultConfig(Config calldata config) external onlyOwner {
        if (config.livenessPeriod == 0) revert InvalidConfig();
        if (config.votingDominancePeriod == 0) revert InvalidConfig();
        if (config.escalationThreshold == 0) revert InvalidConfig();

        Config memory oldConfig = _defaultConfig;
        _defaultConfig = config;

        emit DefaultConfigUpdated(oldConfig, config);
    }

    // --------------------------- View Functions ---------------------------

    /// @inheritdoc IPolyOracleFactory
    function defaultConfig()
        external
        view
        returns (uint32 livenessPeriod, uint32 votingDominancePeriod, uint256 escalationThreshold)
    {
        return (_defaultConfig.livenessPeriod, _defaultConfig.votingDominancePeriod, _defaultConfig.escalationThreshold);
    }

    /// @inheritdoc IPolyOracleFactory
    function oracleCount() external view returns (uint256) {
        return _oracleList.length;
    }

    /// @inheritdoc IPolyOracleFactory
    function getOracle(uint256 index) external view returns (address oracle) {
        return _oracleList[index];
    }

    /// @inheritdoc IPolyOracleFactory
    function isOracle(address oracle) external view returns (bool isValid) {
        return _isOracle[oracle];
    }
}
