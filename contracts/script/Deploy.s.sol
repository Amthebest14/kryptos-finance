// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {LiquidationHandler} from "../src/LiquidationHandler.sol";
import {ProofVerifierAdapter} from "../src/ProofVerifierAdapter.sol";
import {TransitionRevealAdapter} from "../src/TransitionRevealAdapter.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {Groth16Verifier} from "../src/HealthFactorVerifier.sol";
import {Groth16Verifier as TransitionGroth16Verifier} from "../src/TransitionVerifier.sol";
import {Groth16Verifier as RevealGroth16Verifier} from "../src/RevealVerifier.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Devnet/testnet deployment for manual testing (Anvil local or Horizen
/// Testnet). WETH/USDC/ZEN here are freshly-deployed mock tokens, not the real
/// bridged/canonical assets — not for mainnet.
///
/// Every proof gate in the system is backed by a real Groth16 verifier, no
/// mocks left in this path:
///   - ProofVerifierAdapter (Circuit A, health_factor.circom): gates
///     PositionRegistry.recordProof, the "Refresh proof" health-factor
///     check-in — a position can only refresh its liveness by proving it's
///     genuinely solvent, without revealing its numbers. Price/liqThreshold
///     now come from PriceOracle, not caller-supplied calldata (see
///     PriceOracle.sol — closes a real exploit, not just a privacy gap).
///   - TransitionRevealAdapter (Circuit T, transition.circom + Circuit R,
///     reveal.circom): gates VaultManager's deposit/withdraw/borrow/repay
///     transition checks and LiquidationHandler's liquidation reveal check —
///     a deposit/withdraw/borrow/repay can only update the sealed commitment
///     to a value cryptographically consistent with the public token amount
///     actually moved, and a liquidation can only seize/repay the amounts
///     the sealed commitment truly opens to.
///
/// InterestRateModel + ZenStaking: a real utilization-based rate curve, and
/// real ZEN staking that earns a share of accrued interest. Interest amounts
/// are no longer merely self-reported (gap #3's fix) — transition.circom now
/// checks a borrow/repay's claimed `interestAccrued` against the position's
/// own (private) old debt and VaultManager's own (public) borrowIndex ratio,
/// so a caller can no longer claim a wrong amount and still produce a valid
/// proof (see VaultManager.borrow's own comment, and ZenStaking.sol's top
/// comment for what's still a real, distinct limitation: this reconciliation
/// only happens when a position actually touches its debt).
///
/// `run()` is split into small internal steps (rather than one long function)
/// purely to keep each function's local-variable count low enough for solc's
/// legacy codegen — with everything inlined into one function, so many
/// simultaneously-live locals push it past the EVM's 16-slot stack addressing
/// limit ("stack too deep").
contract Deploy is Script {
    struct Verifiers {
        address health;
        address transition;
        address reveal;
        address transitionRevealAdapter;
        address interestRateModel;
        address priceOracle;
    }

    struct Tokens {
        address weth;
        address usdc;
        address zen;
    }

    function run() external {
        vm.startBroadcast();

        Verifiers memory v = _deployVerifiers();
        Tokens memory t = _deployTokens();
        (
            PositionRegistry registry,
            ProofVerifierAdapter adapter,
            VaultManager vault,
            ZenStaking zenStaking,
            LiquidationHandler handler
        ) = _deployCore(v, t.zen);
        _listAssetsAndSeed(vault, t);

        vm.stopBroadcast();

        console.log("Groth16Verifier (health):  ", v.health);
        console.log("ProofVerifierAdapter:      ", address(adapter));
        console.log("TransitionVerifier:        ", v.transition);
        console.log("RevealVerifier:            ", v.reveal);
        console.log("TransitionRevealAdapter:   ", v.transitionRevealAdapter);
        console.log("InterestRateModel:         ", v.interestRateModel);
        console.log("PriceOracle:               ", v.priceOracle);
        console.log("ZenStaking:                ", address(zenStaking));
        console.log("PositionRegistry:          ", address(registry));
        console.log("VaultManager:              ", address(vault));
        console.log("LiquidationHandler:        ", address(handler));
        console.log("WETH:                      ", t.weth);
        console.log("USDC:                      ", t.usdc);
        console.log("ZEN:                       ", t.zen);
    }

    function _deployVerifiers() private returns (Verifiers memory v) {
        v.health = address(new Groth16Verifier());
        v.transition = address(new TransitionGroth16Verifier());
        v.reveal = address(new RevealGroth16Verifier());
        v.transitionRevealAdapter = address(new TransitionRevealAdapter(v.transition, v.reveal));
        // Illustrative but reasonable kinked-curve parameters (WAD-scaled):
        // 0% base rate, 10%/year up to 80% utilization, then a steep 100%/year
        // jump slope beyond it to discourage draining a market dry.
        v.interestRateModel = address(new InterestRateModel(0, 0.1e18, 1e18, 0.8e18));

        // Seed values are real, not placeholders — pulled live moments before
        // this deploy from the same sources the frontend already displays:
        // Pyth's on-chain contract on Base mainnet for WETH ($2442.04) and
        // USDC ($0.9999), CoinGecko for ZEN ($5.29, no on-chain Pyth feed
        // exists for it — see PriceOracle.sol's own comment for why). Stale
        // the moment real market prices move; refreshing them post-deploy via
        // `setPrices()` is an owner operation, not something this script
        // itself keeps current.
        uint256[3] memory seedPrices = [uint256(2442043066), 999900, 5290000];
        uint256[3] memory seedLiqThresholds = [uint256(830000), 900000, 650000];
        v.priceOracle = address(new PriceOracle(seedPrices, seedLiqThresholds));
    }

    // Deployed before _deployCore because ZenStaking needs ZEN's real address
    // as an immutable constructor param, and _deployCore needs to predict
    // ZenStaking's own future address before VaultManager exists — easier to
    // reason about with tokens already real by that point.
    function _deployTokens() private returns (Tokens memory t) {
        t.weth = address(new MockERC20("Wrapped Ether", "WETH", 10 ether));
        t.usdc = address(new MockERC20("USD Coin", "USDC", 10_000 ether));
        t.zen = address(new MockERC20("Horizen", "ZEN", 10_000 ether));
    }

    // PositionRegistry needs the future addresses of both ProofVerifierAdapter
    // (its onlyVerifier gate) and VaultManager (its onlyVault gate) before either
    // exists, and VaultManager needs ZenStaking's future address before ZenStaking
    // exists (ZenStaking's own constructor takes VaultManager's real address
    // instead, since it deploys after) — predict all three from the current
    // nonce, then deploy in the exact order that makes those predictions land.
    function _deployCore(Verifiers memory v, address zenToken)
        private
        returns (
            PositionRegistry registry,
            ProofVerifierAdapter adapter,
            VaultManager vault,
            ZenStaking zenStaking,
            LiquidationHandler handler
        )
    {
        uint256 nonceNow = vm.getNonce(msg.sender);
        address predictedRegistry = vm.computeCreateAddress(msg.sender, nonceNow);
        address predictedAdapter = vm.computeCreateAddress(msg.sender, nonceNow + 1);
        address predictedVault = vm.computeCreateAddress(msg.sender, nonceNow + 2);
        address predictedZenStaking = vm.computeCreateAddress(msg.sender, nonceNow + 3);

        registry = new PositionRegistry(predictedVault, predictedAdapter);
        require(address(registry) == predictedRegistry, "registry address prediction drifted");

        adapter = new ProofVerifierAdapter(address(registry), v.health, v.priceOracle);
        require(address(adapter) == predictedAdapter, "adapter address prediction drifted");
        require(registry.proofVerifier() == address(adapter), "registry wired to wrong verifier");

        vault = new VaultManager(address(registry), v.transitionRevealAdapter, v.interestRateModel, predictedZenStaking);
        require(address(vault) == predictedVault, "vault address prediction drifted");

        zenStaking = new ZenStaking(zenToken, address(vault));
        require(address(zenStaking) == predictedZenStaking, "zenStaking address prediction drifted");

        handler = new LiquidationHandler(address(registry), address(vault), v.transitionRevealAdapter);
        vault.setLiquidationHandler(address(handler));
    }

    // Faucet drip amounts matching kryptos-frontend/src/lib/contracts.ts's
    // FAUCET_AMOUNTS — the on-chain contract is the source of truth for the
    // actual amount minted; the frontend constant is just a matching display
    // label. Seeds the deployer with test balances and the vault with
    // liquidity so borrow() works immediately.
    function _listAssetsAndSeed(VaultManager vault, Tokens memory t) private {
        vault.listAsset(t.weth);
        vault.listAsset(t.usdc);
        vault.listAsset(t.zen);

        MockERC20(t.weth).mint(msg.sender, 1_000 ether);
        MockERC20(t.usdc).mint(msg.sender, 1_000_000e18);
        MockERC20(t.zen).mint(msg.sender, 1_000_000e18);
        MockERC20(t.usdc).mint(address(vault), 1_000_000e18);
        MockERC20(t.zen).mint(address(vault), 1_000_000e18);
    }
}
