import { useApp } from "../state/AppContext";
import { MARKET_ASSETS, LIVE_PRICES as P } from "../lib/mock";
import { usd } from "../lib/math";

export function Stats() {
  const { chainData } = useApp();

  const totalCollateralUsd = MARKET_ASSETS.reduce((s, k) => s + (chainData.totalSupplied[k] ?? 0) * (P[k] ?? 0), 0);
  const totalBorrowedUsd = MARKET_ASSETS.reduce((s, k) => s + (chainData.totalBorrowed[k] ?? 0) * (P[k] ?? 0), 0);
  const utilization = totalCollateralUsd > 0 ? (totalBorrowedUsd / totalCollateralUsd) * 100 : 0;
  const interestRevenueUsd = MARKET_ASSETS.reduce((s, k) => s + (chainData.interestRevenueByAsset[k] ?? 0) * (P[k] ?? 0), 0);
  const hasInterestRevenue = Object.keys(chainData.interestRevenueByAsset).length > 0;

  const REAL_TILES = [
    { label: "Total collateral deposited", value: usd(totalCollateralUsd), note: "Live sum of VaultManager.totalSupplied across all markets, priced live via Pyth (WETH, USDC) and CoinGecko (ZEN)." },
    { label: "Total outstanding borrows", value: usd(totalBorrowedUsd), note: "Live sum of VaultManager.totalBorrowed across all markets." },
    { label: "Utilization rate", value: utilization.toFixed(1) + "%", note: "Borrows divided by collateral, computed live." },
    { label: "Unique borrowers", value: String(chainData.uniqueBorrowers), note: "Distinct addresses behind a Deposited event — real, but not privacy-preserving yet (addresses are visible in event logs until a real commitment scheme hides them)." },
    { label: "Liquidations executed", value: String(chainData.liquidations.length), note: "Live count from LiquidationHandler.LiquidationSettled events." },
  ];

  return (
    <main style={{ maxWidth: 1180, margin: "0 auto", padding: "32px 24px 80px" }}>
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-end", justifyContent: "space-between", gap: 16 }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 26, letterSpacing: "-0.025em", fontWeight: 600 }}>Protocol statistics</h1>
          <p style={{ margin: "7px 0 0", maxWidth: "70ch", fontSize: 13.5, color: "var(--dim)" }}>Read live from the deployed contracts on this devnet.</p>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(320px,1fr))", gap: 16, marginTop: 22 }}>
        {REAL_TILES.map((t) => (
          <div key={t.label} style={{ padding: 24, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
            <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>{t.label}</div>
            <div style={{ marginTop: 12, fontFamily: "'Geist Mono',monospace", fontSize: 42, lineHeight: 1, fontWeight: 500, letterSpacing: "-0.035em" }}>{t.value}</div>
            <div style={{ marginTop: 14, fontSize: 12.5, color: "var(--faint)" }}>{t.note}</div>
          </div>
        ))}

        <div style={{ padding: 24, border: hasInterestRevenue ? "1px solid var(--border)" : "1px dashed var(--border2)", borderRadius: 16, background: "var(--surface)" }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Interest revenue to protocol</div>
          <div style={{ marginTop: 12, fontFamily: "'Geist Mono',monospace", fontSize: 42, lineHeight: 1, fontWeight: 500, letterSpacing: "-0.035em", color: hasInterestRevenue ? undefined : "var(--faint)" }}>
            {hasInterestRevenue ? usd(interestRevenueUsd) : "$0.00"}
          </div>
          <div style={{ marginTop: 14, fontSize: 12.5, color: "var(--faint)" }}>
            Live sum of ZenStaking.RewardNotified events — real tokens VaultManager has actually forwarded as self-reported accrued interest, not a
            projection. Only exists when a borrower's repay call reports it; nothing on-chain can enforce that it does.
          </div>
        </div>
      </div>

      <AggregateSolvencyCard />
    </main>
  );
}

function AggregateSolvencyCard() {
  const { chainData } = useApp();
  const { activePositions, freshPositions, stalePositions, allFresh } = chainData.aggregateSolvency;

  let badgeLabel: string;
  let badgeColor: string;
  let badgeBg: string;
  let body: string;

  if (activePositions === 0) {
    badgeLabel = "No open positions";
    badgeColor = "var(--faint)";
    badgeBg = "var(--surface2)";
    body =
      "No positions are currently open (or every one that ever opened has since been liquidated) — there's nothing to check yet.";
  } else if (allFresh) {
    badgeLabel = "Proven";
    badgeColor = "var(--green)";
    badgeBg = "var(--greensoft)";
    const isPlural = activePositions !== 1;
    body =
      `All ${activePositions} active position${isPlural ? "s" : ""} currently ${isPlural ? "carry" : "carries"} a live, cryptographically ` +
      "verified Circuit A proof of solvency (health factor ≥ 1) — without revealing any individual position's collateral, " +
      "debt, or health factor. No new aggregate circuit is needed for this: PositionRegistry already tracks per-position proof " +
      "freshness on-chain, and Circuit A already proves each one is genuinely solvent to earn that freshness. “Every position " +
      "is proven solvent” is exactly what “none are stale” already means — this card just surfaces that existing " +
      "guarantee as one number, since no single party ever holds every user's private collateral/debt to build one proof over all of them.";
  } else {
    badgeLabel = `${stalePositions} of ${activePositions} unresolved`;
    badgeColor = "var(--amber)";
    badgeBg = "var(--ambersoft)";
    body =
      `${freshPositions} of ${activePositions} active positions currently carry a fresh, verified Circuit A proof. ` +
      `${stalePositions} ${stalePositions === 1 ? "has" : "have"} missed its check-in window and ${stalePositions === 1 ? "is" : "are"} eligible for liquidation — ` +
      "full aggregate solvency doesn't hold at this exact moment. Which position(s) were already individually public via " +
      "PositionRegistry.isStale() — this card only adds up what was already visible.";
  }

  return (
    <div style={{ marginTop: 16, padding: 26, border: "1px dashed var(--border2)", borderRadius: 16, background: "var(--surface)" }}>
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-start", gap: 24, justifyContent: "space-between" }}>
        <div style={{ maxWidth: "64ch" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <h2 style={{ margin: 0, fontSize: 17, letterSpacing: "-0.02em", fontWeight: 600, color: "var(--faint)" }}>Aggregate solvency proof</h2>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 7, padding: "5px 10px", borderRadius: 999, background: badgeBg, color: badgeColor, fontSize: 12, fontWeight: 600 }}>
              {badgeLabel}
            </span>
          </div>
          <p style={{ margin: "12px 0 0", fontSize: 14, lineHeight: 1.55, color: "var(--faint)" }}>{body}</p>
        </div>
      </div>
    </div>
  );
}
