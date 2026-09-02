import { useApp } from "../state/AppContext";
import { AssetBadge } from "./AssetBadge";
import { LOGO_URL } from "../lib/mock";

export function TransactionModal() {
  const { ui, modalSpec: m, closeModal, setAmount, setMax, toggleSel, pickAsset, confirm, txPending } = useApp();

  if (!ui.modal || !m) return null;
  const isForm = ui.stage === "form";
  const isSuccess = ui.stage === "success";

  return (
    <div
      onClick={closeModal}
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 60,
        display: "grid",
        placeItems: "center",
        padding: 24,
        background: "rgba(4,7,14,0.66)",
        backdropFilter: "blur(3px)",
        overflow: "auto",
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: "100%",
          maxWidth: 452,
          border: "1px solid var(--border2)",
          borderRadius: 18,
          background: "var(--surface)",
          boxShadow: "0 24px 70px rgba(0,0,0,0.5)",
          animation: "kfIn 180ms ease-out",
        }}
      >
        <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 16, padding: "22px 22px 0" }}>
          <div>
            <h2 style={{ margin: 0, fontSize: 18, letterSpacing: "-0.02em", fontWeight: 600 }}>{m.title}</h2>
            <p style={{ margin: "6px 0 0", fontSize: 13, color: "var(--dim)", maxWidth: "44ch" }}>{m.sub}</p>
          </div>
          <button
            onClick={closeModal}
            style={{ flex: "none", display: "grid", placeItems: "center", width: 30, height: 30, border: "1px solid var(--border)", borderRadius: 8, background: "none", color: "var(--dim)", fontSize: 15 }}
          >
            ✕
          </button>
        </div>

        {isForm && (
          <div style={{ padding: "20px 22px 22px" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
              <span style={{ fontSize: 12, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--faint)" }}>{m.fieldLabel}</span>
              <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--dim)" }}>{m.maxLabel}</span>
            </div>
            <div style={{ marginTop: 10, border: "1px solid var(--border2)", borderRadius: 12, background: "var(--surface2)", padding: "12px 12px 12px 14px" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <button
                  onClick={toggleSel}
                  style={{ display: "flex", alignItems: "center", gap: 9, flex: "none", height: 38, padding: "0 11px", border: "1px solid var(--border2)", borderRadius: 9, background: "var(--surface)", color: "var(--text)" }}
                >
                  <AssetBadge initial={m.initial} tint={m.tint} logoUrl={LOGO_URL[m.asset]} />
                  <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13 }}>{m.asset}</span>
                  <span style={{ color: "var(--faint)", fontSize: 10 }}>▾</span>
                </button>
                <input
                  value={ui.amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="0.00"
                  inputMode="decimal"
                  style={{ flex: 1, minWidth: 0, border: 0, outline: "none", background: "none", color: "var(--text)", fontFamily: "'Geist Mono',monospace", fontSize: 24, textAlign: "right" }}
                />
                <button
                  onClick={setMax}
                  style={{ flex: "none", height: 26, padding: "0 9px", border: "1px solid var(--border2)", borderRadius: 7, background: "none", color: "var(--goldtext)", fontFamily: "'Geist Mono',monospace", fontSize: 11.5, fontWeight: 600 }}
                >
                  {m.maxWord}
                </button>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, marginTop: 8, paddingLeft: 2 }}>
                <span style={{ fontSize: 12, color: "var(--faint)" }}>{m.balanceLine}</span>
              </div>
            </div>

            {ui.selOpen && (
              <div style={{ marginTop: 8, border: "1px solid var(--border2)", borderRadius: 12, background: "var(--surface)", overflow: "hidden" }}>
                {m.options.map((o) => (
                  <button
                    key={o.symbol}
                    onClick={() => pickAsset(o.symbol)}
                    style={{ display: "flex", alignItems: "center", gap: 10, width: "100%", padding: "11px 14px", border: 0, borderBottom: "1px solid var(--border)", background: "none", color: "var(--text)", textAlign: "left" }}
                  >
                    <AssetBadge initial={o.initial} tint={o.tint} size={24} logoUrl={LOGO_URL[o.symbol]} />
                    <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13 }}>{o.symbol}</span>
                    <span style={{ marginLeft: "auto", fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--dim)" }}>{o.right}</span>
                  </button>
                ))}
              </div>
            )}

            <div style={{ marginTop: 16, border: "1px solid var(--border)", borderRadius: 12, overflow: "hidden" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "11px 14px", background: "var(--surface2)", borderBottom: "1px solid var(--border)" }}>
                <span style={{ fontSize: 12, letterSpacing: "0.05em", textTransform: "uppercase", color: "var(--dim)", fontWeight: 600 }}>Transaction overview</span>
                <span style={{ marginLeft: "auto", fontSize: 11.5, color: "var(--faint)" }}>computed locally</span>
              </div>
              {m.rows.map((r, i) => (
                <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 14, padding: "11px 14px", borderBottom: "1px solid var(--border)" }}>
                  <span style={{ fontSize: 13, color: "var(--dim)" }}>{r.label}</span>
                  <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13.5, color: r.color || "var(--text)" }}>{r.value}</span>
                </div>
              ))}
            </div>

            {m.alert && (
              <div style={{ display: "flex", gap: 11, marginTop: 14, padding: "13px 14px", border: `1px solid ${m.alertColor}`, borderRadius: 12, background: m.alertSoft }}>
                <span style={{ flex: "none", display: "grid", placeItems: "center", width: 18, height: 18, borderRadius: "50%", background: m.alertColor, color: "#0B1020", fontSize: 12, fontWeight: 700 }}>!</span>
                <div>
                  <div style={{ fontSize: 13, fontWeight: 600, color: m.alertColor }}>{m.alertTitle}</div>
                  <div style={{ marginTop: 4, fontSize: 12.5, color: "var(--dim)" }}>{m.alertBody}</div>
                </div>
              </div>
            )}

            <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
              <button
                onClick={closeModal}
                style={{ flex: "none", height: 44, padding: "0 18px", border: "1px solid var(--border2)", borderRadius: 11, background: "none", color: "var(--dim)", fontSize: 14, fontWeight: 500 }}
              >
                Cancel
              </button>
              <button
                onClick={() => confirm()}
                disabled={m.disabled || txPending}
                style={{ flex: 1, height: 44, border: 0, borderRadius: 11, background: m.ctaBg, color: m.ctaFg, fontSize: 14.5, fontWeight: 600, opacity: txPending ? 0.7 : 1 }}
              >
                {txPending ? "Confirming onchain…" : m.cta}
              </button>
            </div>
            <div style={{ marginTop: 12, fontSize: 12, color: "var(--faint)", textAlign: "center" }}>{m.foot}</div>
          </div>
        )}

        {isSuccess && (
          <div style={{ padding: "20px 22px 22px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, padding: 16, border: "1px solid var(--border)", borderRadius: 12, background: "var(--greensoft)" }}>
              <span style={{ flex: "none", display: "grid", placeItems: "center", width: 30, height: 30, borderRadius: "50%", background: "var(--green)", color: "#04120C", fontSize: 15, fontWeight: 700 }}>✓</span>
              <div>
                <div style={{ fontSize: 14, fontWeight: 600, color: "var(--green)" }}>{m.successTitle}</div>
                <div style={{ marginTop: 3, fontSize: 12.5, color: "var(--dim)" }}>{m.successSub}</div>
              </div>
            </div>
            <div style={{ marginTop: 14, border: "1px solid var(--border)", borderRadius: 12, overflow: "hidden" }}>
              {ui.applied.map((r, i) => (
                <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 14, padding: "11px 14px", borderBottom: "1px solid var(--border)" }}>
                  <span style={{ fontSize: 13, color: "var(--dim)" }}>{r.label}</span>
                  <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13.5, color: r.color || "var(--text)" }}>{r.value}</span>
                </div>
              ))}
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 14, fontSize: 12.5, color: "var(--faint)" }}>
              Position re-encrypted. A fresh health proof was submitted with this transaction.
            </div>
            <button
              onClick={closeModal}
              style={{ width: "100%", height: 44, marginTop: 18, border: 0, borderRadius: 11, background: "var(--gold)", color: "#0B1020", fontSize: 14.5, fontWeight: 600 }}
            >
              Back to dashboard
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
