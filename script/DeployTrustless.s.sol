// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { MemePredictionTrustless } from "../contracts/MemePredictionTrustless.sol";

/**
 * @title DeployTrustless
 * @notice Deploys the trustless MemePrediction contract with Pyth oracle integration
 * 
 * Pyth Network Contract Addresses:
 * - Base Mainnet: 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a
 * - Base Sepolia: 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729
 * 
 * Run: forge script script/DeployTrustless.s.sol:DeployTrustless --rpc-url base_sepolia --broadcast --verify
 */
contract DeployTrustless is Script {
    // Pyth contract addresses
    address constant PYTH_BASE_MAINNET = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;
    address constant PYTH_BASE_SEPOLIA = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("EMBER_WALLET_KEY");
        address feeRecipient = vm.addr(deployerPrivateKey); // Use deployer as fee recipient for now
        
        // Detect network - use Base Sepolia Pyth by default
        address pythAddress = PYTH_BASE_SEPOLIA;
        
        console.log("Deploying MemePredictionTrustless...");
        console.log("Pyth Oracle:", pythAddress);
        console.log("Fee Recipient:", feeRecipient);

        vm.startBroadcast(deployerPrivateKey);

        MemePredictionTrustless prediction = new MemePredictionTrustless(
            pythAddress,
            feeRecipient
        );

        vm.stopBroadcast();

        console.log("MemePredictionTrustless deployed at:", address(prediction));
        console.log("");
        console.log("=== PYTH PRICE FEED IDs (Base) ===");
        console.log("PEPE/USD: 0xd69731a2e74ac1ce884fc3890f7ee324b6deb66147055249568869ed700882e4");
        console.log("DOGE/USD: 0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c");
        console.log("SHIB/USD: 0xf0d57deca57b3da2fe63a493f4c25925fdfd8edf834b20f93e1f84dbd1504d4a");
        console.log("WIF/USD:  0x4ca4beeca86f0d164160323817a4e42b10010a724c2217c6ee41b54cd4cc61fc");
        console.log("BONK/USD: 0x72b021217ca3fe68922a19aaf990109cb9d84e9ad004b4d2025ad6f529314419");
        console.log("");
        console.log("Example: createRound(['PEPE', 'DOGE'], [0xd697..., 0xdcef...], 86400)");
    }
}
