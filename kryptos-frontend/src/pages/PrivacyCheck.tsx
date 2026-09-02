import { useCallback, useEffect, useState } from "react";
import { Contract, EventLog, JsonRpcProvider, formatEther, isAddress } from "ethers";
import { useApp } from "../state/AppContext";
import { ADDRESSES, DEPLOY_BLOCK, RPC_URL, VAULT_ABI, ASSET_ADDRESS } from "../lib/contracts";
import { MARKET_ASSETS, LIVE_PRICES as P } from "../lib/mock";
import { hf, hfStr, zone, usd, amt } from "../lib/math";

// Deliberately built as a real demonstration of the system's known privacy
// limitation rather than a paragraph about it: this page does exactly what
// any outside observer already could —
// replay one address's public Deposited/Withdrawn/Borrowed/Repaid history
// and sum it. Nothing here reads anything the app itself doesn't already
// emit publicly; it's the reconstruction technique made visible, not a new
// access path. Read-only, no wallet signature needed to run it, works for
// any address (yours or someone else's — that's the point).
type EventRow = {
  blockNumber: number;
  logIndex: number;
  kind: "Deposited" | "Withdrawn" | "Borrowed" | "Repaid" | "Liquidated";
  asset: string; // collateral asset for a Liquidated row
  amount: number; // collateral amount seized for a Liquidated row
  debtAsset?: string; // Liquidated only
  debtAmount?: number; // Liquidated only
  timestamp: number | null;
  txHash: string;
};

type Snapshot = { after: EventRow; collateral: Record<string, number>; debt: Record<string, number> };

const symOf = (addr: string) => Object.entries(ASSET_ADDRESS).find(([, a]) => a.toLowerCase() === addr.toLowerCase())?.[0] || addr.slice(0, 8);

export function PrivacyCheck() {
  const { account } = useApp();
  const [input, setInput] = useState("");
  const [checked, setChecked] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [timeline, setTimeline] = useState<Snapshot[]>([]);

  useEffect(() => {
    if (account && !input) setInput(account);
  }, [account, input]);

  const run = useCallback(async (target: string) => {
    if (!isAddress(target)) {
      setError("That's not a valid address.");
      return;
    }
    setLoading(true);
    setError(null);
    setChecked(target);
    try {
      const provider = new JsonRpcProvider(RPC_URL, undefined, { batchMaxCount: 1 });
      const vault = new Contract(ADDRESSES.vault, VAULT_ABI, provider);

      const kinds: ("Deposited" | "Withdrawn" | "Borrowed" | "Repaid")[] = ["Deposited", "Withdrawn", "Borrowed", "Repaid"];
      const rowsByKind = await Promise.all(
        kinds.map(async (kind) => {
          const logs = (await vault.queryFilter(vault.filters[kind](target), DEPLOY_BLOCK, "latest")).filter((e): e is EventLog => e instanceof EventLog);
          return logs.map((e) => ({
            row: {
              blockNumber: e.blockNumber,
              logIndex: e.index,
              kind,
              asset: symOf(e.args.asset as string),
              amount: Number(formatEther(e.args.amount as bigint)),
              timestamp: null as number | null,
              txHash: e.transactionHash,
            } as EventRow,
            positionId: (e.args.positionId as bigint).toString(),
          }));
        })
      );
      const directRows = rowsByKind.flat();

      // A liquidated position never emits Withdrawn/Repaid for what it lost —
      // seizeAndRepay moves the seized collateral and repaid debt outside
      // that mechanism entirely (see VaultManager.sol). Missing this would
      // silently overcount: a wallet whose position was liquidated would
      // still show its pre-liquidation collateral as if it were still
      // theirs. Seized isn't indexed by user (only by position), so every
      // distinct position this address has ever opened gets its own query.
      const positionIds = [...new Set(directRows.map((r) => r.positionId))];
      const seizedByPosition = await Promise.all(
        positionIds.map(async (positionId) => {
          const logs = (await vault.queryFilter(vault.filters.Seized(positionId), DEPLOY_BLOCK, "latest")).filter((e): e is EventLog => e instanceof EventLog);
          return logs.map(
            (e): EventRow => ({
              blockNumber: e.blockNumber,
              logIndex: e.index,
              kind: "Liquidated",
              asset: symOf(e.args.collateralAsset as string),
              amount: Number(formatEther(e.args.collateralAmount as bigint)),
              debtAsset: symOf(e.args.debtAsset as string),
              debtAmount: Number(formatEther(e.args.debtRepaid as bigint)),
              timestamp: null,
              txHash: e.transactionHash,
            })
          );
        })
      );

      const rows = [...directRows.map((r) => r.row), ...seizedByPosition.flat()].sort(
        (a, b) => a.blockNumber - b.blockNumber || a.logIndex - b.logIndex
      );

      // Timestamps are a courtesy for the timeline display, not load-bearing
      // for the reconstruction itself — fetched best-effort, one block per
      // unique block number actually involved, not one call per event.
      const uniqueBlocks = [...new Set(rows.map((r) => r.blockNumber))];
      const blockTimes = new Map<number, number>();
      await Promise.all(
        uniqueBlocks.map(async (bn) => {
          try {
            const b = await provider.getBlock(bn);
            if (b) blockTimes.set(bn, b.timestamp);
          } catch {
            // best-effort
          }
        })
      );
      rows.forEach((r) => (r.timestamp = blockTimes.get(r.blockNumber) ?? null));

      const collateral: Record<string, number> = {};
      const debt: Record<string, number> = {};
      const snapshots: Snapshot[] = [];
      for (const row of rows) {
        if (row.kind === "Deposited") collateral[row.asset] = (collateral[row.asset] ?? 0) + row.amount;
        if (row.kind === "Withdrawn") collateral[row.asset] = (collateral[row.asset] ?? 0) - row.amount;
        if (row.kind === "Borrowed") debt[row.asset] = (debt[row.asset] ?? 0) + row.amount;
        if (row.kind === "Repaid") debt[row.asset] = (debt[row.asset] ?? 0) - row.amount;
        if (row.kind === "Liquidated") {
          collateral[row.asset] = (collateral[row.asset] ?? 0) - row.amount;
          if (row.debtAsset) debt[row.debtAsset] = (debt[row.debtAsset] ?? 0) - (row.debtAmount ?? 0);
        }
        snapshots.push({ after: row, collateral: { ...collateral }, debt: { ...debt } });
      }
      setTimeline(snapshots);
    } catch (err) {
      console.error(err);
      setError("Couldn't read this address's history — the RPC may be temporarily unavailable, try again.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (account) run(account);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account]);

  const latest = timeline[timeline.length - 1];
  const supplied = latest?.collateral ?? {};
  const borrowed = latest?.debt ?? {};
  const health = hf(supplied, borrowed);
  const z = zone(health);
  const suppliedUsd = MARKET_ASSETS.reduce((s, k) => s + (supplied[k] ?? 0) * (P[k] ?? 0), 0);
  const borrowedUsd = MARKET_ASSETS.reduce((s, k) => s + (borrowed[k] ?? 0) * (P[k] ?? 0), 0);

  return (
    <main style={{ maxWidth: 900, margin: "0 auto", padding: "32px 24px 80px" }}>
      <h1 style={{ margin: 0, fontSize: 26, letterSpacing: "-0.025em", fontWeight: 600 }}>Exposure check</h1>
      <p style={{ margin: "8px 0 0", maxWidth: "72ch", fontSize: 14, lineHeight: 1.6, color: "var(--dim)" }}>
        Kryptos never stores anyone's collateral, debt, or health factor in the clear. But every deposit, withdrawal, borrow, and repay moves a real,
        public token amount — and those amounts are permanently visible on-chain. This page does exactly what a patient outside observer already could:
        replay one address's public history and add it up. Nothing here uses privileged access; it's the reconstruction made visible, not a new leak.
      </p>

      <div style={{ display: "flex", gap: 10, marginTop: 24 }}>
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="0x… any address, yours or anyone's"
          style={{
            flex: 1,
            height: 42,
            padding: "0 14px",
            border: "1px solid var(--border2)",
            borderRadius: 10,
            background: "var(--surface)",
            color: "var(--text)",
            fontFamily: "'Geist Mono',monospace",
            fontSize: 13,
          }}
        />
        <button
          onClick={() => run(input)}
          disabled={loading || !input}
          style={{ height: 42, padding: "0 20px", border: 0, borderRadius: 10, background: "var(--gold)", color: "#0B1020", fontSize: 14, fontWeight: 600, opacity: loading || !input ? 0.5 : 1 }}
        >
          {loading ? "Checking…" : "Check"}
        </button>
      </div>

      {error && (
        <div style={{ marginTop: 16, padding: "12px 16px", border: "1px solid var(--red)", borderRadius: 10, background: "var(--redsoft)", color: "var(--red)", fontSize: 13.5 }}>
          {error}
        </div>
      )}

      {checked && !loading && !error && (
        <>
          <div style={{ marginTop: 28, padding: 24, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10 }}>
              <div style={{ fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--faint)" }}>{checked}</div>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 7, padding: "5px 11px", borderRadius: 999, background: "var(--redsoft)", color: "var(--red)", fontSize: 12, fontWeight: 600 }}>
                What anyone can already reconstruct
              </span>
            </div>

            {timeline.length === 0 ? (
              <div style={{ marginTop: 18, fontSize: 13.5, color: "var(--faint)" }}>
                No public deposit/withdraw/borrow/repay history for this address on this deployment — there's genuinely nothing to reconstruct here yet.
              </div>
            ) : (
              <>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(180px,1fr))", gap: 20, marginTop: 20 }}>
                  <div>
                    <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Reconstructed collateral</div>
                    <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 26, fontWeight: 500 }}>{usd(suppliedUsd)}</div>
                  </div>
                  <div>
                    <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Reconstructed debt</div>
                    <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 26, fontWeight: 500 }}>{usd(borrowedUsd)}</div>
                  </div>
                  <div>
                    <div style={{ fontSize: 11.5, letterSpacing: "0.07em", textTransform: "uppercase", color: "var(--faint)" }}>Reconstructed health factor</div>
                    <div style={{ marginTop: 8, fontFamily: "'Geist Mono',monospace", fontSize: 26, fontWeight: 500, color: z.color }}>{hfStr(health)}</div>
                  </div>
                </div>
                <div style={{ marginTop: 16, display: "flex", flexWrap: "wrap", gap: 16, fontSize: 12.5, color: "var(--faint)" }}>
                  {MARKET_ASSETS.filter((k) => (supplied[k] ?? 0) !== 0).map((k) => (
                    <span key={"s" + k}>
                      collateral: {amt(supplied[k], k)}
                    </span>
                  ))}
                  {MARKET_ASSETS.filter((k) => (borrowed[k] ?? 0) !== 0).map((k) => (
                    <span key={"b" + k}>
                      debt: {amt(borrowed[k], k)}
                    </span>
                  ))}
                </div>
                <p style={{ margin: "16px 0 0", fontSize: 12.5, color: "var(--faint)", lineHeight: 1.55 }}>
                  Computed the same way the app computes your own numbers — collateral value against liquidation-threshold-weighted debt — using only
                  amounts already public in {timeline.length} event{timeline.length === 1 ? "" : "s"} and today's live prices. The app itself never shows
                  you this about another address; this page is proof that a determined outsider, replaying history by hand, already could.
                </p>
              </>
            )}
          </div>

          {timeline.length > 0 && (
            <div style={{ marginTop: 16, border: "1px solid var(--border)", borderRadius: 16, background: "var(--surface)", overflow: "hidden" }}>
              <div style={{ padding: "16px 22px", borderBottom: "1px solid var(--border)", fontSize: 14, fontWeight: 600 }}>
                Reconstructed timeline
              </div>
              <div style={{ overflowX: "auto" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 620 }}>
                  <thead>
                    <tr>
                      {["When", "Action", "Asset", "Amount", "Running collateral", "Running debt"].map((h) => (
                        <th key={h} style={{ textAlign: "left", padding: "10px 22px", fontSize: 11, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--faint)", borderBottom: "1px solid var(--border)" }}>
                          {h}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {timeline.map((s, i) => (
                      <tr key={s.after.txHash + i}>
                        <td style={{ padding: "10px 22px", fontFamily: "'Geist Mono',monospace", fontSize: 12, color: "var(--faint)", borderBottom: "1px solid var(--border)", whiteSpace: "nowrap" }}>
                          {s.after.timestamp ? new Date(s.after.timestamp * 1000).toLocaleString() : `block ${s.after.blockNumber}`}
                        </td>
                        <td style={{ padding: "10px 22px", fontSize: 13, borderBottom: "1px solid var(--border)" }}>{s.after.kind}</td>
                        <td style={{ padding: "10px 22px", fontFamily: "'Geist Mono',monospace", fontSize: 12.5, borderBottom: "1px solid var(--border)" }}>
                          {s.after.kind === "Liquidated" ? `${s.after.asset} / ${s.after.debtAsset}` : s.after.asset}
                        </td>
                        <td style={{ padding: "10px 22px", fontFamily: "'Geist Mono',monospace", fontSize: 12.5, borderBottom: "1px solid var(--border)" }}>
                          {s.after.kind === "Liquidated"
                            ? `seized ${amt(s.after.amount, s.after.asset)}, repaid ${amt(s.after.debtAmount ?? 0, s.after.debtAsset ?? "")}`
                            : amt(s.after.amount, s.after.asset)}
                        </td>
                        <td style={{ padding: "10px 22px", fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--dim)", borderBottom: "1px solid var(--border)" }}>
                          {MARKET_ASSETS.filter((k) => (s.collateral[k] ?? 0) !== 0).map((k) => amt(s.collateral[k], k)).join(", ") || "—"}
                        </td>
                        <td style={{ padding: "10px 22px", fontFamily: "'Geist Mono',monospace", fontSize: 12.5, color: "var(--dim)", borderBottom: "1px solid var(--border)" }}>
                          {MARKET_ASSETS.filter((k) => (s.debt[k] ?? 0) !== 0).map((k) => amt(s.debt[k], k)).join(", ") || "—"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </main>
  );
}
