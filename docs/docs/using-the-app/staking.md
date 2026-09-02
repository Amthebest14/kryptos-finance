---
title: Staking
sidebar_label: Staking
---

# Staking

ZEN staking is the one part of the app with no privacy mechanism involved at all — stakes and rewards are plain ERC-20 accounting, fully public, by design.

## Stake ZEN

**Always allowed. Fully public.**

- **You do:** Staking page → enter an amount → Stake ZEN.
- **On-chain:** `ZenStaking.stake()` — plain ERC-20 mechanics. Your stake size is just as visible as anyone's.
- **You see:** Your Stake and Pool Share update immediately; so does everyone else's view of the same numbers.

## Unstake

**Always allowed.**

- **You do:** Staking page → Unstake → up to your current staked amount.
- **On-chain:** Settles your earned rewards up to this exact moment first, then reduces your stake and returns the ZEN.
- **You see:** ZEN back in your wallet. Anything you'd earned stays claimable — unstaking doesn't forfeit it.

## Claim rewards

**Always allowed.**

- **You do:** Claim next to whichever reward asset shows a nonzero balance.
- **On-chain:** Pays out your accumulated share of that asset's interest revenue — sourced entirely from real repayments other borrowers made, nothing synthetic.
- **You see:** Tokens land in your wallet; that reward line resets to zero until more interest gets repaid.

:::note
If it shows "no interest revenue forwarded yet," that's literal — nobody with debt has repaid with claimed interest since you staked. Not a placeholder, an honest zero.
:::
