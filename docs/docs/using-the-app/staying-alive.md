---
title: Staying Alive
sidebar_label: Staying Alive
---

# Staying Alive

Because Kryptos never reads your collateral or debt from storage, it can't check your solvency the way a normal lending market does — by just looking. Instead, every position has to periodically *re-prove* its own solvency, on a clock. This page covers that mechanism and what happens if you miss it.

## Refreshing your health proof

**Needs a ZK proof.**

- **You do:** Click *Refresh proof now*, or leave *Auto-refresh* on and do nothing — it fires on its own with about 5 minutes of margin before your check-in is due.
- **On-chain:** Your browser proves, from your real local numbers: `collateral × price × liquidation threshold ≥ debt × price` — using the same price the contract itself reads from `PriceOracle`, so nobody can prove against a number they made up. `ProofVerifierAdapter.recordProof()` verifies it, then stamps a fresh timestamp on your position.
- **You see:** The health proof card flips to *Proof fresh*, and the countdown resets to 30 minutes.

:::tip Why auto-refresh can only run in this tab
Your collateral, debt, and salt live only in this browser's storage. No server or background job could renew this proof on your behalf without being handed those secrets — which would defeat the entire point. Keep the tab open (or come back before the window closes) for auto-refresh to do its job.
:::

## What happens if you miss a check-in

**Staleness itself is public.**

| Window | State |
|---|---|
| 0–30 min | Normal. `isStale()` and `isInGracePeriod()` both false. |
| 30–45 min | Grace period. Withdraw/borrow already blocked, but a fresh proof still clears it instantly — no penalty yet. |
| 45 min+ | `isStale()` flips true. Nothing about your numbers is revealed by this alone — it's a public timestamp, not a leak. But the position is now eligible for liquidation. |

Anyone can check whether *any* position is stale — that flag was always meant to be public. It's how liquidation eligibility works without anyone having to watch healthy positions.
