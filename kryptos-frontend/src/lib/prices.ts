// Live asset prices. Verified live against real endpoints while building this
// (not assumed from memory) — see the two sources below and why they're split.
//
// WETH and USDC: read directly from Pyth Network's on-chain price contract on
// Base mainnet. This is a plain read-only eth_call against a public RPC — no
// API key, no signup. (Pyth's off-chain Hermes API now requires a key as of
// their Aug 26, 2026 upgrade; reading the already-updated on-chain feed
// sidesteps that entirely, and is how many production dapps consume Pyth
// anyway.)
//
// ZEN: Pyth's *new* Base contract has never received a ZEN/USD update
// (reverts with PriceFeedNotFound), and the *old* Base contract's ZEN price
// is about a year stale. Genuinely not available live via Pyth on Base right
// now. Falls back to CoinGecko's free public API instead, honestly labeled
// as a different source rather than silently mislabeling stale data as live.
import { Contract, JsonRpcProvider } from "ethers";
import { LIVE_PRICES } from "./mock";

const BASE_MAINNET_RPC = "https://mainnet.base.org";
const PYTH_CONTRACT = "0xbC16aee60f64864882BC6C4E428e148Fc0E272F5";
const PYTH_ABI = ["function getPriceUnsafe(bytes32 id) view returns (int64 price, uint64 conf, int32 expo, uint256 publishTime)"];

const PYTH_FEED_IDS: Record<string, string> = {
  WETH: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace", // Crypto.ETH/USD — WETH tracks ETH 1:1
  USDC: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a", // Crypto.USDC/USD
};

export type PriceSource = "pyth" | "coingecko" | "unavailable";

export interface PriceInfo {
  value: number;
  source: PriceSource;
  updatedAt: number | null; // unix seconds, null if this fetch failed and we kept the last-known value
}

const basePythProvider = new JsonRpcProvider(BASE_MAINNET_RPC, undefined, { batchMaxCount: 1 });
const pyth = new Contract(PYTH_CONTRACT, PYTH_ABI, basePythProvider);

async function fetchPythPrice(symbol: string): Promise<PriceInfo | null> {
  try {
    const [price, , expo, publishTime] = await pyth.getPriceUnsafe(PYTH_FEED_IDS[symbol]);
    const value = Number(price) * 10 ** Number(expo);
    return { value, source: "pyth", updatedAt: Number(publishTime) };
  } catch (err) {
    console.error(`Pyth price fetch failed for ${symbol}`, err);
    return null;
  }
}

async function fetchZenPrice(): Promise<PriceInfo | null> {
  try {
    const res = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=zencash&vs_currencies=usd&include_last_updated_at=true");
    const json = await res.json();
    const usd = json?.zencash?.usd;
    const updatedAt = json?.zencash?.last_updated_at;
    if (typeof usd !== "number") return null;
    return { value: usd, source: "coingecko", updatedAt: typeof updatedAt === "number" ? updatedAt : null };
  } catch (err) {
    console.error("CoinGecko price fetch failed for ZEN", err);
    return null;
  }
}

// Fetches all live prices and mutates LIVE_PRICES in place (same object
// reference every consumer already imports) so no call site elsewhere in the
// app needs to change. Returns per-asset source/freshness info for display —
// on a failed fetch, the old value is kept and the asset is reported
// "unavailable" for that round rather than silently zeroed.
export async function refreshLivePrices(): Promise<Record<string, PriceInfo>> {
  const [weth, usdc, zen] = await Promise.all([fetchPythPrice("WETH"), fetchPythPrice("USDC"), fetchZenPrice()]);

  const result: Record<string, PriceInfo> = {
    WETH: weth ?? { value: LIVE_PRICES.WETH, source: "unavailable", updatedAt: null },
    USDC: usdc ?? { value: LIVE_PRICES.USDC, source: "unavailable", updatedAt: null },
    ZEN: zen ?? { value: LIVE_PRICES.ZEN, source: "unavailable", updatedAt: null },
  };

  for (const [symbol, info] of Object.entries(result)) {
    LIVE_PRICES[symbol] = info.value;
  }

  return result;
}
