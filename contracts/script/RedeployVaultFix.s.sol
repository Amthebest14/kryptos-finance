// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {LiquidationHandler} from "../src/LiquidationHandler.sol";
import {ProofVerifierAdapter} from "../src/ProofVerifierAdapter.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Fixes a real bug found live: seizeAndRepay() left a liquidated
/// wallet's `positionOf[owner].active` permanently true, sealed against a
/// plain keccak256 "closed" marker instead of a genuine Poseidon commitment —
/// meaning no transition proof could ever be built again, locking that
/// wallet out of VaultManager forever. See VaultManager.sol's own
/// seizeAndRepay comment for the fix itself.
///
/// Fixing it touches VaultManager, which PositionRegistry, ProofVerifierAdapter,
/// LiquidationHandler, and ZenStaking all reference immutably — all five need
/// fresh addresses. Everything else (both real Groth16 verifier sets,
/// TransitionRevealAdapter, PriceOracle, InterestRateModel, and the WETH/USDC/ZEN
/// mock tokens themselves) is untouched by this fix and reused as-is, so
/// existing wallet balances and faucet cooldowns carry over unaffected.
///
/// ZenStaking is the one real, one-time cost here: its old `vault` reference
/// was immutable, so it has to be redeployed too, orphaning any existing
/// stakes/rewards. ZenStaking.sol just gained an owner-gated `setVault()`
/// specifically so this is the last time that has to happen — a future
/// VaultManager fix can point the SAME ZenStaking at a new vault in place.
contract RedeployVaultFix is Script {
    // Reused as-is — untouched by this fix.
    address constant HEALTH_VERIFIER = 0x2DF316eC6fbFED3a336871d7c0b11d1B64938E34;
    address constant TRANSITION_REVEAL_ADAPTER = 0xbaC53287eCf23ac461742B2BC08AC5754664b14d;
    address constant PRICE_ORACLE = 0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5;
    address constant INTEREST_RATE_MODEL = 0x4049f156BCF0FD86eC93A7100c9006E3e49B2d63;
    address constant WETH = 0x239Ac78cAb8d5553BDC6737593824b06fd88CE47;
    address constant USDC = 0xe026E73C3aD539b6566d2A1A29A5d778e7AB7C9a;
    address constant ZEN = 0xe015F8ccacC72545b9CF457a610bfC75fFAB4ADd;

    function run() external {
        vm.startBroadcast();

        // PositionRegistry needs ProofVerifierAdapter's and VaultManager's
        // future addresses up front; VaultManager needs ZenStaking's future
        // address up front — predict all three from the current nonce, then
        // deploy in the exact order that makes those predictions land.
        uint256 nonceNow = vm.getNonce(msg.sender);
        address predictedRegistry = vm.computeCreateAddress(msg.sender, nonceNow);
        address predictedAdapter = vm.computeCreateAddress(msg.sender, nonceNow + 1);
        address predictedVault = vm.computeCreateAddress(msg.sender, nonceNow + 2);
        address predictedZenStaking = vm.computeCreateAddress(msg.sender, nonceNow + 3);

        PositionRegistry registry = new PositionRegistry(predictedVault, predictedAdapter);
        require(address(registry) == predictedRegistry, "registry address prediction drifted");

        ProofVerifierAdapter adapter = new ProofVerifierAdapter(address(registry), HEALTH_VERIFIER, PRICE_ORACLE);
        require(address(adapter) == predictedAdapter, "adapter address prediction drifted");
        require(registry.proofVerifier() == address(adapter), "registry wired to wrong verifier");

        VaultManager vault =
            new VaultManager(address(registry), TRANSITION_REVEAL_ADAPTER, INTEREST_RATE_MODEL, predictedZenStaking);
        require(address(vault) == predictedVault, "vault address prediction drifted");

        ZenStaking zenStaking = new ZenStaking(ZEN, address(vault));
        require(address(zenStaking) == predictedZenStaking, "zenStaking address prediction drifted");

        LiquidationHandler handler = new LiquidationHandler(address(registry), address(vault), TRANSITION_REVEAL_ADAPTER);
        vault.setLiquidationHandler(address(handler));

        vault.listAsset(WETH);
        vault.listAsset(USDC);
        vault.listAsset(ZEN);

        // Fresh vault, fresh liquidity — the token contracts are reused, but
        // this specific vault address has never held any of them.
        MockERC20(USDC).mint(address(vault), 1_000_000e18);
        MockERC20(ZEN).mint(address(vault), 1_000_000e18);

        vm.stopBroadcast();

        console.log("PositionRegistry:    ", address(registry));
        console.log("ProofVerifierAdapter:", address(adapter));
        console.log("VaultManager:        ", address(vault));
        console.log("ZenStaking:          ", address(zenStaking));
        console.log("LiquidationHandler:  ", address(handler));
        console.log("(reused) HealthVerifier:          ", HEALTH_VERIFIER);
        console.log("(reused) TransitionRevealAdapter: ", TRANSITION_REVEAL_ADAPTER);
        console.log("(reused) PriceOracle:             ", PRICE_ORACLE);
        console.log("(reused) InterestRateModel:       ", INTEREST_RATE_MODEL);
        console.log("(reused) WETH/USDC/ZEN:           ", WETH, USDC, ZEN);
    }
}
