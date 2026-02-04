// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

/// @title DeployMockUSDC
/// @notice Deployment script for MockUSDC token
/// @dev This deploys a mock USDC token for testing purposes and updates the deployments.toml file
contract DeployMockUSDC is Script, Config {
    function run() public {
        // Load config with write-back enabled
        _loadConfig("./deployments.toml", true);

        console.log("Deploying MockUSDC to chain:", block.chainid);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockUSDC
        MockUSDC usdc = new MockUSDC();

        console.log("MockUSDC deployed to:", address(usdc));
        console.log("Name:", usdc.name());
        console.log("Symbol:", usdc.symbol());
        console.log("Decimals:", usdc.decimals());

        vm.stopBroadcast();

        // Save deployment address back to config
        config.set("usdc", address(usdc));
        config.set("mockUSDC_deployed_at", block.timestamp);
        config.set("mockUSDC_deployer", deployer);

        // Verify deployment
        require(usdc.decimals() == 6, "USDC decimals should be 6");
        require(keccak256(bytes(usdc.symbol())) == keccak256(bytes("USDC")), "Symbol should be USDC");

        console.log("\nMockUSDC deployment verified and saved to deployments.toml");
        console.log("You can now use this address in other deployment scripts");
    }
}
