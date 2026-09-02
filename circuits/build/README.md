# circuits/build

Compiled circuit artifacts (r1cs, wasm witness calculators, zkeys, generated
Solidity verifiers, and test fixtures) for all four circuits: Circuit A
(`health_factor`), Circuit T (`transition`), Circuit R (`reveal`), and the
shielded-pool POC (`shielded_spend`).

## The trusted setup file

`powersOfTau28_hez_final_14.ptau` (~19MB) is the real, public, multi-party
Hermez Perpetual Powers of Tau ceremony (phase 1, 2^14) that every circuit's
phase-2 setup is anchored to. It was independently verified with
`snarkjs powersoftau verify` against the complete transcript — checking
every real contributor's response hash in the chain, not just this
project's own contribution — which ran to completion and passed
("Powers of Tau Ok!").

It's committed directly rather than gitignored: as of this writing, both of
its official public mirrors return an error —

- `https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_14.ptau` (403)
- `https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_14.ptau` (403)

— so re-fetching it isn't currently reliable. If a working mirror exists by
the time you're reading this, you can still verify the copy here matches by
checking its ceremony transcript with:

```bash
npx snarkjs powersoftau verify powersOfTau28_hez_final_14.ptau
```

## What's *not* committed

`pot12_*.ptau` and `pot14_*.ptau` — this project's own earlier, single-party
Powers of Tau files, superseded by the real ceremony above and kept out of
git as dead weight. If you need them for any reason, regenerate with:

```bash
npx snarkjs powersoftau new bn128 12 pot12_0000.ptau
npx snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau
npx snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau
```

(swap `12` for `14` for the larger size the `shielded_spend` circuit needs).

## Regenerating everything else

From `circuits/`, each circuit has a matching `make_*.js` fixture script and
`.circom` source under `src/`. Standard circom + snarkjs flow (compile →
groth16 setup on the ptau above → export verifier) reproduces every file in
this directory.
