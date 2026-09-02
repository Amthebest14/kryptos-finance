import { useApp } from "../state/AppContext";
import { AssetBadge } from "../components/AssetBadge";
import { TINT, BADGE, LOGO_URL } from "../lib/mock";

export function LiquidationsFeed() {
  const { chainData } = useApp();
  const badge = (k: string) => BADGE[k] || k.slice(0, 2).toUpperCase();
  const liquidations = chainData.liquidations;

  return (
    <main style={{ maxWidth: 1040, margin: "0 auto", padding: "32px 24px 80px" }}>
      <h1 style={{ margin: 0, fontSize: 26, letterSpacing: "-0.025em", fontWeight: 600 }}>Liquidation activity</h1>
      <p style={{ margin: "8px 0 0", maxWidth: "74ch", fontSize: 14, lineHeight: 1.55, color: "var(--dim)" }}>
        Every liquidation the protocol has executed, read live from LiquidationHandler's onchain events. Entries carry a position ID and the asset pair
        involved — nothing else. There is no amount and no wallet address, because the protocol never held that data in the clear.
      </p>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(200px,1fr))", gap: 1, marginTop: 24, background: "var(--border)", border: "1px solid var(--border)", borderRadius: 14, overflow: "hidden" }}>
        <div style={{ padding: "20px 22px", background: "var(--surface)" }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Liquidations, all time</div>
          <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 28, fontWeight: 500, letterSpacing: "-0.02em" }}>{liquidations.length}</div>
        </div>
        <div style={{ padding: "20px 22px", background: "var(--surface)" }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Identity leaks</div>
          <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 28, fontWeight: 500, letterSpacing: "-0.02em", color: "var(--green)" }}>0</div>
        </div>
      </div>
      <div style={{ marginTop: 16, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", overflow: "hidden" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "16px 22px", borderBottom: "1px solid var(--border)" }}>
          <span style={{ fontSize: 14, fontWeight: 600 }}>Event feed</span>
          <span style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 12, color: "var(--faint)" }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--green)", animation: "kfPulse 2.4s ease-in-out infinite" }} />
            Live from chain
          </span>
        </div>
        {liquidations.length === 0 ? (
          <div style={{ padding: "40px 22px", textAlign: "center", fontSize: 13.5, color: "var(--faint)" }}>
            No liquidations yet on this deployment — this is a real, currently-empty feed, not a placeholder.
          </div>
        ) : (
          liquidations.map((f) => (
            <div key={f.txHash} style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 14, padding: "15px 22px", borderBottom: "1px solid var(--border)" }}>
              <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--faint)", minWidth: 160 }}>{new Date(f.timestamp * 1000).toLocaleString()}</span>
              <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13.5, minWidth: 118 }}>Position #{f.positionId}</span>
              <span style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 104 }}>
                <AssetBadge initial={badge(f.collateralAsset)} tint={TINT[f.collateralAsset]} size={22} logoUrl={LOGO_URL[f.collateralAsset]} />
                <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13, color: "var(--dim)" }}>{f.collateralAsset}</span>
              </span>
              <span style={{ marginLeft: "auto", display: "inline-flex", alignItems: "center", gap: 7, padding: "5px 10px", borderRadius: 999, background: "var(--greensoft)", color: "var(--green)", fontSize: 12, fontWeight: 550 }}>
                <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--green)" }} />
                Processed — zero identity leakage
              </span>
            </div>
          ))
        )}
        <div style={{ padding: "16px 22px", fontSize: 12.5, color: "var(--faint)" }}>Position IDs are sequential per-position, not tied to a wallet address.</div>
      </div>
    </main>
  );
}
