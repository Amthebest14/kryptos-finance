// Ported verbatim from the approved Kryptos Finance design mockup.
// Keep this in lockstep with the design source if the underlying formulas change.
import { LIVE_PRICES as P, MOCK_LIQ_THRESHOLD as LT, MOCK_MAX_LTV as MX } from "./mock";

export type Balances = Record<string, number>;

export function val(m: Balances): number {
  return Object.keys(m).reduce((s, k) => s + m[k] * (P[k] ?? 0), 0);
}

export function thr(m: Balances): number {
  return Object.keys(m).reduce((s, k) => s + m[k] * (P[k] ?? 0) * (LT[k] ?? 0), 0);
}

export function pow(m: Balances): number {
  return Object.keys(m).reduce((s, k) => s + m[k] * (P[k] ?? 0) * (MX[k] ?? 0), 0);
}

export function hf(sup: Balances, bor: Balances): number {
  const d = val(bor);
  return d <= 0.01 ? Infinity : thr(sup) / d;
}

export function usd(n: number): string {
  if (!isFinite(n)) return "—";
  if (Math.abs(n) >= 1e6) return "$" + (n / 1e6).toFixed(2) + "M";
  return "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function amt(n: number, sym: string): string {
  const d = sym === "USDC" || sym === "USDT" || sym === "ZEN" ? 2 : 4;
  return n.toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d }) + " " + sym;
}

export function hfStr(h: number): string {
  return isFinite(h) ? h.toFixed(2) : "∞";
}

export function zone(h: number): { label: string; color: string; soft: string } {
  if (!isFinite(h) || h >= 1.6) return { label: "Healthy", color: "var(--green)", soft: "var(--greensoft)" };
  if (h >= 1.3) return { label: "Moderate", color: "var(--amber)", soft: "var(--ambersoft)" };
  if (h >= 1.0) return { label: "At risk", color: "var(--red)", soft: "var(--redsoft)" };
  return { label: "Liquidatable", color: "var(--red)", soft: "var(--redsoft)" };
}

export function pct(h: number): string {
  if (!isFinite(h)) return "100%";
  const p = Math.max(0, Math.min(1, (h - 1) / 2)) * 100;
  return p.toFixed(1) + "%";
}

export function num(s: string): number {
  const n = parseFloat(String(s).replace(/,/g, ""));
  return isFinite(n) && n > 0 ? n : 0;
}

export function spark(arr: number[]): string {
  const mn = Math.min(...arr);
  const mx = Math.max(...arr);
  const r = mx - mn || 1;
  return arr
    .map((v, i) => (i * (100 / (arr.length - 1))).toFixed(1) + "," + (26 - ((v - mn) / r) * 24).toFixed(1))
    .join(" ");
}
