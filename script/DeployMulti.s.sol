// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import {PolyOracleMulti} from "../src/PolyOracleMulti.sol";

/// @title DeployMulti
/// @notice Deployment script for PolyOracleMulti
contract DeployMulti is Script, Config {
    function run() public {
        // Load deployment parameters from deployments.toml
        _loadConfig("./deployments.toml", true);

        console.log("Deploying to chain:", block.chainid);

        address usdc = config.get("usdc").toAddress();
        address admin = config.get("admin").toAddress();
        uint256 livenessPeriod = config.get("livenessPeriod").toUint256();
        uint256 votingDominancePeriod = config.get("votingDominancePeriod").toUint256();
        uint256 escalationThreshold = config.get("escalationThreshold").toUint256();

        // Override admin with deployer if placeholder
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        if (admin == address(0x1)) {
            admin = deployer;
        }

        console.log("Deploying PolyOracleMulti...");
        console.log("USDC:", usdc);
        console.log("Admin:", admin);
        console.log("Liveness Period:", livenessPeriod);
        console.log("Voting Dominance Period:", votingDominancePeriod);
        console.log("Escalation Threshold:", escalationThreshold);

        vm.startBroadcast(deployerPrivateKey);

        PolyOracleMulti oracle = new PolyOracleMulti(
            usdc, admin, uint32(livenessPeriod), uint32(votingDominancePeriod), escalationThreshold
        );

        console.log("PolyOracleMulti deployed to:", address(oracle));

        vm.stopBroadcast();

        // Save deployment address back to config
        config.set("polyOracleMulti", address(oracle));
        config.set("deployed_at", block.timestamp);
        config.set("deployer", vm.addr(deployerPrivateKey));

        // Verify deployment
        require(oracle.owner() == admin, "Owner not set correctly");
        require(address(oracle.USDC()) == usdc, "USDC not set correctly");
        require(oracle.LIVENESS_PERIOD() == livenessPeriod, "Liveness period not set correctly");
        require(oracle.VOTING_DOMINANCE_PERIOD() == votingDominancePeriod, "Voting dominance period not set correctly");
        require(oracle.ESCALATION_THRESHOLD() == escalationThreshold, "Escalation threshold not set correctly");

        console.log("Deployment verified successfully");
    }
}
