---
title: The Core Loop
sidebar_label: The Core Loop
---

# The Core Loop

What actually happens, on-chain, behind every button — faucet through repay.

## Claiming the faucet

**Always allowed.**

- **You do:** Click *Get 10 WETH* / *Get 10,000 USDC* / *Get 10,000 ZEN* on the Dashboard.
- **On-chain:** Calls `claimFaucet()` on that specific mock token — no arguments, credits `msg.sender` directly. Each token tracks your last claim day independently.
- **You see:** Wallet balance updates immediately; the button greys out with "claimed today" until the next reset.

:::note
Faucet claims are per-asset, not global — claiming WETH doesn't touch your USDC or ZEN cooldown. Each resets at 00:00 UTC+1.
:::

## Your first deposit

**Always allowed — no proof required.**

- **You do:** Deposit → pick an asset and amount → confirm. This is the one deposit that needs no proof, because there's no prior committed state yet for a proof to be consistent with.
- **On-chain:** Your browser computes `commitment = Poseidon(collateral, debt, salt)` locally — the salt is generated once, right now, and never leaves your device. `VaultManager.deposit()` opens your position with that commitment, then moves the real tokens. Emits `Deposited(user, positionId, asset, amount)`.
- **You see:** Dashboard shows a real health factor, computed from your own locally-held numbers — not read from chain. Markets' Total Supplied ticks up for that asset, live.

:::note
**What's public:** your wallet address, the asset, and the exact amount — a real ERC-20 transfer can't hide that. **What's sealed:** everything about your position going forward, including this very first number, once it's inside the commitment.
:::

## Depositing again

**Always allowed. Needs a ZK proof.**

- **You do:** Same Deposit flow — but now your position already exists, so this has to prove consistency with it.
- **On-chain:** Your browser generates a real Circuit T (transition) proof: "the new sealed commitment is the old one, plus exactly this public amount, to exactly this asset — nothing else touched." `VaultManager.deposit()` verifies that proof via `TransitionRevealAdapter` before accepting the new commitment.
- **You see:** Health factor and collateral update on your Dashboard the instant the transaction confirms.

Every deposit/withdraw/borrow/repay after the first uses this exact same proof mechanism — it's the one thing stopping you, or anyone, from sealing a commitment that lies about what was actually deposited.

## Withdraw

**Blocked while stale. Needs a ZK proof.**

- **You do:** Withdraw → pick asset and amount, up to what's marked "safe" (keeps you above the liquidation threshold).
- **On-chain:** `VaultManager.withdraw()` first checks `PositionRegistry.isStale(positionId)` — reverts immediately with `"position stale"` if you've missed your check-in. Same Circuit T proof as a deposit, just a negative collateral delta.
- **You see:** If blocked, a plain revert, not a bug — go refresh your proof first. If it succeeds, tokens land back in your wallet and collateral drops on the Dashboard.

:::note
Why the block exists: withdrawing shrinks your safety margin, and a stale position has already failed to prove it can absorb that. Repaying has the opposite rule — see below.
:::

## Borrow

**Blocked while stale. Needs a ZK proof.**

- **You do:** Borrow → pick asset and amount, within what your collateral currently supports.
- **On-chain:** Same staleness check as withdraw. The proof adds your debt by the amount borrowed, to that one asset's slot. Tokens come from the vault's own pooled liquidity (seeded at deploy, topped up by other repayments) — not from any specific lender.
- **You see:** Borrowed tokens in your wallet. Debt and health factor update on the Dashboard; Markets' Total Borrowed and Borrow APR shift for that asset.

## Repay

**Always allowed — even while stale. Needs a ZK proof.**

- **You do:** Repay → pick asset and amount. Deliberately never blocked, even mid-grace-period — this is how you save yourself.
- **On-chain:** Two things move in the same proof: your debt principal drops by the repayment, *and* any interest accrued since your last touch of that asset gets added — checked cryptographically against the protocol's own public interest index, not just taken on your word. Whatever portion of that interest the repayment actually covers gets forwarded to `ZenStaking` as real revenue, if anyone has staked ZEN to receive it.
- **You see:** Debt drops, health factor climbs. If ZEN stakers exist, Staking's reward numbers move too — in whichever asset you just repaid with.
