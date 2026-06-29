//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployWhitelist } from "./DeployWhitelist.s.sol";
import { DeployStaking } from "./DeployStaking.s.sol";
import { DeployOptimistic } from "./DeployOptimistic.s.sol";

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    function run() external {
        // Deploys all your contracts sequentially
        // Add new deployments here when needed

        DeployWhitelist deployWhitelist = new DeployWhitelist();
        deployWhitelist.run();

        DeployStaking deployStaking = new DeployStaking();
        deployStaking.run();

        DeployOptimistic deployOptimistic = new DeployOptimistic();
        deployOptimistic.run();

        // Deploy another contract
        // DeployMyContract myContract = new DeployMyContract();
        // myContract.run();
    }
}
