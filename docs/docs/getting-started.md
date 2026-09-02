---
title: Getting Started
sidebar_label: Getting Started
---

# Getting Started

Kryptos runs on **Horizen Testnet** (chain id `2651420`). Everything here uses test assets with no real value — the point is to exercise the real protocol, not a simulation of it.

## 1. Add Horizen Testnet to your wallet

| | |
|---|---|
| Network name | Horizen Testnet |
| Chain ID | `2651420` |
| RPC URL | `https://horizen-testnet.rpc.caldera.xyz/http` |
| Block explorer | https://explorer-testnet.horizen.io/ |

Opening [the app](https://testnet.kryptos.finance) and connecting a wallet will prompt you to add this network automatically if you don't already have it.

## 2. Connect a wallet

Click **Connect Wallet** in the top right. Kryptos uses RainbowKit, so any standard EVM wallet (MetaMask, Rabby, WalletConnect-compatible mobile wallets) works.

## 3. Claim the faucet

The Dashboard has three faucet buttons — WETH, USDC, and ZEN. Each is rate-limited to one claim per address per day (resetting at 00:00 UTC+1), tracked independently per asset, so claiming WETH doesn't affect your USDC or ZEN cooldown.

## 4. Make your first deposit

Your first deposit is the one action in the whole app that doesn't need a zero-knowledge proof — there's no prior committed state yet for a proof to be consistent *with*. Pick an asset and amount, confirm, and your browser generates a fresh secret salt (never leaving your device) that seals your position's very first commitment.

From here on, every action — a second deposit, a withdrawal, a borrow, a repayment — is proven, not just submitted. The full mechanics of each one are in [Using the App](./using-the-app/core-loop.md).

## 5. Keep your proof fresh

Positions must periodically re-prove their own solvency (every 30 minutes on this deployment) or become eligible for liquidation. The app handles this automatically with **Auto-refresh** — see [Staying Alive](./using-the-app/staying-alive.md) for exactly how and why.

:::tip
Nothing about your position — collateral, debt, or salt — ever leaves your browser except as a zero-knowledge proof. That also means nothing can refresh your proof for you from a server; it only happens while a tab with your position open is running. Auto-refresh handles this as long as the tab stays open.
:::
