---
slug: /
title: Introduction
sidebar_label: Introduction
---

# Kryptos Finance

Kryptos Finance is a private borrow-lend protocol on [Horizen](https://horizen.io) — a confidential-computing L3 on Base. It works like the lending markets you already know (Aave, Compound, Euler): deposit collateral, borrow against it, repay, get liquidated if you fall behind. The difference is what's visible while you do it.

On a typical lending market, every position is a public ledger entry. Anyone can see exactly how much collateral you're holding, how much you owe, and how close you are to liquidation — a standing, permanent, queryable record tied to your wallet. For an individual it's an unwanted disclosure; for a treasury, a fund, or a market maker sizing real credit on-chain, it's often disqualifying.

Kryptos keeps a position's collateral, debt, and health factor out of contract storage entirely. Nothing about them is submitted in plaintext, ever. Instead, every deposit, withdrawal, borrow, repayment, and liquidation is accompanied by a real Groth16 zero-knowledge proof — generated in your browser, verified on-chain — that the position remains solvent and internally consistent, without disclosing the numbers behind it.

## Why zero-knowledge, not a TEE

There are two broad ways to build confidential DeFi: trusted hardware (a TEE attests that it ran the logic correctly, without revealing inputs) or zero-knowledge proofs (a proof attests the same thing, independent of any hardware you have to trust). Kryptos takes the second path, verified through [zkVerify](https://zkverify.io). Every proof in this system is a real Groth16 SNARK you can independently verify against the circuit source in this repository — there's no enclave, no closed beta, and no operator whose word you have to take for it.

## What's actually private, in one sentence

Your exact collateral, debt, and health factor never touch contract storage or any proof verifier in plaintext — but the public event log (who transacted, roughly when, in what amount) is not hidden, and a patient observer can reconstruct a position's running balance by replaying it. This is stated plainly, not discovered the hard way — see [Privacy Threat Model](./privacy/threat-model.md) for the full picture, including a working tool that performs exactly that reconstruction against a real wallet.

## Where to go next

- **New to the app?** Start with [Getting Started](./getting-started.md).
- **Want the mechanism, not just the pitch?** Read [How Privacy Works](./privacy-model.md) and [Architecture](./architecture.md).
- **Evaluating the privacy claim specifically?** Go straight to [Privacy Threat Model](./privacy/threat-model.md).
- **Looking for contract addresses?** See [Deployed Contracts](./reference/deployed-contracts.md).
