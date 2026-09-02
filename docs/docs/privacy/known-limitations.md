---
title: Known Limitations
sidebar_label: Known Limitations
---

# Known Limitations

Every limitation on this page is stated because it's real and currently true on this deployment — not as a hypothetical caveat. Where a limitation has since been addressed, that's noted too.

## Event-log balance reconstruction

Individual transaction amounts are public by necessity — a real on-chain token transfer can't hide its own amount. A patient observer who replays a wallet's full public history can sum those amounts into a reconstructed running collateral/debt balance, even though the contract itself never stores that running total anywhere. This is the single most important scope limit on the privacy guarantee — covered in full, with a live demonstration tool, in [Privacy Threat Model](./threat-model.md).

## Trusted setup: single-party phase 2

Each circuit's phase-2 (circuit-specific) Groth16 setup contribution is currently made by this project alone, even though phase-1 is anchored to a real multi-party public ceremony. Covered in full in [Trusted Setup](./trusted-setup.md).

## Shielded pool is a proof-of-concept, not integrated

`ShieldedPool.sol` and Circuit S (`shielded_spend.circom`) demonstrate the core mechanism a fully private transfer layer needs — depositing into a pooled, fungible set of notes and later spending one by proving membership without revealing which note, for an arbitrary amount. It is **not** wired into `VaultManager`, borrowing, repayment, or liquidation. Doing that is real future work: a shielded pool is a fundamentally different data model (spend-a-note vs. update-a-position), not a small patch to the existing vault contracts.

## Self-liquidation is scoped to one collateral asset and one debt asset

Circuit R (reveal) — used for voluntary self-liquidation — proves a commitment opens to exactly one collateral amount and one debt amount. A position holding two collateral assets simultaneously (say, both WETH and ZEN) cannot self-liquidate through this path even if its debt side is a single asset. This is a real scope limit on the circuit, not an incidental bug — extending it is a circuit change, not a contract fix.

## Backstop liquidation trusts a sanity-bounded, self-reported claim

The longer-window bonded backstop for abandoned positions (used only when a position is stale far longer than the ordinary liquidation window, and its owner never returns) takes the proposer's claimed collateral/debt amounts — typically reconstructed off-chain from that position's own public event history — and checks them only against a sanity bound on the asset's protocol-wide totals, backed by a bond sized off the same claim. It is not independently verified the way a Circuit R reveal is. This is an intentional trade-off for a rare, already-adversarial path, not an oversight — the bond is the actual deterrent, not proof-level correctness.

## Interest accrual only reconciles when debt is touched

A position's committed debt reflects interest accrued since its last deposit, withdrawal, borrow, or repayment involving that debt — reconciled via the protocol's shared interest index whenever one of those actions runs a proof. A position that only touches its collateral (deposits or withdraws collateral, never revisits its debt) can go a long time without its committed debt reflecting the interest that accrued on it in the background, and Circuit A's own health check doesn't yet separately account for that unclaimed, real-time accrual either. This is a known, deferred piece of work, not a silent gap — the interest itself isn't lost or miscounted, it's just not yet reflected in that position's own health proof until the position's debt side is next touched.

## PriceOracle governance is multisig-shaped, not yet multisig-secured

`PriceOracle`'s price-setting authority is a [`SimpleMultiSig`](https://github.com/Amthebest14/kryptos-finance/blob/main/contracts/src/SimpleMultiSig.sol) contract rather than a single externally-owned account — but on the current deployment it's configured 1-of-1, with the same single deployer key as sole owner. Honestly: this is not yet a real security improvement over a plain EOA, since one key controls execution either way. What it changes is the *infrastructure* — adding genuinely independent co-owners is now one `propose`/`approve` cycle away, not a `PriceOracle` redeploy.
