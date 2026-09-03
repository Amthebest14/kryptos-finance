// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {LiquidationHandler} from "../src/LiquidationHandler.sol";
import {ProofVerifierAdapter} from "../src/ProofVerifierAdapter.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Fixes a real bug found live: _submitCollateralTransition passed a
/// genuine 0 as checkpointIndex/currentIndex for any asset a position had
/// never borrowed/repaid — satisfied the OLD exact-equality interest check
/// trivially, but not the floor-division remainder-bound check from the
/// interest-proof fix (RedeployVaultFix), which needs checkpointIndex > 0 to
/// be satisfiable at all. Made every deposit/withdraw of a never-touched
/// asset fail to prove. See VaultManager._submitCollateralTransition's own
/// comment for the fix itself — no circuit or trusted-setup change needed,
/// this is a contract-only substitution (borrowIndex[asset], never 0 once
/// listed, in place of a genuine 0).
///
/// Touches VaultManager, so the same five contracts as the interest-proof
/// redeploy need fresh addresses again. Both real Groth16 verifier sets,
/// TransitionRevealAdapter, PriceOracle, InterestRateModel, and the
/// WETH/USDC/ZEN mock tokens are untouched and reused as-is.
contract RedeployCollateralIndexFix is Script {
    address constant HEALTH_VERIFIER = 0x2DF316eC6fbFED3a336871d7c0b11d1B64938E34;
    address constant TRANSITION_REVEAL_ADAPTER = 0x7E9cA610f84A2971E0D0576d7018196726fC3612;
    address constant PRICE_ORACLE = 0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5;
    address constant INTEREST_RATE_MODEL = 0x4049f156BCF0FD86eC93A7100c9006E3e49B2d63;
    address constant WETH = 0x239Ac78cAb8d5553BDC6737593824b06fd88CE47;
    address constant USDC = 0xe026E73C3aD539b6566d2A1A29A5d778e7AB7C9a;
    address constant ZEN = 0xe015F8ccacC72545b9CF457a610bfC75fFAB4ADd;

    function run() external {
        vm.startBroadcast();

        uint256 nonceNow = vm.getNonce(msg.sender);
        address predictedRegistry = vm.computeCreateAddress(msg.sender, nonceNow);
        address predictedAdapter = vm.computeCreateAddress(msg.sender, nonceNow + 1);
        address predictedVault = vm.computeCreateAddress(msg.sender, nonceNow + 2);
        address predictedZenStaking = vm.computeCreateAddress(msg.sender, nonceNow + 3);

        PositionRegistry registry = new PositionRegistry(predictedVault, predictedAdapter);
        require(address(registry) == predictedRegistry, "registry address prediction drifted");

        ProofVerifierAdapter adapter = new ProofVerifierAdapter(address(registry), HEALTH_VERIFIER, PRICE_ORACLE);
        require(address(adapter) == predictedAdapter, "adapter address prediction drifted");

        VaultManager vault =
            new VaultManager(address(registry), TRANSITION_REVEAL_ADAPTER, INTEREST_RATE_MODEL, predictedZenStaking);
        require(address(vault) == predictedVault, "vault address prediction drifted");

        ZenStaking zenStaking = new ZenStaking(ZEN, address(vault));
        require(address(zenStaking) == predictedZenStaking, "zenStaking address prediction drifted");

        LiquidationHandler handler =
            new LiquidationHandler(address(registry), address(vault), TRANSITION_REVEAL_ADAPTER);
        vault.setLiquidationHandler(address(handler));

        vault.listAsset(WETH);
        vault.listAsset(USDC);
        vault.listAsset(ZEN);

        MockERC20(USDC).mint(address(vault), 1_000_000e18);
        MockERC20(ZEN).mint(address(vault), 1_000_000e18);

        vm.stopBroadcast();

        console.log("PositionRegistry:    ", address(registry));
        console.log("ProofVerifierAdapter:", address(adapter));
        console.log("VaultManager:        ", address(vault));
        console.log("ZenStaking:          ", address(zenStaking));
        console.log("LiquidationHandler:  ", address(handler));
    }
}
