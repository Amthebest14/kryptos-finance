# Kryptos Finance

A private borrow-lend protocol on [Horizen](https://horizen.io) — built for
Horizen Season 2's Builder Ecosystem Fund RFP (in partnership with Thrive
Protocol), private borrow-lend track.

Deposits, withdrawals, borrows, repayments, and liquidations are all gated
by real Groth16 zero-knowledge proofs, generated client-side in the
browser and verified on-chain — not a mock verifier, not a centralized
attestor. No third-party TEE or off-chain prover is trusted with a
position's actual balances.

- **App (Horizen Testnet):** https://testnet.kryptos.finance
- **Docs:** https://docs.kryptos.finance
- **Network:** Horizen Testnet, chain id `2651420`

## What's private, and what isn't

A position's collateral and debt amounts are never submitted in plaintext
to any contract — every state change is proven, not disclosed, via a
Poseidon commitment scheme. What this system does **not** hide: the public
event log (who transacted, roughly when, on which asset) is still
reconstructable by anyone willing to replay on-chain history and correlate
amounts, the same way it would be for any EVM chain. The `/exposure` page
in the app is a transparency tool that performs exactly that
reconstruction against a real wallet, so the actual threat model is
visible rather than asserted. See the docs for the full writeup.

## Repository layout

```
contracts/          Solidity contracts (Foundry) — VaultManager, PriceOracle,
                     ProofVerifierAdapter, LiquidationHandler, ZenStaking,
                     ShieldedPool (POC), generated Groth16 verifiers
circuits/            Circom circuits — health-factor, transition, reveal,
                     shielded-spend — plus their compiled artifacts and
                     trusted-setup files under circuits/build/
kryptos-frontend/    React + Vite + TypeScript dapp (wagmi, RainbowKit,
                     ethers, snarkjs — proofs are generated in-browser)
docs/                Docusaurus site (docs.kryptos.finance)
```

## Running locally

**Contracts**
```bash
cd contracts
forge install
forge test        # 104 tests
```

**Circuits** — see [circuits/build/README.md](circuits/build/README.md)
for the trusted-setup file and how to regenerate everything.

**Frontend**
```bash
cd kryptos-frontend
npm install
npm run dev
```

## License

MIT — see [LICENSE](LICENSE). The four generated Groth16 verifier
contracts under `contracts/src/` carry snarkjs's own GPL-3.0 license
instead; each says so in its own header.
