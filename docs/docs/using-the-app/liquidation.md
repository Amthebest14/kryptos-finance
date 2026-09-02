---
title: Liquidation
sidebar_label: Liquidation
---

# Liquidation

A stale position — one that's missed its check-in by more than 45 minutes — becomes eligible for liquidation through one of two paths.

## Settle now (self-liquidation)

**Reveals your numbers. Needs a ZK proof.**

- **You do:** Only appears once your position is stale. Click *Settle now* — only works if you hold exactly one collateral asset and one debt asset.
- **On-chain:** Circuit R proves your sealed commitment truly opens to the specific numbers you're about to reveal — you can't be lied to by your own client, and nobody else could have forged this without your salt. `LiquidationHandler.liquidate()` then requires you to actually pay the real debt amount in, and sends your own seized collateral back to you in the same transaction.
- **You see:** A confirmation screen showing exactly what was repaid and what collateral came back. The position closes permanently — this wallet can't reopen a new one on this deployment, but a fresh deposit starts a brand-new position.

:::caution The multi-asset limit is real, not a bug
Circuit R's scope is one collateral asset plus one debt asset. Two collateral assets (say, WETH and ZEN together) trips it even if your debt side is a single asset.
:::

## Third-party liquidation

**Public feed.**

- **You do:** Browse the Liquidations page — a live feed of every settled liquidation: position ID, assets involved, timestamp.
- **On-chain:** `liquidate()` is technically callable by anyone with a valid reveal proof — but generating one needs the position's secret salt, which only its owner ever holds. In practice, this page is read-only for everyone but the position's own owner.
- **You see:** No amounts on this feed by design — only what's cryptographically unavoidable (asset pair, position ID). Amounts are visible only by deliberately decoding that transaction's calldata.

An abandoned position — stale with an owner who never comes back — has a separate, bonded backstop mechanism after a much longer window: a third party can propose a liquidation using the position's public event history as its evidence, backed by a bond sized against that same claim. It's a genuinely different, rarer path, not part of everyday use.
