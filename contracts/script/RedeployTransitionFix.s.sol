// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {LiquidationHandler} from "../src/LiquidationHandler.sol";
import {ProofVerifierAdapter} from "../src/ProofVerifierAdapter.sol";
import {TransitionRevealAdapter} from "../src/TransitionRevealAdapter.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {Groth16Verifier as TransitionGroth16Verifier} from "../src/TransitionVerifier.sol";

/// @notice Fixes a real bug found live, on a real repay: transition.circom's
/// interest check demanded interestAccrued divide out of
/// debt*indexDelta/checkpointIndex exactly, which real interest essentially
/// never does (checkpointIndex is a huge WAD-scaled value with no reason to
/// divide the product evenly) — failing on any borrow/repay with nonzero
/// elapsed time, i.e. normal use. See transition.circom's own comment for
/// the fix (a bounded-remainder floor-division check instead of exact
/// equality) and TransitionVerifier.sol's provenance header for the
/// regenerated trusted setup.
///
/// A new circuit means a new TransitionVerifier, which TransitionRevealAdapter
/// wires to immutably, which PositionRegistry/ProofVerifierAdapter/
/// VaultManager/LiquidationHandler all reference immutably in turn — the
/// same full cascade as RedeployVaultFix.s.sol, plus TransitionRevealAdapter
/// itself this time (reused as-is last time, since only VaultManager's own
/// Solidity changed then, not the circuit). RevealVerifier (Circuit R)
/// didn't change, so TransitionRevealAdapter's other half is reused as-is.
///
/// Reused as-is (untouched by this fix): HealthVerifier, RevealVerifier,
/// PriceOracle, InterestRateModel, and the WETH/USDC/ZEN mock tokens
/// themselves. ZenStaking is reused too, repointed via its own setVault()
/// rather than redeployed — the whole reason that setter exists.
contract RedeployTransitionFix is Script {
    // Reused as-is — untouched by this fix.
    address constant HEALTH_VERIFIER = 0x2DF316eC6fbFED3a336871d7c0b11d1B64938E34;
    address constant REVEAL_VERIFIER = 0xf17904Cdbe9E60F1B210B6f4CBa22da6D0ac40cB;
    address constant PRICE_ORACLE = 0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5;
    address constant INTEREST_RATE_MODEL = 0x4049f156BCF0FD86eC93A7100c9006E3e49B2d63;
    address constant ZEN_STAKING = 0x0b56986F8Ec05ba0b6da5956269cDA0c5BB9226E;
    address constant WETH = 0x239Ac78cAb8d5553BDC6737593824b06fd88CE47;
    address constant USDC = 0xe026E73C3aD539b6566d2A1A29A5d778e7AB7C9a;
    address constant ZEN = 0xe015F8ccacC72545b9CF457a610bfC75fFAB4ADd;

    function run() external {
        vm.startBroadcast();

        // TransitionVerifier is a plain, no-constructor-args deploy — no
        // prediction needed, it doesn't depend on anything else here.
        // TransitionRevealAdapter needs it plus the (unchanged) RevealVerifier,
        // and nothing needs TransitionRevealAdapter's address predicted in
        // advance either, so both go first, straightforwardly.
        TransitionGroth16Verifier transitionVerifier = new TransitionGroth16Verifier();
        TransitionRevealAdapter transitionRevealAdapter =
            new TransitionRevealAdapter(address(transitionVerifier), REVEAL_VERIFIER);

        // PositionRegistry needs ProofVerifierAdapter's and VaultManager's
        // future addresses up front; VaultManager needs ZenStaking's future
        // address too — but ZenStaking is reused here (repointed via
        // setVault below), not redeployed, so only registry/adapter/vault
        // need predicting, same three-way dance as RedeployVaultFix.s.sol.
        uint256 nonceNow = vm.getNonce(msg.sender);
        address predictedRegistry = vm.computeCreateAddress(msg.sender, nonceNow);
        address predictedAdapter = vm.computeCreateAddress(msg.sender, nonceNow + 1);
        address predictedVault = vm.computeCreateAddress(msg.sender, nonceNow + 2);

        PositionRegistry registry = new PositionRegistry(predictedVault, predictedAdapter);
        require(address(registry) == predictedRegistry, "registry address prediction drifted");

        ProofVerifierAdapter adapter = new ProofVerifierAdapter(address(registry), HEALTH_VERIFIER, PRICE_ORACLE);
        require(address(adapter) == predictedAdapter, "adapter address prediction drifted");
        require(registry.proofVerifier() == address(adapter), "registry wired to wrong verifier");

        VaultManager vault = new VaultManager(
            address(registry), address(transitionRevealAdapter), INTEREST_RATE_MODEL, ZEN_STAKING
        );
        require(address(vault) == predictedVault, "vault address prediction drifted");

        LiquidationHandler handler =
            new LiquidationHandler(address(registry), address(vault), address(transitionRevealAdapter));
        vault.setLiquidationHandler(address(handler));

        // The one owner-gated repoint this whole redeploy actually needs —
        // ZenStaking itself stays put, existing stakes/rewards carry over.
        ZenStaking(ZEN_STAKING).setVault(address(vault));

        vault.listAsset(WETH);
        vault.listAsset(USDC);
        vault.listAsset(ZEN);

        // Fresh vault, fresh liquidity — reused tokens, but this specific
        // vault address has never held any of them.
        MockERC20(USDC).mint(address(vault), 1_000_000e18);
        MockERC20(ZEN).mint(address(vault), 1_000_000e18);

        vm.stopBroadcast();

        console.log("TransitionVerifier:      ", address(transitionVerifier));
        console.log("TransitionRevealAdapter: ", address(transitionRevealAdapter));
        console.log("PositionRegistry:        ", address(registry));
        console.log("ProofVerifierAdapter:    ", address(adapter));
        console.log("VaultManager:            ", address(vault));
        console.log("LiquidationHandler:      ", address(handler));
        console.log("(reused, repointed) ZenStaking:  ", ZEN_STAKING);
        console.log("(reused) HealthVerifier:         ", HEALTH_VERIFIER);
        console.log("(reused) RevealVerifier:         ", REVEAL_VERIFIER);
        console.log("(reused) PriceOracle:            ", PRICE_ORACLE);
        console.log("(reused) InterestRateModel:      ", INTEREST_RATE_MODEL);
        console.log("(reused) WETH/USDC/ZEN:          ", WETH, USDC, ZEN);
    }
}
