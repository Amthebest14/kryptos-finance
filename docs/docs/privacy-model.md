---
title: How Privacy Works
sidebar_label: How Privacy Works
---

# How Privacy Works

## Prove, don't disclose

A conventional lending market stores your position as plaintext: `collateral[you] = 4.2 ETH`, readable by the contract, and therefore by anyone who reads the contract's storage — which on a public chain is everyone. There's no way to check "is this position solvent?" without the checker being able to see the numbers.

A zero-knowledge proof breaks that link. It lets you prove a *statement about* private numbers — "my collateral times its price times the liquidation threshold is at least my debt times its price" — without the verifier ever learning the numbers themselves. The contract still gets a real, cryptographically-binding guarantee. It just never sees what it's guaranteeing about.

This is the entire mechanism Kryptos is built on. Every action that would normally require disclosing your position instead requires proving a fact about it.

## What actually sits in contract storage

Per position, exactly one thing: a single field element,

```
commitment = Poseidon(collateral[WETH], collateral[USDC], collateral[ZEN],
                       debt[WETH], debt[USDC], debt[ZEN], salt)
```

That's it. Not collateral, not debt, not a health factor — a hash that's computationally infeasible to invert, sealed with a secret salt that never leaves your browser. Two positions with identical collateral and debt produce completely unrelated commitments, because the salt differs.

## The three proofs

| Circuit | Proves | Used when |
|---|---|---|
| **A — Health Factor** | This commitment's collateral currently covers its debt at the required ratio | Every ~30-minute check-in |
| **T — Transition** | A new commitment equals the old one plus exactly one public, signed delta | Every deposit, withdrawal, borrow, repayment after the first |
| **R — Reveal** | A commitment genuinely opens to specific disclosed numbers | Once, at voluntary self-liquidation |

All three run entirely in your browser via [snarkjs](https://github.com/iden3/snarkjs), against real compiled circuits (not a server-side stand-in), and are verified on-chain by generated Solidity verifiers. You can read the circuit source directly — see the [`circuits/`](https://github.com/Amthebest14/kryptos-finance/tree/main/circuits) directory in the repository.

## Why this needs real cryptography, not just "trust us"

Two properties have to both hold, or the whole scheme is worthless:

- **Soundness** — you cannot construct a valid-looking proof for a false statement. This is what Groth16 guarantees mathematically, not a policy.
- **Zero-knowledge** — the proof itself leaks nothing about the private inputs beyond the truth of the statement. This is also a property of the proof system, verified by construction, not by promise.

Neither property depends on trusting Kryptos, a server operator, or any piece of hardware. It depends on the correctness of Groth16 (a well-studied, widely deployed proof system) and the circuits' own logic, which is open in this repository for exactly that reason.

## What this doesn't hide

Zero-knowledge proofs hide the *content* of your position. They don't hide that a transaction happened, who sent it, or its public amount — a real on-chain token transfer is inherently public. This is a real, load-bearing distinction, covered in full in [Privacy Threat Model](./privacy/threat-model.md).
