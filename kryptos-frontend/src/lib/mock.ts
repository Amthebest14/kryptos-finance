// What's left here is display metadata and explicitly-labeled placeholders for
// phases that don't exist yet — NOT fake data standing in for real data.
// Everything that has a real contract behind it (positions, balances, totals,
// liquidations) is read live in AppContext.tsx / the pages, not from this file.

// Real assets only — matches script/Deploy.s.sol. wstETH/cbBTC/USDT appear in
// the original design but have no deployed token, so they're left out rather
// than pointed at a fake address.
export const MARKET_ASSETS = ["WETH", "USDC", "ZEN"];

export const TINT: Record<string, string> = { WETH: "#5B6FE8", USDC: "#2775CA", ZEN: "#28B394" };
export const BADGE: Record<string, string> = { WETH: "ETH", USDC: "C", ZEN: "ZEN" };
export const NAME: Record<string, string> = { WETH: "Wrapped Ether", USDC: "USD Coin", ZEN: "Horizen ZEN" };

// Real official logos, referenced from CoinGecko's public image CDN (same
// pattern as loading fonts from Google Fonts — an external URL, not a file we
// download and re-host). Verified live before wiring in: each URL returns a
// real image/png, not a 404. AssetBadge falls back to the tinted-initial
// circle automatically if any of these ever stop loading.
export const LOGO_URL: Record<string, string> = {
  WETH: "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png?1696501628", // WETH tracks ETH; no separate wrapped-ETH logo needed
  USDC: "https://coin-images.coingecko.com/coins/images/6319/large/USDC.png?1769615602",
  ZEN: "https://coin-images.coingecko.com/coins/images/691/large/Horizen2.0-logo_icon-on-yellow_%281%29.png?1751696763",
};

// Live prices — fetched from Pyth (WETH, USDC) and CoinGecko (ZEN) by
// prices.ts's refreshLivePrices(), which mutates these values in place on a
// timer (see AppContext.tsx). The numbers below are only the seed shown for
// one render before the first live fetch resolves, not fallback mock data.
export const LIVE_PRICES: Record<string, number> = { WETH: 3557.2, USDC: 1, ZEN: 11.42 };
export const MOCK_LIQ_THRESHOLD: Record<string, number> = { WETH: 0.83, USDC: 0.9, ZEN: 0.65 };
export const MOCK_MAX_LTV: Record<string, number> = { WETH: 0.8, USDC: 0.87, ZEN: 0.6 };

// PLACEHOLDER — Phase 3's InterestRateModel.sol not built yet. Real rates need
// a real utilization curve; these are illustrative only.
export const MOCK_SUPPLY_APY: Record<string, string> = { WETH: "2.14%", USDC: "5.41%", ZEN: "1.86%" };
export const MOCK_BORROW_APR: Record<string, string> = { WETH: "3.87%", USDC: "7.28%", ZEN: "4.95%" };

export const HOW_POINTS = [
  { num: "01", title: "Your numbers are locked", body: "Collateral, debt and health factor are encrypted the moment you deposit. No table, feed or dashboard here can show them — the protocol cannot read them either." },
  { num: "02", title: "You prove you are healthy, privately", body: "Every 30 minutes your position submits a proof that it is still above the liquidation threshold. The proof reveals pass or fail, and nothing else." },
  { num: "03", title: "Fail to prove it, and only the position surfaces", body: "If proofs stop arriving, the position enters a grace period and then becomes liquidatable. What becomes visible is a position ID — never who you are." },
];

export const FOOTER_COLS = [
  { title: "Protocol", links: ["Markets", "Statistics", "Liquidations", "ZEN staking"] },
  { title: "Developers", links: ["Documentation", "Proof system", "Audits", "GitHub"] },
  { title: "Community", links: ["X", "Discord", "Forum", "Blog"] },
];
