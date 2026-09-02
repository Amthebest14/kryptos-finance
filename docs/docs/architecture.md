---
title: Architecture
sidebar_label: Architecture
---

# Architecture

Kryptos is three cooperating pieces: **contracts** that hold funds and verify proofs, **circuits** that define what "a valid state transition" means, and a **frontend** that generates proofs client-side against your own private data. Nothing about your position's contents ever leaves the browser except a proof.

## The three layers

```
┌─────────────────────────────────────────────────────────┐
│  Frontend (React + Vite)                                 │
│  Holds your collateral/debt/salt in browser storage only. │
│  Generates Groth16 proofs client-side via snarkjs.        │
└──────────────────────────┬─────────────────────────────┘
                            │ tx + proof
┌──────────────────────────▼─────────────────────────────┐
│  Contracts (Solidity, Horizen Testnet)                    │
│  VaultManager · LiquidationHandler · ZenStaking ·          │
│  PriceOracle · ProofVerifierAdapter · PositionRegistry      │
└──────────────────────────┬─────────────────────────────┘
                            │ verifies against
┌──────────────────────────▼─────────────────────────────┐
│  Circuits (Circom → Groth16)                               │
│  Health Factor · Transition · Reveal · Shielded Spend (POC)│
└─────────────────────────────────────────────────────────┘
```

## Contracts

| Contract | Role |
|---|---|
| `VaultManager` | Entry point for deposit/withdraw/borrow/repay. Holds real ERC-20 balances; routes every state change through a proof verifier before accepting it. |
| `PositionRegistry` | Tracks each position's sealed commitment and last-proof timestamp — the only per-position state that exists on-chain. |
| `ProofVerifierAdapter` | Verifies Circuit A (health factor) proofs against live prices read from `PriceOracle`, so no one can prove solvency against a number they made up. |
| `TransitionRevealAdapter` | Verifies Circuit T (transition) and Circuit R (reveal) proofs; gates every deposit/withdraw/borrow/repay and every liquidation reveal. |
| `LiquidationHandler` | Executes both liquidation paths — a position's own self-liquidation, and the longer-window bonded backstop for abandoned positions. |
| `PriceOracle` | Protocol-owned price and liquidation-threshold source, with a 24-hour staleness guard. |
| `InterestRateModel` | Utilization-based borrow/supply rate curve (Compound-style). |
| `ZenStaking` | Stake ZEN, earn a share of real repaid interest revenue, in whichever asset was actually repaid. |
| `ShieldedPool` | A proof-of-concept, not wired into the main vault flow — see [Known Limitations](./privacy/known-limitations.md). |

## Circuits

Four Circom circuits, compiled to Groth16 and verified on-chain via auto-generated Solidity verifiers:

- **Circuit A — Health Factor.** Proves `collateral × price × liquidation threshold ≥ debt × price` without revealing collateral or debt. Run on every periodic proof refresh.
- **Circuit T — Transition.** Proves a new sealed commitment equals the old one plus exactly one public, signed delta (a deposit, withdrawal, borrow, or repayment) to exactly one asset slot — nothing else changed. Run on every action after the first deposit.
- **Circuit R — Reveal.** Proves a sealed commitment genuinely opens to the specific numbers being disclosed. Run once, at self-liquidation, when a position deliberately reveals itself to settle.
- **Circuit S — Shielded Spend (proof-of-concept).** Proves membership of a note in a pool-wide Merkle tree and correct spend/change accounting, without revealing which note. Demonstrates the mechanism a fully private transfer layer would need; not yet wired into the vault. See [Known Limitations](./privacy/known-limitations.md).

Every circuit's trusted setup is anchored to the real, public, multi-party Hermez Perpetual Powers of Tau ceremony — see [Trusted Setup](./privacy/trusted-setup.md) for how that was independently verified.

## The commitment scheme

A position's state is a single field element:

```
commitment = Poseidon(collateral[WETH], collateral[USDC], collateral[ZEN],
                       debt[WETH], debt[USDC], debt[ZEN], salt)
```

`salt` is generated once, client-side, at your first deposit, and never leaves your browser. Poseidon is used specifically because it's cheap to prove inside a circuit — unlike Keccak, which is what a naive implementation would reach for and what makes it expensive to prove membership or equality claims about a hash inside a SNARK.

## How a transaction flows

Take a second deposit as an example — the same shape applies to withdrawals, borrows, and repayments:

1. Your browser reads your current committed collateral/debt/salt from local storage.
2. It computes the new state (old collateral + this deposit) and a fresh salt for the new commitment.
3. It generates a Circuit T proof: *"the new commitment equals the old commitment plus exactly this public amount, to exactly this asset — nothing else."*
4. `VaultManager.deposit()` verifies that proof via `TransitionRevealAdapter`, then moves the real ERC-20 tokens and stores only the new commitment.
5. A `Deposited(user, positionId, asset, amount)` event fires — the amount is necessarily public, since it's a real token transfer, but nothing about your resulting *total* position is.

The full action-by-action version of this, covering every button in the app, is in [Using the App](./using-the-app/core-loop.md).
