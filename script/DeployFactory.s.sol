// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import {PolyOracleFactory} from "../src/PolyOracleFactory.sol";
import {PolyOracleSingle} from "../src/PolyOracleSingle.sol";
import {IPolyOracleTypes} from "../src/interfaces/IPolyOracleTypes.sol";

/// @title DeployFactory
/// @notice Deployment script for PolyOracleFactory and PolyOracleSingle implementation
contract DeployFactory is Script, Config {
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

        IPolyOracleTypes.Config memory defaultConfig = IPolyOracleTypes.Config({
            livenessPeriod: uint32(livenessPeriod),
            votingDominancePeriod: uint32(votingDominancePeriod),
            escalationThreshold: escalationThreshold
        });

        console.log("Deploying PolyOracleSingle implementation...");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation first
        PolyOracleSingle implementation = new PolyOracleSingle();
        console.log("PolyOracleSingle implementation deployed to:", address(implementation));

        // Deploy factory with implementation
        console.log("Deploying PolyOracleFactory...");
        console.log("USDC:", usdc);
        console.log("Admin:", admin);
        console.log("Implementation:", address(implementation));
        console.log("Liveness Period:", livenessPeriod);
        console.log("Voting Dominance Period:", votingDominancePeriod);
        console.log("Escalation Threshold:", escalationThreshold);

        PolyOracleFactory factory = new PolyOracleFactory(usdc, admin, address(implementation), defaultConfig);

        console.log("PolyOracleFactory deployed to:", address(factory));

        vm.stopBroadcast();

        // Save deployment addresses back to config
        config.set("polyOracleSingleImplementation", address(implementation));
        config.set("polyOracleFactory", address(factory));
        config.set("deployed_at", block.timestamp);
        config.set("deployer", deployer);

        // Verify deployment
        require(factory.owner() == admin, "Owner not set correctly");
        require(address(factory.USDC()) == usdc, "USDC not set correctly");
        require(factory.IMPLEMENTATION() == address(implementation), "Implementation not set correctly");

        (uint256 lp, uint256 vdp, uint256 et) = factory.defaultConfig();
        require(lp == livenessPeriod, "Liveness period not set correctly");
        require(vdp == votingDominancePeriod, "Voting dominance period not set correctly");
        require(et == escalationThreshold, "Escalation threshold not set correctly");

        console.log("Deployment verified successfully");
    }
}
