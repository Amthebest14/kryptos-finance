// Ported verbatim from the approved Kryptos Finance design's modalSpec() method.
// Pure function version: no closures/callbacks baked in — the component wires
// its own handlers using the plain data returned here.
import { LIVE_PRICES as P, MOCK_SUPPLY_APY as APY, MOCK_BORROW_APR as APR, TINT, BADGE, MOCK_LIQ_THRESHOLD as LT, MARKET_ASSETS } from "./mock";
import { val, thr, pow, hf, usd, amt, hfStr, zone, num, type Balances } from "./math";
import type { ModalKind } from "./types";

export interface ModalOption {
  symbol: string;
  initial: string;
  tint: string;
  right: string;
}

export interface ModalRow {
  label: string;
  value: string;
  color?: string;
}

export interface ModalSpec {
  title: string;
  sub: string;
  fieldLabel: string;
  maxWord: string;
  balanceLine: string;
  foot: string;
  rows: ModalRow[];
  asset: string;
  initial: string;
  tint: string;
  maxLabel: string;
  max: number;
  options: ModalOption[];
  alert: boolean;
  alertTitle: string;
  alertBody: string;
  alertColor: string;
  alertSoft: string;
  disabled: boolean;
  cta: string;
  ctaBg: string;
  ctaFg: string;
  successTitle: string;
  successSub: string;
  hf1: number;
}

const TONES: Record<string, { color: string; soft: string }> = {
  danger: { color: "var(--red)", soft: "var(--redsoft)" },
  warn: { color: "var(--amber)", soft: "var(--ambersoft)" },
  ok: { color: "var(--green)", soft: "var(--greensoft)" },
};

export function badge(k: string): string {
  return BADGE[k] || k.slice(0, 2).toUpperCase();
}

export function getModalSpec(
  kind: ModalKind,
  asset: string,
  amountStr: string,
  supplied: Balances,
  borrowed: Balances,
  staked: number,
  rewards: number,
  walletBalances: Balances
): ModalSpec | null {
  if (!kind) return null;

  const sup = supplied,
    bor = borrowed;
  const a = asset,
    price = P[a] || 0;
  const n = num(amountStr);
  const hf0 = hf(sup, bor);
  const clone = (o: Balances) => Object.assign({}, o);

  let optionKeys: string[] = [];
  let max = 0,
    hf1 = hf0,
    rows: ModalRow[] = [];
  // Omits ModalSpec's own `alert: boolean` field rather than intersecting
  // with it — this working variable holds the alert as an object while being
  // built, then collapses to a boolean (see `alert: !!spec.alert` below) only
  // in the value actually returned.
  let spec: Omit<Partial<ModalSpec>, "alert"> & { alert?: { t: string; title: string; body: string }; blocked?: boolean } =
    {};

  if (kind === "deposit" || kind === "withdraw") {
    optionKeys = kind === "deposit" ? MARKET_ASSETS : Object.keys(sup);
  } else if (kind === "borrow") {
    optionKeys = MARKET_ASSETS;
  } else if (kind === "repay") {
    optionKeys = Object.keys(bor);
  } else {
    optionKeys = ["ZEN"];
  }

  if (kind === "deposit") {
    max = walletBalances[a] || 0;
    const s2 = clone(sup);
    s2[a] = (s2[a] || 0) + n;
    hf1 = hf(s2, bor);
    spec = {
      title: "Deposit collateral",
      sub: "Encrypted on arrival. The amount is never written in the clear.",
      fieldLabel: "Amount to deposit",
      maxWord: "MAX",
      cta: "Confirm deposit",
      balanceLine: "Wallet balance " + amt(max, a),
      successTitle: "Deposit confirmed",
      successSub: "Collateral added to your private position.",
      foot: "Your new health factor is computed in your browser and never leaves it.",
    };
    rows = [
      { label: "Supplying", value: amt(n, a) },
      { label: "Collateral after", value: usd(val(sup) + n * price) },
      { label: "Health factor", value: hfStr(hf0) + "  →  " + hfStr(hf1), color: zone(hf1).color },
      { label: "Supply APY", value: APY[a] || "—", color: "var(--green)" },
      { label: "Network fee", value: "~$0.42 · proof gas incl.", color: "var(--dim)" },
    ];
  } else if (kind === "borrow") {
    max = Math.max(0, (pow(sup) - val(bor)) / price);
    const b2 = clone(bor);
    b2[a] = (b2[a] || 0) + n;
    hf1 = hf(sup, b2);
    spec = {
      title: "Borrow",
      sub: "Your borrow limit is derived from encrypted collateral — only you see it.",
      fieldLabel: "Amount to borrow",
      maxWord: "MAX",
      cta: "Confirm borrow",
      balanceLine: "Available to borrow " + amt(max, a),
      successTitle: "Borrow confirmed",
      successSub: "Funds sent to 0x7f4c…3A2c.",
      foot: "Interest accrues at the public market rate; your balance stays private.",
    };
    rows = [
      { label: "Borrowing", value: amt(n, a) },
      { label: "Borrow APR", value: APR[a] || "—" },
      { label: "Debt after", value: usd(val(bor) + n * price) },
      { label: "Health factor", value: hfStr(hf0) + "  →  " + hfStr(hf1), color: zone(hf1).color },
      { label: "Network fee", value: "~$0.51 · proof gas incl.", color: "var(--dim)" },
    ];
    if (n > 0 && hf1 < 1.15)
      spec.alert = { t: "danger", title: "This borrow leaves you near liquidation", body: "At " + hfStr(hf1) + " a small price move can liquidate the position. Borrow less, or add collateral first." };
    else if (n > 0 && hf1 < 1.6)
      spec.alert = { t: "warn", title: "Health factor enters the caution band", body: "Below 1.60 you should expect to top up collateral if the market moves against you." };
  } else if (kind === "repay") {
    max = Math.min(bor[a] || 0, walletBalances[a] || 0);
    const b2 = clone(bor);
    b2[a] = Math.max(0, (b2[a] || 0) - n);
    hf1 = hf(sup, b2);
    spec = {
      title: "Repay",
      sub: "Repay any amount. The remaining balance stays encrypted.",
      fieldLabel: "Amount to repay",
      maxWord: "REPAY MAX",
      cta: "Confirm repayment",
      balanceLine: "Outstanding " + amt(bor[a] || 0, a) + " · wallet " + amt(walletBalances[a] || 0, a),
      successTitle: "Repayment confirmed",
      successSub: "Debt reduced and position re-proved.",
      foot: "Repaying raises your health factor immediately.",
    };
    rows = [
      { label: "Repaying", value: amt(n, a) },
      { label: "Remaining debt", value: usd(Math.max(0, val(bor) - n * price)) },
      { label: "Health factor", value: hfStr(hf0) + "  →  " + hfStr(hf1), color: zone(hf1).color },
      { label: "Network fee", value: "~$0.38 · proof gas incl.", color: "var(--dim)" },
    ];
    if (n > 0 && n >= (bor[a] || 0) - 0.001)
      spec.alert = { t: "ok", title: "This closes the " + a + " borrow", body: "The " + a + " position is removed from your dashboard once the transaction settles." };
  } else if (kind === "withdraw") {
    const safeVal = (thr(sup) - 1.1 * val(bor)) / ((LT[a] ?? 1) * price);
    max = Math.max(0, Math.min(sup[a] || 0, safeVal));
    const s2 = clone(sup);
    s2[a] = Math.max(0, (s2[a] || 0) - n);
    hf1 = hf(s2, bor);
    spec = {
      title: "Withdraw collateral",
      sub: "Bounded by what keeps your position above the liquidation threshold.",
      fieldLabel: "Amount to withdraw",
      maxWord: "MAX SAFE",
      cta: "Confirm withdrawal",
      balanceLine: "Supplied " + amt(sup[a] || 0, a) + " · withdrawable " + amt(max, a),
      successTitle: "Withdrawal confirmed",
      successSub: "Collateral returned to your wallet.",
      foot: "Withdrawals settle without publishing your remaining balance.",
    };
    rows = [
      { label: "Withdrawing", value: amt(n, a) },
      { label: "Collateral after", value: usd(Math.max(0, val(sup) - n * price)) },
      { label: "Health factor", value: hfStr(hf0) + "  →  " + hfStr(hf1), color: zone(hf1).color },
      { label: "Network fee", value: "~$0.44 · proof gas incl.", color: "var(--dim)" },
    ];
    if (n > 0 && hf1 < 1.0)
      spec.alert = { t: "danger", title: "Blocked — this would liquidate you instantly", body: "Withdrawing " + amt(n, a) + " drops health factor to " + hfStr(hf1) + ". Repay debt first, or use MAX SAFE (" + amt(max, a) + ")." };
    else if (n > 0 && hf1 < 1.3)
      spec.alert = { t: "warn", title: "Leaves little headroom", body: "Health factor falls to " + hfStr(hf1) + ", inside the caution band." };
    if (n > 0 && hf1 < 1.0) spec.blocked = true;
  } else if (kind === "stake" || kind === "unstake") {
    const staking = kind === "stake";
    max = staking ? walletBalances.ZEN || 0 : staked;
    spec = {
      title: staking ? "Stake ZEN" : "Unstake ZEN",
      sub: staking ? "Earn a share of borrower interest. Your stake is private to this wallet." : "Unstaking takes effect at the next epoch boundary.",
      fieldLabel: staking ? "Amount to stake" : "Amount to unstake",
      maxWord: "MAX",
      cta: staking ? "Confirm stake" : "Confirm unstake",
      balanceLine: staking ? "Wallet balance " + amt(max, "ZEN") : "Staked " + amt(max, "ZEN"),
      successTitle: staking ? "Stake confirmed" : "Unstake queued",
      successSub: staking ? "Rewards start accruing next epoch." : "ZEN unlocks at the next epoch boundary.",
      foot: "Staking never links this wallet to a borrow position.",
    };
    const after = staking ? staked + n : Math.max(0, staked - n);
    rows = [
      { label: staking ? "Staking" : "Unstaking", value: amt(n, "ZEN") },
      { label: "Your stake after", value: amt(after, "ZEN") },
      { label: "Estimated APR", value: "11.42%", color: "var(--green)" },
      { label: "Projected rewards, 30d", value: usd((after * P.ZEN * 0.1142) / 12) },
      { label: "Network fee", value: "~$0.29", color: "var(--dim)" },
    ];
    if (!staking && n > 0)
      spec.alert = { t: "warn", title: "Accrued rewards are claimed with this unstake", body: amt(rewards, "ZEN") + " of pending rewards will be sent to your wallet in the same transaction." };
  }

  const al = spec.alert ? TONES[spec.alert.t] : null;
  const blocked = !!spec.blocked;
  const over = n > max + 1e-9;
  const disabled = n <= 0 || blocked || over;

  return {
    title: spec.title || "",
    sub: spec.sub || "",
    fieldLabel: spec.fieldLabel || "",
    maxWord: spec.maxWord || "",
    balanceLine: spec.balanceLine || "",
    foot: spec.foot || "",
    rows,
    asset: a,
    initial: badge(a),
    tint: TINT[a] || "var(--raise)",
    maxLabel: "Max " + amt(max, a),
    max,
    options: optionKeys.map((k) => ({
      symbol: k,
      initial: badge(k),
      tint: TINT[k],
      right: kind === "repay" ? amt(bor[k] || 0, k) : kind === "withdraw" ? amt(sup[k] || 0, k) : amt(walletBalances[k] || 0, k),
    })),
    alert: !!spec.alert,
    alertTitle: spec.alert ? spec.alert.title : "",
    alertBody: spec.alert ? spec.alert.body : "",
    alertColor: al ? al.color : "var(--border)",
    alertSoft: al ? al.soft : "transparent",
    disabled,
    cta: over ? "Amount exceeds maximum" : blocked ? "Blocked — position would be liquidatable" : spec.cta || "",
    ctaBg: disabled ? "var(--raise)" : "var(--gold)",
    ctaFg: disabled ? "var(--faint)" : "#0B1020",
    successTitle: spec.successTitle || "",
    successSub: spec.successSub || "",
    hf1,
  };
}
