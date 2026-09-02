import { useState } from "react";
import { useApp } from "../state/AppContext";
import { AssetBadge } from "../components/AssetBadge";
import { TINT, BADGE, LOGO_URL } from "../lib/mock";
import { amt, usd } from "../lib/math";
import { LIVE_PRICES as P } from "../lib/mock";

export function Staking() {
  const { account, accountData, stakingData, stakeZen, unstakeZen, claimReward, txPending } = useApp();
  const [stakeInput, setStakeInput] = useState("");
  const [unstakeInput, setUnstakeInput] = useState("");
  const badge = (k: string) => BADGE[k] || k.slice(0, 2).toUpperCase();

  const zenBalance = accountData.walletBalances.ZEN ?? 0;
  const stakeAmount = Number(stakeInput) || 0;
  const unstakeAmount = Number(unstakeInput) || 0;

  return (
    <main style={{ maxWidth: 1080, margin: "0 auto", padding: "32px 24px 80px" }}>
      <h1 style={{ margin: 0, fontSize: 26, letterSpacing: "-0.025em", fontWeight: 600 }}>ZEN staking</h1>
      <p style={{ margin: "8px 0 0", maxWidth: "72ch", fontSize: 14, lineHeight: 1.55, color: "var(--dim)" }}>
        Stake ZEN to earn a share of self-reported accrued interest, forwarded in whatever asset was actually repaid — WETH, USDC, or ZEN. Unlike the lending
        side, staking is plain ERC20 mechanics with no privacy involved: stake sizes and earned rewards are public, queryable for any address, the same way a
        normal staking contract works.
      </p>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))", gap: 1, marginTop: 24, background: "var(--border)", border: "1px solid var(--border)", borderRadius: 14, overflow: "hidden" }}>
        <div style={{ padding: "20px 22px", background: "var(--surface)" }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Total ZEN staked</div>
          <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 26, fontWeight: 500 }}>{amt(stakingData.totalStaked, "ZEN")}</div>
        </div>
        <div style={{ padding: "20px 22px", background: "var(--surface)" }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Your stake</div>
          <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 26, fontWeight: 500 }}>{account ? amt(stakingData.myStake, "ZEN") : "—"}</div>
        </div>
        <div style={{ padding: "20px 22px", background: "var(--surface)" }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Your pool share</div>
          <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 26, fontWeight: 500 }}>
            {account && stakingData.totalStaked > 0 ? ((stakingData.myStake / stakingData.totalStaked) * 100).toFixed(2) + "%" : "—"}
          </div>
        </div>
      </div>

      {!account ? (
        <div style={{ marginTop: 16, padding: "56px 32px", border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", textAlign: "center" }}>
          <h2 style={{ margin: 0, fontSize: 20, letterSpacing: "-0.02em", fontWeight: 600, color: "var(--faint)" }}>Wallet not connected</h2>
          <p style={{ margin: "10px auto 0", maxWidth: "52ch", fontSize: 14, lineHeight: 1.55, color: "var(--faint)" }}>
            Connect a wallet on Horizen Testnet to stake ZEN and see your rewards.
          </p>
        </div>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(340px,1fr))", gap: 16, marginTop: 16 }}>
          <div style={{ padding: 22, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>Stake</div>
            <div style={{ marginTop: 4, fontSize: 12.5, color: "var(--faint)" }}>Wallet balance: {amt(zenBalance, "ZEN")}</div>
            <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
              <input
                type="number"
                min="0"
                placeholder="0.0"
                value={stakeInput}
                onChange={(e) => setStakeInput(e.target.value)}
                style={{ flex: 1, height: 40, padding: "0 12px", border: "1px solid var(--border2)", borderRadius: 9, background: "var(--surface2)", color: "var(--text)", fontSize: 14, fontFamily: "'Geist Mono',monospace" }}
              />
              <button
                onClick={() => setStakeInput(String(zenBalance))}
                style={{ height: 40, padding: "0 12px", border: "1px solid var(--border2)", borderRadius: 9, background: "none", color: "var(--dim)", fontSize: 12.5 }}
              >
                Max
              </button>
            </div>
            <button
              onClick={() => {
                stakeZen(stakeAmount);
                setStakeInput("");
              }}
              disabled={txPending || stakeAmount <= 0 || stakeAmount > zenBalance}
              style={{ width: "100%", height: 40, marginTop: 12, border: 0, borderRadius: 9, background: "var(--gold)", color: "#0B1020", fontSize: 13.5, fontWeight: 600, opacity: txPending || stakeAmount <= 0 || stakeAmount > zenBalance ? 0.5 : 1 }}
            >
              {txPending ? "Submitting…" : "Stake ZEN"}
            </button>
          </div>

          <div style={{ padding: 22, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>Unstake</div>
            <div style={{ marginTop: 4, fontSize: 12.5, color: "var(--faint)" }}>Currently staked: {amt(stakingData.myStake, "ZEN")}</div>
            <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
              <input
                type="number"
                min="0"
                placeholder="0.0"
                value={unstakeInput}
                onChange={(e) => setUnstakeInput(e.target.value)}
                style={{ flex: 1, height: 40, padding: "0 12px", border: "1px solid var(--border2)", borderRadius: 9, background: "var(--surface2)", color: "var(--text)", fontSize: 14, fontFamily: "'Geist Mono',monospace" }}
              />
              <button
                onClick={() => setUnstakeInput(String(stakingData.myStake))}
                style={{ height: 40, padding: "0 12px", border: "1px solid var(--border2)", borderRadius: 9, background: "none", color: "var(--dim)", fontSize: 12.5 }}
              >
                Max
              </button>
            </div>
            <button
              onClick={() => {
                unstakeZen(unstakeAmount);
                setUnstakeInput("");
              }}
              disabled={txPending || unstakeAmount <= 0 || unstakeAmount > stakingData.myStake}
              style={{ width: "100%", height: 40, marginTop: 12, border: "1px solid var(--border2)", borderRadius: 9, background: "none", color: "var(--text)", fontSize: 13.5, fontWeight: 550, opacity: txPending || unstakeAmount <= 0 || unstakeAmount > stakingData.myStake ? 0.5 : 1 }}
            >
              {txPending ? "Submitting…" : "Unstake ZEN"}
            </button>
          </div>
        </div>
      )}

      {account && (
        <div style={{ marginTop: 16, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", overflow: "hidden" }}>
          <div style={{ padding: "16px 22px", borderBottom: "1px solid var(--border)", fontSize: 14, fontWeight: 600 }}>Your claimable rewards</div>
          {stakingData.rewardAssets.length === 0 ? (
            <div style={{ padding: "40px 22px", textAlign: "center", fontSize: 13.5, color: "var(--faint)" }}>
              No interest revenue has been forwarded to staking yet — real, currently-empty, not a placeholder.
            </div>
          ) : (
            stakingData.rewardAssets.map((sym) => (
              <div key={sym} style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 14, padding: "15px 22px", borderBottom: "1px solid var(--border)" }}>
                <AssetBadge initial={badge(sym)} tint={TINT[sym]} size={28} logoUrl={LOGO_URL[sym]} />
                <div>
                  <div style={{ fontSize: 13.5, fontWeight: 550 }}>{sym}</div>
                  <div style={{ fontSize: 12, color: "var(--faint)" }}>{usd((stakingData.earned[sym] ?? 0) * (P[sym] ?? 0))}</div>
                </div>
                <div style={{ marginLeft: "auto", fontFamily: "'Geist Mono',monospace", fontSize: 14 }}>{amt(stakingData.earned[sym] ?? 0, sym)}</div>
                <button
                  onClick={() => claimReward(sym)}
                  disabled={txPending || (stakingData.earned[sym] ?? 0) <= 0}
                  style={{ height: 34, padding: "0 14px", border: "1px solid var(--border2)", borderRadius: 8, background: "none", color: "var(--text)", fontSize: 12.5, fontWeight: 550, opacity: txPending || (stakingData.earned[sym] ?? 0) <= 0 ? 0.5 : 1 }}
                >
                  Claim
                </button>
              </div>
            ))
          )}
          <div style={{ padding: "13px 22px", fontSize: 12.5, color: "var(--faint)" }}>
            Revenue only exists when a borrower's repay call actually reports accrued interest — see the Dashboard's Borrowed panel. Nothing forces a
            borrower to; an honest frontend does.
          </div>
        </div>
      )}
    </main>
  );
}
