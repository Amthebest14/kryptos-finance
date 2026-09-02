import { useNavigate } from "react-router-dom";
import { useApp } from "../state/AppContext";
import { AssetBadge } from "../components/AssetBadge";
import { HOW_POINTS, FOOTER_COLS, MARKET_ASSETS, TINT, BADGE, LIVE_PRICES as P, LOGO_URL } from "../lib/mock";
import { usd } from "../lib/math";

export function Landing() {
  const { chainData } = useApp();
  const navigate = useNavigate();

  const totalCollateralUsd = MARKET_ASSETS.reduce((s, k) => s + (chainData.totalSupplied[k] ?? 0) * (P[k] ?? 0), 0);
  const totalBorrowedUsd = MARKET_ASSETS.reduce((s, k) => s + (chainData.totalBorrowed[k] ?? 0) * (P[k] ?? 0), 0);
  const utilization = totalCollateralUsd > 0 ? (totalBorrowedUsd / totalCollateralUsd) * 100 : 0;
  const heroStats = [
    { label: "Total collateral", value: usd(totalCollateralUsd), note: `across ${MARKET_ASSETS.length} markets` },
    { label: "Total borrowed", value: usd(totalBorrowedUsd), note: "private positions only" },
    { label: "Utilization", value: utilization.toFixed(1) + "%", note: "protocol-wide, live" },
  ];

  const launch = () => navigate("/dashboard");

  return (
    <main>
      <section style={{ position: "relative", overflow: "hidden" }}>
        <img
          src="/rotate.svg"
          alt=""
          aria-hidden="true"
          className="landing-bg-mark"
          style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            width: "min(150vw, 1500px)",
            height: "min(150vw, 1500px)",
            opacity: 0.18,
            pointerEvents: "none",
            zIndex: 0,
          }}
        />
        <div style={{ position: "relative", zIndex: 1, maxWidth: 1180, margin: "0 auto", padding: "96px 24px 72px" }}>
          <div
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 8,
            padding: "5px 11px 5px 8px",
            border: "1px solid var(--border)",
            borderRadius: 999,
            background: "var(--surface)",
            color: "var(--dim)",
            fontSize: 12,
            letterSpacing: "0.01em",
          }}
        >
          <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--gold)" }} />
          Confidential lending market · live on Horizen
        </div>
        <h1 style={{ margin: "26px 0 0", fontSize: 60, lineHeight: 1.02, letterSpacing: "-0.035em", fontWeight: 600, maxWidth: "15ch" }}>
          Borrow without publishing your position.
        </h1>
        <p style={{ margin: "24px 0 0", maxWidth: "60ch", fontSize: 17, lineHeight: 1.55, color: "var(--dim)" }}>
          On transparent lending markets every large position is a target — bots hunt liquidations, and the funds, treasuries and desks that could bring
          real credit onchain stay out. Kryptos Finance keeps your collateral, debt and health factor private. Only protocol totals are public.
        </p>
        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 12, marginTop: 36 }}>
          <button onClick={launch} style={{ height: 46, padding: "0 22px", border: 0, borderRadius: 10, background: "var(--gold)", color: "#0B1020", fontSize: 14.5, fontWeight: 600 }}>
            Launch App
          </button>
          <a href="#how" style={{ display: "grid", placeItems: "center", height: 46, padding: "0 20px", border: "1px solid var(--border2)", borderRadius: 10, color: "var(--text)", fontSize: 14.5, fontWeight: 500 }}>
            How it works
          </a>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(200px,1fr))", gap: 1, marginTop: 64, background: "var(--border)", border: "1px solid var(--border)", borderRadius: 14, overflow: "hidden" }}>
          {heroStats.map((s) => (
            <div key={s.label} style={{ padding: "22px 24px", background: "var(--surface)" }}>
              <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>{s.label}</div>
              <div style={{ marginTop: 10, fontFamily: "'Geist Mono',monospace", fontSize: 30, fontWeight: 500, letterSpacing: "-0.02em" }}>{s.value}</div>
              <div style={{ marginTop: 6, fontSize: 12.5, color: "var(--faint)" }}>{s.note}</div>
            </div>
          ))}
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 14, marginTop: 28 }}>
          <span style={{ fontSize: 12, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--faint)" }}>Supported collateral</span>
          {MARKET_ASSETS.map((k) => (
            <div key={k} style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 12px 6px 6px", border: "1px solid var(--border)", borderRadius: 999, background: "var(--surface)" }}>
              <AssetBadge initial={BADGE[k] || k.slice(0, 2).toUpperCase()} tint={TINT[k]} logoUrl={LOGO_URL[k]} />
              <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--text)" }}>{k}</span>
            </div>
          ))}
          </div>
        </div>
      </section>

      <section id="how" style={{ borderTop: "1px solid var(--border)", background: "var(--surface)" }}>
        <div style={{ maxWidth: 1180, margin: "0 auto", padding: "72px 24px" }}>
          <h2 style={{ margin: 0, fontSize: 13, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--faint)", fontWeight: 600 }}>
            How the privacy works
          </h2>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(280px,1fr))", gap: 20, marginTop: 28 }}>
            {HOW_POINTS.map((p) => (
              <div key={p.num} style={{ padding: 26, border: "1px solid var(--border)", borderRadius: 14, background: "var(--bg)" }}>
                <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12, color: "var(--gold)" }}>{p.num}</div>
                <h3 style={{ margin: "14px 0 0", fontSize: 20, letterSpacing: "-0.02em", fontWeight: 600 }}>{p.title}</h3>
                <p style={{ margin: "12px 0 0", fontSize: 14, lineHeight: 1.55, color: "var(--dim)" }}>{p.body}</p>
              </div>
            ))}
          </div>
          <p style={{ margin: "28px 0 0", fontSize: 14, color: "var(--faint)", maxWidth: "70ch" }}>
            Nothing here is opt-in. Confidentiality is the default state of every position on Kryptos Finance — the protocol has no view into individual
            accounts either.
          </p>
        </div>
      </section>

      <footer style={{ borderTop: "1px solid var(--border)", padding: "44px 24px 56px" }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 32, justifyContent: "space-between", maxWidth: 1180, margin: "0 auto" }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <img src="/logo-64.png" alt="" width={24} height={24} style={{ borderRadius: 6, display: "block" }} />
              <span style={{ fontWeight: 600, fontSize: 14.5 }}>Kryptos Finance</span>
            </div>
            <div style={{ marginTop: 14, display: "flex", alignItems: "center", gap: 8, fontSize: 12.5, color: "var(--faint)" }}>
              <span style={{ padding: "4px 9px", border: "1px solid var(--border)", borderRadius: 6 }}>Built on Horizen</span>
              <span style={{ padding: "4px 9px", border: "1px solid var(--border)", borderRadius: 6 }}>In partnership with Thrive</span>
            </div>
          </div>
          <div style={{ display: "flex", gap: 56, flexWrap: "wrap" }}>
            {FOOTER_COLS.map((c) => (
              <div key={c.title}>
                <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>{c.title}</div>
                <div style={{ display: "flex", flexDirection: "column", gap: 9, marginTop: 14 }}>
                  {c.links.map((l) => (
                    <a key={l} href="#how" style={{ fontSize: 13.5, color: "var(--dim)" }}>
                      {l}
                    </a>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </footer>
    </main>
  );
}
