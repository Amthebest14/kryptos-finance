---
title: Deployed Contracts
sidebar_label: Deployed Contracts
---

# Deployed Contracts

All contracts below are live on **Horizen Testnet** (chain id `2651420`), deployed via Foundry. Addresses are also maintained in [`kryptos-frontend/src/lib/contracts.ts`](https://github.com/Amthebest14/kryptos-finance/blob/main/kryptos-frontend/src/lib/contracts.ts), the frontend's own source of truth — if this page and that file ever disagree, the file is authoritative.

## Core protocol

| Contract | Address |
|---|---|
| `VaultManager` | `0x6b2cFE744D93AC7734281756CB4f3De0071bE8cA` |
| `PositionRegistry` | `0x4f226Ce0A8b2232562Fc5982a8027903FC2A9Da6` |
| `LiquidationHandler` | `0x925AF37De2142a6cF4c76D5546D55a90981b57Bd` |
| `ProofVerifierAdapter` | `0x0DB69497D9E1d485758Ef9c5925F383Dc52aFCcb` |
| `TransitionRevealAdapter` | `0xbaC53287eCf23ac461742B2BC08AC5754664b14d` |
| `PriceOracle` | `0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5` |
| `InterestRateModel` | `0x4049f156BCF0FD86eC93A7100c9006E3e49B2d63` |
| `ZenStaking` | `0x0b56986F8Ec05ba0b6da5956269cDA0c5BB9226E` |
| `SimpleMultiSig` (PriceOracle owner) | `0x05cFa3CDEBf164Dc99DAF17b89c1997836b626A7` |

## Generated Groth16 verifiers

| Verifier | Circuit | Address |
|---|---|---|
| `HealthFactorVerifier` | Circuit A | `0x2DF316eC6fbFED3a336871d7c0b11d1B64938E34` |
| `TransitionVerifier` | Circuit T | `0xDe7c8f1C1135A6790F25316ca42B37354196a216` |
| `RevealVerifier` | Circuit R | `0xf17904Cdbe9E60F1B210B6f4CBa22da6D0ac40cB` |

## Test assets (mock, faucet-enabled)

| Asset | Address | Faucet amount |
|---|---|---|
| WETH | `0x239Ac78cAb8d5553BDC6737593824b06fd88CE47` | 10 / day |
| USDC | `0xe026E73C3aD539b6566d2A1A29A5d778e7AB7C9a` | 10,000 / day |
| ZEN | `0xe015F8ccacC72545b9CF457a610bfC75fFAB4ADd` | 10,000 / day |

## Shielded pool (proof-of-concept — not integrated)

| Contract | Address |
|---|---|
| `ShieldedPool` | `0x1cCF4E20eC3Cf752bE62776E89A723e7044fE504` |
| `ShieldedSpendVerifier` (Circuit S) | `0x286080ba2Ba64AD4Abe39b4Eb6D16f0114e7615D` |

See [Known Limitations](../privacy/known-limitations.md) for what this contract does and doesn't do.

## Network

| | |
|---|---|
| Chain ID | `2651420` |
| RPC URL | `https://horizen-testnet.rpc.caldera.xyz/http` |
| Block explorer | https://explorer-testnet.horizen.io/ |
