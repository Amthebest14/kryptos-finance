import { useApp } from "../state/AppContext";
import { AssetBadge } from "../components/AssetBadge";
import { FAUCET_AMOUNTS } from "../lib/contracts";
import { TINT, BADGE, MARKET_ASSETS, NAME, LIVE_PRICES as P, LOGO_URL } from "../lib/mock";
import { amt, usd, pct } from "../lib/math";

const ACTION_LABELS = ["Deposit", "Borrow", "Repay", "Withdraw"] as const;
const ACTION_KIND = { Deposit: "deposit", Borrow: "borrow", Repay: "repay", Withdraw: "withdraw" } as const;
const pctStr = (n: number | undefined) => (n ?? 0).toFixed(2) + "%";

export function Dashboard() {
  const { account, localPosition, chainData, priceInfo, accountData, proofStatus, hfValue, hfDisplay, hfZone, collateralUsd, debtUsd, availableUsd, hasPosition, open, refreshProof, autoRefreshEnabled, setAutoRefreshEnabled, settlePosition, mintTestTokens, txPending } = useApp();
  const badge = (k: string) => BADGE[k] || k.slice(0, 2).toUpperCase();

  return (
    <main style={{ maxWidth: 1280, margin: "0 auto", padding: "32px 24px 80px" }}>
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-end", justifyContent: "space-between", gap: 16 }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 26, letterSpacing: "-0.025em", fontWeight: 600 }}>Your position</h1>
          <p style={{ margin: "7px 0 0", fontSize: 13.5, color: "var(--dim)" }}>
            {account
              ? `Everything in this section is decrypted locally for wallet ${account.slice(0, 6)}…${account.slice(-4)}. It is not readable by the protocol, other users, or the public dashboards.`
              : "Connect a wallet to open or view a private position."}
          </p>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "6px 11px", border: "1px solid var(--border)", borderRadius: 8, background: "var(--goldsoft)", color: "var(--goldtext)", fontSize: 12, fontWeight: 500 }}>
          Visible only to you
        </div>
      </div>

      {account && (
        <div style={{ marginTop: 22, padding: "18px 22px", border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
          <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
            <div>
              <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Testnet faucet</div>
              <div style={{ marginTop: 4, fontSize: 12.5, color: "var(--dim)" }}>
                Free test tokens on Horizen Testnet only — these are our own mock WETH/USDC/ZEN, worth nothing.
              </div>
            </div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              {MARKET_ASSETS.map((k) => {
                const status = accountData.faucetStatus[k];
                const claimed = status && !status.canClaim;
                const disabled = txPending || claimed;
                return (
                  <button
                    key={k}
                    onClick={() => mintTestTokens(k)}
                    disabled={disabled}
                    title={claimed ? `Resets ${new Date(status.nextClaimAt * 1000).toUTCString()}` : undefined}
                    style={{ display: "flex", alignItems: "center", gap: 8, height: 36, padding: "0 14px", border: "1px solid var(--border2)", borderRadius: 9, background: "var(--surface2)", color: claimed ? "var(--faint)" : "var(--text)", fontSize: 12.5, fontWeight: 550, opacity: disabled ? 0.6 : 1 }}
                  >
                    <AssetBadge initial={badge(k)} tint={TINT[k]} size={18} logoUrl={LOGO_URL[k]} />
                    {claimed ? `${k} claimed today` : `Get ${FAUCET_AMOUNTS[k].toLocaleString()} ${k}`}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {hasPosition ? (
        <>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 16, marginTop: 22 }}>
            <div style={{ flex: "1 1 480px", minWidth: 0, padding: 26, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
              <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-start", justifyContent: "space-between", gap: 20 }}>
                <div>
                  <div style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>
                    Health factor
                  </div>
                  <div style={{ display: "flex", alignItems: "baseline", gap: 14, marginTop: 8 }}>
                    <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 76, lineHeight: 0.9, fontWeight: 500, letterSpacing: "-0.045em", color: hfZone.color }}>{hfDisplay}</span>
                    <span style={{ fontSize: 13.5, fontWeight: 550, color: hfZone.color }}>{hfZone.label}</span>
                  </div>
                  <div style={{ marginTop: 12, fontSize: 13, color: "var(--dim)" }}>Liquidation begins at 1.00. Only you can see this number — the protocol verifies it through a proof.</div>
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 14, minWidth: 200 }}>
                  <div>
                    <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Collateral</div>
                    <div style={{ marginTop: 5, fontFamily: "'Geist Mono',monospace", fontSize: 22 }}>{collateralUsd}</div>
                  </div>
                  <div>
                    <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Borrowed</div>
                    <div style={{ marginTop: 5, fontFamily: "'Geist Mono',monospace", fontSize: 22 }}>{debtUsd}</div>
                  </div>
                  <div>
                    <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Available to borrow</div>
                    <div style={{ marginTop: 5, fontFamily: "'Geist Mono',monospace", fontSize: 22 }}>{availableUsd}</div>
                  </div>
                </div>
              </div>
              <div style={{ marginTop: 30 }}>
                <div style={{ position: "relative", height: 8, borderRadius: 99, background: "linear-gradient(90deg,var(--red) 0 12%,var(--amber) 12% 30%,var(--green) 30% 100%)", opacity: 0.9 }} />
                <div style={{ position: "relative", height: 0 }}>
                  <div style={{ position: "absolute", top: -14, left: pct(hfValue), transform: "translateX(-50%)", width: 3, height: 20, borderRadius: 2, background: "var(--text)", boxShadow: "0 0 0 3px var(--bg)" }} />
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", marginTop: 16, fontFamily: "'Geist Mono',monospace", fontSize: 11.5, color: "var(--faint)" }}>
                  <span>1.00 liquidation</span>
                  <span>1.30 at risk</span>
                  <span>1.60 healthy</span>
                  <span>3.00+</span>
                </div>
              </div>
            </div>

            <div style={{ flex: "1 1 300px", minWidth: 0, display: "flex", flexDirection: "column", gap: 16 }}>
              <div style={{ padding: 22, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
                  <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Health proof</div>
                  <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "5px 10px", borderRadius: 999, background: proofStatus.soft, color: proofStatus.color, fontSize: 12, fontWeight: 600 }}>
                    <span style={{ width: 6, height: 6, borderRadius: "50%", background: proofStatus.color }} />
                    {proofStatus.label}
                  </div>
                </div>
                <div style={{ marginTop: 14, fontSize: 14, color: "var(--text)" }}>{proofStatus.line}</div>
                <div style={{ marginTop: 6, fontSize: 13, color: "var(--dim)" }}>{proofStatus.help}</div>
                <button
                  onClick={() => refreshProof()}
                  disabled={txPending}
                  style={{ width: "100%", height: 38, marginTop: 16, border: "1px solid var(--border2)", borderRadius: 9, background: "none", color: "var(--text)", fontSize: 13, fontWeight: 550, opacity: txPending ? 0.6 : 1 }}
                >
                  {txPending ? "Submitting…" : "Refresh proof now"}
                </button>
                <div style={{ marginTop: 8, fontSize: 11, color: "var(--faint)" }}>Position #{accountData.positionId} · real onchain check-in, verified by a genuine Circuit A zero-knowledge proof</div>
                <label style={{ display: "flex", alignItems: "center", gap: 9, marginTop: 14, paddingTop: 14, borderTop: "1px solid var(--border)", fontSize: 12.5, color: "var(--dim)", cursor: "pointer" }}>
                  <input
                    type="checkbox"
                    checked={autoRefreshEnabled}
                    onChange={(e) => setAutoRefreshEnabled(e.target.checked)}
                    style={{ width: 15, height: 15, accentColor: "var(--accent)" }}
                  />
                  Auto-refresh while this tab is open
                </label>
                <div style={{ marginTop: 6, fontSize: 11, color: "var(--faint)" }}>
                  Renews shortly before every 30-minute check-in, no click needed. Only works while this tab stays open — your collateral, debt, and salt never
                  leave this device, so nothing else could renew it on your behalf.
                </div>
                {accountData.isStale && (
                  <>
                    <button
                      onClick={() => {
                        if (window.confirm("This closes your position onchain via a real reveal proof and cannot be undone — this wallet will not be able to open a new position on this deployment again afterward. Continue?")) {
                          settlePosition();
                        }
                      }}
                      disabled={txPending}
                      style={{ width: "100%", height: 38, marginTop: 10, border: "1px solid var(--red)", borderRadius: 9, background: "none", color: "var(--red)", fontSize: 13, fontWeight: 550, opacity: txPending ? 0.6 : 1 }}
                    >
                      {txPending ? "Submitting…" : "Settle now (self-liquidate)"}
                    </button>
                    <div style={{ marginTop: 8, fontSize: 11, color: "var(--faint)" }}>
                      Reveals and closes this position via a real Circuit R proof, rather than racing the check-in. Irreversible — see the confirm dialog.
                    </div>
                  </>
                )}
              </div>
              <div style={{ padding: 22, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
                <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Actions</div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 9, marginTop: 14 }}>
                  {ACTION_LABELS.map((label) => (
                    <button
                      key={label}
                      onClick={() => open(ACTION_KIND[label])}
                      style={{ height: 40, border: "1px solid var(--border2)", borderRadius: 9, background: "var(--surface2)", color: "var(--text)", fontSize: 13.5, fontWeight: 550 }}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(400px,1fr))", gap: 16, marginTop: 16 }}>
            <div style={{ minWidth: 0, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", overflow: "hidden" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "18px 22px", borderBottom: "1px solid var(--border)" }}>
                <span style={{ fontSize: 14, fontWeight: 600 }}>Supplied collateral</span>
                <span style={{ marginLeft: "auto", fontFamily: "'Geist Mono',monospace", fontSize: 13, color: "var(--dim)" }}>{collateralUsd}</span>
              </div>
              {Object.keys(localPosition.supplied).map((k) => (
                <div key={k} style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 12, padding: "14px 22px", borderBottom: "1px solid var(--border)" }}>
                  <AssetBadge initial={badge(k)} tint={TINT[k]} size={30} logoUrl={LOGO_URL[k]} />
                  <div style={{ minWidth: 74 }}>
                    <div style={{ fontSize: 13.5, fontWeight: 550 }}>{k}</div>
                    <div style={{ fontSize: 12, color: "var(--faint)" }}>{pctStr(chainData.rates[k]?.supplyApyPct)} APY</div>
                  </div>
                  <div style={{ marginLeft: "auto", textAlign: "right", whiteSpace: "nowrap" }}>
                    <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 14 }}>{amt(localPosition.supplied[k], k)}</div>
                    <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12, color: "var(--faint)" }}>{usd(localPosition.supplied[k] * (P[k] ?? 0))}</div>
                  </div>
                  <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "flex-end", gap: 6, marginLeft: 14 }}>
                    <button onClick={() => open("deposit", k)} style={{ height: 30, padding: "0 11px", border: "1px solid var(--border2)", borderRadius: 7, background: "none", color: "var(--text)", fontSize: 12.5 }}>
                      Deposit
                    </button>
                    <button onClick={() => open("withdraw", k)} style={{ height: 30, padding: "0 11px", border: "1px solid var(--border2)", borderRadius: 7, background: "none", color: "var(--dim)", fontSize: 12.5 }}>
                      Withdraw
                    </button>
                  </div>
                </div>
              ))}
              <div style={{ padding: "13px 22px", fontSize: 12.5, color: "var(--faint)" }}>Amounts stored encrypted. Deposits and withdrawals settle without revealing balances onchain.</div>
            </div>

            <div style={{ minWidth: 0, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", overflow: "hidden" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "18px 22px", borderBottom: "1px solid var(--border)" }}>
                <span style={{ fontSize: 14, fontWeight: 600 }}>Borrowed</span>
                <span style={{ marginLeft: "auto", fontFamily: "'Geist Mono',monospace", fontSize: 13, color: "var(--dim)" }}>{debtUsd}</span>
              </div>
              {Object.keys(localPosition.borrowed).map((k) => (
                <div key={k} style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 12, padding: "14px 22px", borderBottom: "1px solid var(--border)" }}>
                  <AssetBadge initial={badge(k)} tint={TINT[k]} size={30} logoUrl={LOGO_URL[k]} />
                  <div style={{ minWidth: 74 }}>
                    <div style={{ fontSize: 13.5, fontWeight: 550 }}>{k}</div>
                    <div style={{ fontSize: 12, color: "var(--faint)" }}>{pctStr(chainData.rates[k]?.borrowAprPct)} APR</div>
                  </div>
                  <div style={{ marginLeft: "auto", textAlign: "right", whiteSpace: "nowrap" }}>
                    <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 14 }}>{amt(localPosition.borrowed[k], k)}</div>
                    <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12, color: "var(--faint)" }}>{usd(localPosition.borrowed[k] * (P[k] ?? 0))}</div>
                  </div>
                  <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "flex-end", gap: 6, marginLeft: 14 }}>
                    <button onClick={() => open("repay", k)} style={{ height: 30, padding: "0 11px", border: "1px solid var(--border2)", borderRadius: 7, background: "none", color: "var(--text)", fontSize: 12.5 }}>
                      Repay
                    </button>
                    <button onClick={() => open("borrow", k)} style={{ height: 30, padding: "0 11px", border: "1px solid var(--border2)", borderRadius: 7, background: "none", color: "var(--dim)", fontSize: 12.5 }}>
                      Borrow
                    </button>
                  </div>
                </div>
              ))}
              <div style={{ padding: "13px 22px", fontSize: 12.5, color: "var(--faint)" }}>
                Interest accrues against each market's public rate and is folded into your borrow/repay proofs automatically — computed on this device from
                your own private balance, since the protocol can't read it to check the math itself.
              </div>
            </div>
          </div>
        </>
      ) : (
        <div style={{ marginTop: 22, padding: "56px 32px", border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", textAlign: "center" }}>
          <div style={{ display: "grid", placeItems: "center", width: 46, height: 46, margin: "0 auto", borderRadius: 12, background: "var(--goldsoft)" }} />
          <h2 style={{ margin: "20px 0 0", fontSize: 22, letterSpacing: "-0.02em", fontWeight: 600 }}>{account ? "No open position yet" : "Wallet not connected"}</h2>
          <p style={{ margin: "10px auto 0", maxWidth: "52ch", fontSize: 14, lineHeight: 1.55, color: "var(--dim)" }}>
            {account
              ? "Deposit collateral to open a private position. From the moment it exists, your collateral, debt and health factor are encrypted — you prove the position is healthy without revealing the numbers."
              : "Connect a wallet on Horizen Testnet (chain 2651420) to deposit collateral and open a position."}
          </p>
          <div style={{ display: "flex", justifyContent: "center", gap: 10, marginTop: 24 }}>
            <button onClick={() => open("deposit")} style={{ height: 42, padding: "0 20px", border: 0, borderRadius: 10, background: "var(--gold)", color: "#0B1020", fontSize: 14, fontWeight: 600 }}>
              Deposit collateral
            </button>
            <a href="#markets" style={{ display: "grid", placeItems: "center", height: 42, padding: "0 18px", border: "1px solid var(--border2)", borderRadius: 10, color: "var(--text)", fontSize: 14, fontWeight: 500 }}>
              See the markets below
            </a>
          </div>
        </div>
      )}

      <section id="markets" style={{ marginTop: 38 }}>
        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-end", justifyContent: "space-between", gap: 12 }}>
          <div>
            <h2 style={{ margin: 0, fontSize: 19, letterSpacing: "-0.02em", fontWeight: 600 }}>Markets</h2>
            <p style={{ margin: "6px 0 0", fontSize: 13, color: "var(--dim)" }}>
              Real onchain totals from VaultManager, priced live. Rates are computed live from InterestRateModel.sol's utilization curve — Supply APY is the
              curve's rate, not yield you're currently earning, since VaultManager doesn't distribute interest to depositors yet.
            </p>
          </div>
          <div style={{ fontSize: 11.5, color: "var(--faint)", textAlign: "right" }}>
            Prices: WETH &amp; USDC live via Pyth
            {priceInfo.ZEN?.source === "coingecko" ? ", ZEN via CoinGecko" : priceInfo.ZEN?.source === "unavailable" ? ", ZEN price unavailable" : ""}
          </div>
        </div>
        <div style={{ marginTop: 16, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", overflow: "hidden" }}>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", minWidth: 860, borderCollapse: "collapse" }}>
              <thead>
                <tr>
                  {["Asset", "Supply APY", "Borrow APR", "Total supplied", "Total borrowed", "Utilization"].map((h, i) => (
                    <th key={h} style={{ textAlign: i === 0 ? "left" : "right", padding: i === 0 ? "13px 22px" : "13px 16px", fontSize: 11.5, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--faint)", fontWeight: 600, borderBottom: "1px solid var(--border)" }}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {MARKET_ASSETS.map((k) => {
                  const supplied = chainData.totalSupplied[k] ?? 0;
                  const borrowed = chainData.totalBorrowed[k] ?? 0;
                  const util = supplied > 0 ? (borrowed / supplied) * 100 : 0;
                  return (
                    <tr key={k}>
                      <td style={{ padding: "14px 22px", borderBottom: "1px solid var(--border)" }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 11 }}>
                          <AssetBadge initial={badge(k)} tint={TINT[k]} size={28} logoUrl={LOGO_URL[k]} />
                          <div>
                            <div style={{ fontSize: 13.5, fontWeight: 550 }}>{k}</div>
                            <div style={{ fontSize: 12, color: "var(--faint)" }}>{NAME[k]}</div>
                          </div>
                        </div>
                      </td>
                      <td style={{ padding: "14px 16px", textAlign: "right", fontFamily: "'Geist Mono',monospace", fontSize: 13.5, color: "var(--green)", borderBottom: "1px solid var(--border)" }}>{pctStr(chainData.rates[k]?.supplyApyPct)}</td>
                      <td style={{ padding: "14px 16px", textAlign: "right", fontFamily: "'Geist Mono',monospace", fontSize: 13.5, borderBottom: "1px solid var(--border)" }}>{pctStr(chainData.rates[k]?.borrowAprPct)}</td>
                      <td style={{ padding: "14px 16px", textAlign: "right", fontFamily: "'Geist Mono',monospace", fontSize: 13.5, color: "var(--dim)", borderBottom: "1px solid var(--border)" }}>{amt(supplied, k)}</td>
                      <td style={{ padding: "14px 16px", textAlign: "right", fontFamily: "'Geist Mono',monospace", fontSize: 13.5, color: "var(--dim)", borderBottom: "1px solid var(--border)" }}>{amt(borrowed, k)}</td>
                      <td style={{ padding: "14px 22px", borderBottom: "1px solid var(--border)" }}>
                        <div style={{ display: "flex", alignItems: "center", justifyContent: "flex-end", gap: 10 }}>
                          <div style={{ width: 56, height: 5, borderRadius: 99, background: "var(--raise)", overflow: "hidden" }}>
                            <div style={{ height: "100%", borderRadius: 99, background: "var(--gold)", width: util.toFixed(1) + "%" }} />
                          </div>
                          <span style={{ fontFamily: "'Geist Mono',monospace", fontSize: 13, minWidth: 52, textAlign: "right" }}>{util.toFixed(1)}%</span>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </main>
  );
}
