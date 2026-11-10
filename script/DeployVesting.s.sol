// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

/// forge script script/DeployVesting.s.sol --rpc-url $RPC_URL --account deployer --broadcast
/// Variables : TOKEN (adresse du jeton ERC-20), OWNER (propriétaire du contrat).
contract DeployVesting is Script {
    function run() external returns (TokenVesting vesting) {
        IERC20 token = IERC20(vm.envAddress("TOKEN"));
        address owner = vm.envAddress("OWNER");
        vm.startBroadcast();
        vesting = new TokenVesting(token, owner);
        vm.stopBroadcast();
        console.log("TokenVesting:", address(vesting));
    }
}
