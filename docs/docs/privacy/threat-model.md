---
title: Privacy Threat Model
sidebar_label: Threat Model
---

# Privacy Threat Model

Every privacy system protects against *some* observer, under *some* conditions — never against every possible one, unconditionally. Stating that scope precisely is more useful, and more honest, than a blanket claim of "private." This page states it precisely.

## Who sees what

| Data | You | Everyone else |
|---|---|---|
| Your exact collateral / debt right now | Visible | Hidden |
| Your health factor | Visible | Hidden |
| That your position exists, and its ID | Visible | Public |
| Whether your position is stale right now | Visible | Public |
| Each individual deposit/withdraw/borrow/repay amount | Visible | Public |
| Protocol-wide totals (Markets, Stats) | Visible | Public |
| Your revealed numbers, after a liquidation | Visible | Public |

## The honest caveat

Your individual transaction amounts are each public — a real token transfer has to be. That means a patient observer replaying your wallet's full history *can* reconstruct your running collateral and debt by summing them, even though no single number was ever revealed on its own, and even though the contract itself never stored your total at any point in time. Closing that for real needs a fundamentally different transfer mechanism — a shielded pool with pooled, fungible notes instead of per-position balances — not a setting to flip. See [Known Limitations](./known-limitations.md) for the proof-of-concept that demonstrates what that mechanism would look like, and why it isn't wired into the main vault yet.

This is documented deliberately, not discovered by a reviewer. The app ships a working tool that performs exactly this reconstruction — see below.

## Try it yourself: the Exposure tool

The app's [`/exposure`](https://testnet.kryptos.finance/exposure) page does, live, exactly what any outside observer already could: replay one address's public `Deposited`/`Withdrawn`/`Borrowed`/`Repaid`/liquidation history and sum it into a reconstructed running balance. It reads nothing the app doesn't already emit publicly, needs no wallet signature to run, and works for any address — yours or someone else's. That's deliberate: the tool exists to make the reconstruction technique visible, not to open a new access path.

## So what does this actually protect against?

Given that caveat, the natural question is what the privacy guarantee is actually worth. The answer: it changes *who* can act on your position and *how cheaply*, not whether a sufficiently motivated party can eventually reconstruct it.

**What's closed off:**
- Cheap, automated, real-time surveillance. A bot watching for large positions to front-run, MEV-search, or target for social engineering gets nothing from reading contract storage or a single transaction — there's no health factor to query, no balance to sort by size.
- Casual observation. Anyone glancing at the chain, or even querying it directly, cannot see your position's contents — only that a position exists and that some public amount moved.
- Health-factor sniping. Liquidation bots that scan for undercollateralized positions by reading storage have nothing to scan; staleness (a timestamp) is the only public liquidation signal, and it reveals nothing about the numbers behind it.

**What isn't closed off:**
- A patient, targeted adversary willing to replay your specific wallet's full public history and do the arithmetic. This was always true of any transparent-ledger system and remains true here.

This is the same scope distinction Tor draws for network traffic: it defeats bulk, cheap, automated surveillance, not a resourced adversary correlating traffic at both ends of a specific target. Kryptos draws an analogous line for financial position data — and states it, rather than letting a user discover the gap themselves.

## What Horizen's confidentiality layer is protecting

Horizen's role here is verifying the zero-knowledge proofs themselves (via zkVerify) — the mathematical guarantee that a proof is sound and reveals nothing beyond its stated claim. That's the layer that makes "prove solvency without disclosing the numbers" possible at all. It's a different, narrower guarantee than "nothing about this protocol is ever observable" — and this page exists so that distinction isn't left implicit.
