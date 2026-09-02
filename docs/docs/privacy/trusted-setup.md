---
title: Trusted Setup
sidebar_label: Trusted Setup
---

# Trusted Setup

Groth16 — the proof system behind all four circuits — requires a one-time trusted setup ceremony per circuit. If the secret randomness ("toxic waste") used to generate a circuit's proving/verification keys were ever known to anyone, that person could forge false proofs for that circuit without detection. This page states exactly what Kryptos's setup is, and isn't.

## Two phases, two different guarantees

Groth16 setups split into a universal phase-1 ("Powers of Tau," circuit-independent) and a circuit-specific phase-2 (binds phase-1 to one particular circuit's constraints).

**Phase 1 is anchored to a real, public, multi-party ceremony** — the Hermez Perpetual Powers of Tau ceremony (`powersOfTau28_hez_final_14.ptau`), not a single-party file generated for this project. As long as at least one participant in that ceremony's long contributor chain honestly discarded their randomness, the resulting toxic waste is unknown to anyone, including this project.

This was independently verified, not assumed: `snarkjs powersoftau verify` was run against the *complete* ceremony transcript — checking every real contributor's response hash in the chain, not just the portion relevant to this project — and it passed outright (`Powers of Tau Ok!`), against contributions from recognizable public participants (weijie, kobi, poma, and others from the actual community ceremony).

**Phase 2 — the circuit-specific contribution for each of the four circuits — is currently single-party**, run by this project alone. This is a real, stated limitation, not folded into the phase-1 fix: a single-party phase-2 means the toxic waste for that step is known to have existed in one place at one time, even though it was discarded. A production deployment should run a genuine multi-party phase-2 ceremony per circuit before handling real value.

## Reproducing the verification

```bash
cd circuits/build
npx snarkjs powersoftau verify powersOfTau28_hez_final_14.ptau
```

The ceremony file itself ships in the repository (`circuits/build/`) rather than being fetched at build time, since both of its official public mirrors are currently unreliable — see [`circuits/build/README.md`](https://github.com/Amthebest14/kryptos-finance/tree/main/circuits/build) for the exact mirror URLs and status.

## Why this matters for a lending protocol specifically

The trusted setup isn't an abstract cryptographic footnote here — it's the thing standing between "this position is solvent" and "this position claims to be solvent." A forged Circuit A proof would let an insolvent position pass every health check indefinitely. The setup's integrity is exactly as load-bearing as the solvency guarantee itself.
