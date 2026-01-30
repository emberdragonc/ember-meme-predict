// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { MemePrediction } from "../contracts/MemePrediction.sol";

contract DeployScript is Script {
    // FeeSplitter addresses
    address constant FEE_SPLITTER_TESTNET = address(0); // TODO: Deploy FeeSplitter to testnet
    address constant FEE_SPLITTER_MAINNET = 0x6db5060318cA3A51d9fb924976c85fcFFaF43EAC;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        bool isMainnet = block.chainid == 8453;
        
        // SAFETY CHECK: Require explicit confirmation for mainnet
        if (isMainnet) {
            bool mainnetConfirmed = vm.envBool("MAINNET_CONFIRMED");
            require(mainnetConfirmed, "Set MAINNET_CONFIRMED=true to deploy to mainnet");
        }
        
        address feeRecipient = isMainnet ? FEE_SPLITTER_MAINNET : vm.envAddress("FEE_RECIPIENT");
        
        vm.startBroadcast(deployerPrivateKey);

        MemePrediction prediction = new MemePrediction(feeRecipient);
        
        console.log("================================================");
        console.log("MemePrediction deployed!");
        console.log("================================================");
        console.log("Chain ID:", block.chainid);
        console.log("Network:", isMainnet ? "BASE MAINNET" : "BASE SEPOLIA (testnet)");
        console.log("Contract:", address(prediction));
        console.log("Fee recipient:", feeRecipient);
        console.log("================================================");
        
        if (!isMainnet) {
            console.log("");
            console.log("NEXT STEPS:");
            console.log("1. Request audit from @clawditor");
            console.log("2. Wait for audit approval");
            console.log("3. THEN deploy to mainnet with MAINNET_CONFIRMED=true");
        }

        vm.stopBroadcast();
    }
}
