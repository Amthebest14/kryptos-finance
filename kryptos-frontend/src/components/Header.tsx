import { Link, useLocation, useNavigate } from "react-router-dom";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useApp } from "../state/AppContext";

const NAVS = [
  { path: "/dashboard", label: "Dashboard" },
  { path: "/liquidations", label: "Liquidations" },
  { path: "/stats", label: "Stats" },
  { path: "/staking", label: "Staking" },
  { path: "/exposure", label: "Exposure" },
];

export function Header() {
  const { ui, toggleTheme } = useApp();
  const location = useLocation();
  const navigate = useNavigate();

  return (
    <header
      style={{
        position: "sticky",
        top: 0,
        zIndex: 40,
        display: "flex",
        alignItems: "center",
        gap: 32,
        height: 64,
        padding: "0 24px",
        background: "var(--bg)",
        borderBottom: "1px solid var(--border)",
      }}
    >
      <Link to="/" style={{ display: "flex", alignItems: "center", gap: 10, color: "var(--text)" }}>
        <img src="/logo-64.png" alt="" width={26} height={26} style={{ borderRadius: 7, display: "block" }} />
        <span style={{ fontWeight: 600, fontSize: 15, letterSpacing: "-0.01em", whiteSpace: "nowrap" }}>Kryptos Finance</span>
      </Link>

      <nav style={{ display: "flex", alignItems: "center", gap: 4, flex: 1, overflow: "auto" }}>
        {NAVS.map((n) => {
          const active = location.pathname === n.path;
          return (
            <button
              key={n.path}
              onClick={() => navigate(n.path)}
              style={{
                position: "relative",
                padding: "8px 12px",
                border: 0,
                background: active ? "var(--surface2)" : "none",
                borderRadius: 8,
                color: active ? "var(--text)" : "var(--dim)",
                fontSize: 13.5,
                fontWeight: active ? 550 : 500,
                whiteSpace: "nowrap",
              }}
            >
              {n.label}
            </button>
          );
        })}
      </nav>

      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <button
          onClick={toggleTheme}
          style={{
            height: 34,
            padding: "0 12px",
            border: "1px solid var(--border)",
            background: "none",
            borderRadius: 8,
            color: "var(--dim)",
            fontSize: 12,
            fontWeight: 500,
            letterSpacing: "0.02em",
          }}
        >
          {ui.theme === "dark" ? "Light" : "Dark"}
        </button>
        <ConnectButton.Custom>
          {({ account, chain, openConnectModal, openAccountModal, openChainModal, mounted }) => {
            const ready = mounted;
            const connected = ready && account && chain;
            return (
              <div style={{ display: ready ? "block" : "none" }}>
                {!connected ? (
                  <button
                    onClick={openConnectModal}
                    style={{ height: 34, padding: "0 14px", border: 0, background: "var(--gold)", borderRadius: 8, color: "#0B1020", fontSize: 13, fontWeight: 600 }}
                  >
                    Connect wallet
                  </button>
                ) : chain.unsupported ? (
                  <button
                    onClick={openChainModal}
                    style={{ height: 34, padding: "0 14px", border: "1px solid var(--red)", background: "var(--redsoft)", borderRadius: 8, color: "var(--red)", fontSize: 13, fontWeight: 600 }}
                  >
                    Wrong network
                  </button>
                ) : (
                  <button
                    onClick={openAccountModal}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 8,
                      height: 34,
                      padding: "0 12px",
                      border: "1px solid var(--border)",
                      background: "var(--surface)",
                      borderRadius: 8,
                    }}
                  >
                    <span style={{ width: 7, height: 7, borderRadius: "50%", background: "var(--green)", boxShadow: "0 0 0 3px var(--greensoft)" }} />
                    <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--text)" }}>
                      {account.address.slice(0, 6)}…{account.address.slice(-4)}
                    </span>
                  </button>
                )}
              </div>
            );
          }}
        </ConnectButton.Custom>
      </div>
    </header>
  );
}
