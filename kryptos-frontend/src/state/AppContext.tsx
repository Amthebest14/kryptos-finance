import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Contract, EventLog, JsonRpcProvider, Log, formatEther, parseEther } from "ethers";
import { useAccount, useChainId } from "wagmi";
import {
  CHAIN_ID,
  RPC_URL,
  DEPLOY_BLOCK,
  ADDRESSES,
  ASSET_ADDRESS,
  ASSET_INDEX,
  FAUCET_AMOUNTS,
  ERC20_ABI,
  VAULT_ABI,
  REGISTRY_ABI,
  PROOF_VERIFIER_ABI,
  PRICE_ORACLE_ABI,
  HANDLER_ABI,
  HISTORICAL_HANDLERS,
  INTEREST_RATE_MODEL_ABI,
  ZEN_STAKING_ABI,
} from "../lib/contracts";
import { useEthersSigner } from "../lib/useEthersSigner";
import { refreshLivePrices, type PriceInfo } from "../lib/prices";
import { generateHealthProof, generateTransitionProof, generateRevealProof } from "../lib/zkProof";
import { MARKET_ASSETS } from "../lib/mock";
import { hf, hfStr, zone, num, amt, usd, pow, val } from "../lib/math";
import { getModalSpec, type ModalSpec } from "../lib/modalSpec";
import { loadPosition, savePosition, computeCommitment, scaleAmount, type LocalPosition } from "../lib/localPosition";
import type { ModalKind, ToastState } from "../lib/types";

export interface LiquidationEvent {
  positionId: string;
  collateralAsset: string;
  debtAsset: string;
  timestamp: number;
  txHash: string;
}

export interface ProofStatus {
  label: string;
  color: string;
  soft: string;
  line: string;
  help: string;
}

export interface AggregateSolvency {
  activePositions: number; // ever-opened positions minus already-liquidated ones
  freshPositions: number; // active positions with a live, verified Circuit A proof
  stalePositions: number; // active positions past their check-in window
  allFresh: boolean; // true only when activePositions > 0 and stalePositions === 0
}

export interface MarketRate {
  supplyApyPct: number;
  borrowAprPct: number;
}

interface ChainData {
  totalSupplied: Record<string, number>;
  totalBorrowed: Record<string, number>;
  liquidations: LiquidationEvent[];
  uniqueBorrowers: number;
  aggregateSolvency: AggregateSolvency;
  rates: Record<string, MarketRate>;
  interestRevenueByAsset: Record<string, number>;
}

export interface StakingData {
  totalStaked: number;
  myStake: number;
  rewardAssets: string[];
  earned: Record<string, number>;
}

interface FaucetStatus {
  canClaim: boolean;
  nextClaimAt: number; // unix seconds, 0 if claimable now
}

interface AccountData {
  positionId: number;
  positionActive: boolean;
  lastProofTimestamp: number;
  isStale: boolean;
  isInGracePeriod: boolean;
  graceRemaining: number;
  walletBalances: Record<string, number>;
  faucetStatus: Record<string, FaucetStatus>;
}

// Matches PositionRegistry.PROOF_INTERVAL() on-chain exactly (30 minutes) —
// kept as a matched constant here rather than an extra chain read, same
// pattern the rest of this file already used for this same number.
const PROOF_INTERVAL_SEC = 30 * 60;
// How long before a proof is actually due the auto-refresh timer (and the
// "Due soon" UI label) starts trying — enough slack to survive a slow RPC or
// a failed attempt with time left to retry, not so much that it fires long
// before there's any real urgency.
const AUTO_REFRESH_BUFFER_SEC = 5 * 60;

// Display-only input to InterestRateModel.getSupplyRatePerYear — VaultManager
// doesn't actually distribute interest to depositors yet, so this only shapes
// what the Markets table shows as the curve's rate, not anyone's real yield.
const RESERVE_FACTOR_WAD = 100000000000000000n; // 0.1e18 = 10%

// Horizen Testnet's RPC caps eth_getLogs at a 100,000-block window — this
// never mattered right after deployment, but the chain has since advanced
// past DEPLOY_BLOCK + 100,000, and a single-range query spanning
// DEPLOY_BLOCK -> latest now exceeds it. Found live: the RPC's own
// "-32602 query exceeds max block range 100000" response, sent back as a
// single-item JSON-RPC batch, was surfacing in ethers.js as an opaque
// "could not coalesce error" with no indication it was a block-range
// problem at all — confirmed by replaying the exact same request with a
// raw fetch() instead of ethers, which returned the real RPC error
// directly. Splitting into chunks under the cap is the actual fix, not a
// batching/concurrency workaround.
const MAX_LOG_RANGE = 90_000;

async function queryFilterChunked(
  contract: Contract,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  filter: any,
  fromBlock: number,
  toBlock: number
) {
  const results: (EventLog | Log)[] = [];
  for (let start = fromBlock; start <= toBlock; start += MAX_LOG_RANGE) {
    const end = Math.min(start + MAX_LOG_RANGE - 1, toBlock);
    const chunk = await contract.queryFilter(filter, start, end);
    results.push(...chunk);
  }
  return results;
}

const EMPTY_AGGREGATE_SOLVENCY: AggregateSolvency = { activePositions: 0, freshPositions: 0, stalePositions: 0, allFresh: false };
const EMPTY_CHAIN_DATA: ChainData = {
  totalSupplied: {},
  totalBorrowed: {},
  liquidations: [],
  uniqueBorrowers: 0,
  aggregateSolvency: EMPTY_AGGREGATE_SOLVENCY,
  rates: {},
  interestRevenueByAsset: {},
};
const EMPTY_STAKING_DATA: StakingData = { totalStaked: 0, myStake: 0, rewardAssets: [], earned: {} };
const EMPTY_ACCOUNT_DATA: AccountData = {
  positionId: 0,
  positionActive: false,
  lastProofTimestamp: 0,
  isStale: false,
  isInGracePeriod: false,
  graceRemaining: 0,
  walletBalances: {},
  faucetStatus: {},
};

const INITIAL_UI_STATE = {
  theme: "dark" as "dark" | "light",
  modal: null as ModalKind,
  stage: "form" as "form" | "success",
  asset: "WETH",
  amount: "",
  selOpen: false,
  toast: null as ToastState | null,
  applied: [] as { label: string; value: string; color?: string }[],
};

interface AppContextValue {
  // wallet — connection itself is driven by RainbowKit's <ConnectButton>,
  // this context only reflects the resulting state
  account: string | null;
  chainOk: boolean;

  // ui-only state
  ui: typeof INITIAL_UI_STATE;
  toggleTheme: () => void;
  setToast: (t: ToastState | null) => void;

  // local (per-account, client-side) position
  localPosition: LocalPosition;

  // chain-wide public data
  chainData: ChainData;
  priceInfo: Record<string, PriceInfo>;

  // connected-account data
  accountData: AccountData;
  proofStatus: ProofStatus;
  stakingData: StakingData;

  // derived
  modalSpec: ModalSpec | null;
  hfValue: number;
  hfDisplay: string;
  hfZone: { label: string; color: string; soft: string };
  collateralUsd: string;
  debtUsd: string;
  availableUsd: string;
  hasPosition: boolean;

  // actions
  open: (kind: ModalKind, asset?: string) => void;
  closeModal: () => void;
  setAmount: (v: string) => void;
  setMax: () => void;
  toggleSel: () => void;
  pickAsset: (symbol: string) => void;
  confirm: () => Promise<void>;
  refreshProof: () => Promise<void>;
  autoRefreshEnabled: boolean;
  setAutoRefreshEnabled: (v: boolean) => void;
  settlePosition: () => Promise<void>;
  mintTestTokens: (symbol: string) => Promise<void>;
  stakeZen: (amountUi: number) => Promise<void>;
  unstakeZen: (amountUi: number) => Promise<void>;
  claimReward: (asset: string) => Promise<void>;
  txPending: boolean;
}

const AppContext = createContext<AppContextValue | null>(null);

function proofStatusFor(lastProofTimestamp: number, isStale: boolean, isInGracePeriod: boolean, graceRemainingSec: number, hasPosition: boolean): ProofStatus {
  if (!hasPosition) {
    return { label: "No position", color: "var(--dim)", soft: "var(--surface2)", line: "Open a position to start submitting health proofs.", help: "" };
  }
  const ageSec = Math.max(0, Math.floor(Date.now() / 1000) - lastProofTimestamp);
  const ageMin = Math.floor(ageSec / 60);
  if (isStale) {
    return {
      label: "Proof stale",
      color: "var(--red)",
      soft: "var(--redsoft)",
      line: `No valid proof since ${ageMin} min ago · position is now liquidatable`,
      help: "Because the proof stopped arriving, this position — not your identity — is what became visible.",
    };
  }
  if (isInGracePeriod) {
    const graceMin = Math.floor(graceRemainingSec / 60);
    const graceSec = graceRemainingSec % 60;
    return {
      label: "Grace period",
      color: "var(--amber)",
      soft: "var(--ambersoft)",
      line: `Missed check-in · ${graceMin}m ${graceSec}s of grace remaining`,
      help: "Submit a proof before grace expires. Nothing about your numbers has been revealed yet.",
    };
  }
  const dueInSec = Math.max(0, PROOF_INTERVAL_SEC - ageSec);
  const dueInMin = Math.ceil(dueInSec / 60);
  return {
    label: dueInSec < AUTO_REFRESH_BUFFER_SEC ? "Due soon" : "Proof fresh",
    color: dueInSec < AUTO_REFRESH_BUFFER_SEC ? "var(--amber)" : "var(--green)",
    soft: dueInSec < AUTO_REFRESH_BUFFER_SEC ? "var(--ambersoft)" : "var(--greensoft)",
    line: `Submitted ${ageMin} min ago · next check-in due in ${dueInMin} min`,
    help: "Each proof confirms your position is above the liquidation threshold. It carries no amounts.",
  };
}

export function AppProvider({ children }: { children: ReactNode }) {
  const { address, isConnected } = useAccount();
  const connectedChainId = useChainId();
  const signer = useEthersSigner();
  const account = isConnected ? address ?? null : null;
  const chainOk = !isConnected || connectedChainId === CHAIN_ID;

  const [txPending, setTxPending] = useState(false);
  const [ui, setUi] = useState(INITIAL_UI_STATE);
  const [localPosition, setLocalPosition] = useState<LocalPosition>({ supplied: {}, borrowed: {}, salt: "" });
  const [chainData, setChainData] = useState<ChainData>(EMPTY_CHAIN_DATA);
  const [accountData, setAccountData] = useState<AccountData>(EMPTY_ACCOUNT_DATA);
  const [stakingData, setStakingData] = useState<StakingData>(EMPTY_STAKING_DATA);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // batchMaxCount: 1 disables request batching. Horizen Testnet's RPC proxy
  // (Caldera) doesn't handle ethers' default batched JSON-RPC calls cleanly —
  // Anvil's local node did, which is why this only surfaced after moving off
  // it. One request per call is slightly less efficient but actually works.
  const readProvider = useMemo(() => new JsonRpcProvider(RPC_URL, undefined, { batchMaxCount: 1 }), []);

  // Serializes every readProvider-issuing refresh across the whole app —
  // found live: per-function overlap guards (see chainDataRefreshInFlight
  // below) stop refreshChainData from overlapping with ITSELF, but
  // refreshChainData, refreshStakingData, and refreshAccountData each run on
  // their own effect/interval and all fire together on mount. That's three
  // independent bursts of concurrent requests hitting Horizen's RPC proxy in
  // the same window, on top of React StrictMode's double-invoke — enough to
  // reproduce "could not coalesce error" on the queryFilter-based sections
  // even with batchMaxCount:1 and the per-function guards both in place.
  // Routing every one of those functions' RPC work through this single
  // promise-chain queue means at most one burst is ever in flight at a time,
  // app-wide — a small latency cost (a few hundred ms), not a correctness
  // one, given none of this drives an interaction the user is blocked on.
  const rpcQueue = useRef<Promise<unknown>>(Promise.resolve());
  const withRpcQueue = useCallback(<T,>(fn: () => Promise<T>): Promise<T> => {
    const run = rpcQueue.current.then(fn, fn);
    rpcQueue.current = run.then(
      () => undefined,
      () => undefined
    );
    return run;
  }, []);

  useEffect(() => {
    const root = document.documentElement;
    if (ui.theme === "light") root.setAttribute("data-theme", "light");
    else root.removeAttribute("data-theme");
  }, [ui.theme]);

  const fadeToast = useCallback(() => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setUi((s) => ({ ...s, toast: null })), 4200);
  }, []);

  const showToast = useCallback(
    (t: ToastState) => {
      setUi((s) => ({ ...s, toast: t }));
      fadeToast();
    },
    [fadeToast]
  );

  // ---- public, chain-wide reads (no wallet required) ----------------------
  // Tracks the last successfully-fetched liquidations list across ticks —
  // read by the aggregate-solvency section below when a given run's own
  // liquidation fetch fails, without waiting on a state update to land.
  const liquidationsRef = useRef<LiquidationEvent[]>([]);

  // Guards against overlapping invocations sharing the same readProvider —
  // found live: React StrictMode deliberately double-invokes effects in dev
  // (mount, cleanup, mount again), so the effect below that calls
  // refreshChainData() on mount was firing it twice within milliseconds. Two
  // full concurrent runs meant more simultaneous eth_getLogs requests
  // through Horizen's RPC proxy than the single-invocation case ever
  // produces, and the queryFilter-based sections (liquidations, interest
  // revenue, unique borrowers) started throwing "could not coalesce error"
  // under that load even with batchMaxCount:1 already set — confirmed by
  // reproducing each section in isolation (no failure) versus letting the
  // real effect's double-invoke run (fails every time). A second overlapping
  // run — from StrictMode, a slow network causing the 10s interval to fire
  // again before the last run finished, or a manual refresh racing the
  // interval — now just skips instead of piling on more concurrent requests.
  const chainDataRefreshInFlight = useRef(false);

  // Split into independently-resilient sections, each committing its own
  // slice of state rather than one function-wide try/catch around a single
  // final setChainData. Found by testing: every section that calls
  // queryFilter (liquidations, interest revenue, unique borrowers) started
  // failing once the chain advanced past DEPLOY_BLOCK + 100,000 blocks (see
  // MAX_LOG_RANGE's own comment) — with the old all-or-nothing shape, that
  // failure silently discarded EVERYTHING, including totals that had already
  // been fetched successfully earlier in the same run, making a page with
  // real deposits and borrows on it render as all zeros. queryFilterChunked
  // is the real fix for the underlying cause; this section split is a
  // separate, independently-worthwhile resilience improvement on top of it —
  // a transient failure in any one section now self-heals on the next 10s
  // tick instead of blanking the whole page.
  const refreshChainData = useCallback(async () => {
    if (chainDataRefreshInFlight.current) return;
    chainDataRefreshInFlight.current = true;
    try {
      await withRpcQueue(() => refreshChainDataInner());
    } finally {
      chainDataRefreshInFlight.current = false;
    }
  }, [withRpcQueue]);

  const refreshChainDataInner = useCallback(async () => {
    const vault = new Contract(ADDRESSES.vault, VAULT_ABI, readProvider);
    const registry = new Contract(ADDRESSES.registry, REGISTRY_ABI, readProvider);
    const rateModel = new Contract(ADDRESSES.interestRateModel, INTEREST_RATE_MODEL_ABI, readProvider);
    const staking = new Contract(ADDRESSES.zenStaking, ZEN_STAKING_ABI, readProvider);

    // Fetched once and reused by every event-query section below, rather than
    // letting a failure here (a plain eth_blockNumber call, unrelated to the
    // eth_call-based market-totals section above it) take down sections that
    // don't actually depend on it. Sections needing it just skip cleanly on
    // a null.
    let latestBlock: number | null = null;
    try {
      latestBlock = await readProvider.getBlockNumber();
    } catch (err) {
      console.error("refreshChainData: getBlockNumber failed", err);
    }

    const symOf = (addr: string) =>
      Object.entries(ASSET_ADDRESS).find(([, a]) => a.toLowerCase() === addr.toLowerCase())?.[0] || addr.slice(0, 8);

    try {
      const totalSupplied: Record<string, number> = {};
      const totalBorrowed: Record<string, number> = {};
      const rates: Record<string, { supplyApyPct: number; borrowAprPct: number }> = {};
      for (const sym of MARKET_ASSETS) {
        const addr = ASSET_ADDRESS[sym];
        const [sup, bor] = await Promise.all([vault.totalSupplied(addr), vault.totalBorrowed(addr)]);
        totalSupplied[sym] = Number(formatEther(sup));
        totalBorrowed[sym] = Number(formatEther(bor));

        // Real, live rates from InterestRateModel — same wei-scale inputs the
        // contract itself uses for accrual, not a client-side reimplementation
        // of the curve (avoids drift between what's shown and what accrues).
        // RESERVE_FACTOR_WAD is display-only here: VaultManager doesn't pay
        // depositors interest yet, so supply APY reflects what the curve
        // would pay, not money currently being earned — labeled as such in the UI.
        const [borrowRateWad, supplyRateWad] = await Promise.all([
          rateModel.getBorrowRatePerYear(sup, bor),
          rateModel.getSupplyRatePerYear(sup, bor, RESERVE_FACTOR_WAD),
        ]);
        rates[sym] = {
          borrowAprPct: (Number(borrowRateWad) / 1e18) * 100,
          supplyApyPct: (Number(supplyRateWad) / 1e18) * 100,
        };
      }
      setChainData((prev) => ({ ...prev, totalSupplied, totalBorrowed, rates }));
    } catch (err) {
      console.error("refreshChainData: market totals failed", err);
    }

    // Aggregate solvency (below) needs to know which positions are already
    // liquidated — on a failed fetch this falls back to
    // liquidationsRef.current (last successful run) rather than treating
    // every liquidated position as still "active."
    let liquidations: LiquidationEvent[] = liquidationsRef.current;
    try {
      if (latestBlock === null) throw new Error("no latestBlock available this tick");
      // Every LiquidationHandler this VaultManager has ever pointed to, not
      // just the current one — a position closed through a since-replaced
      // handler has its LiquidationSettled event sitting on THAT contract's
      // own address, invisible to a query against only the current one (see
      // HISTORICAL_HANDLERS' own comment for the real case this fixes).
      const handlersToQuery = [ADDRESSES.handler, ...HISTORICAL_HANDLERS];
      const eventsByHandler = await Promise.all(
        handlersToQuery.map((addr) => {
          const h = new Contract(addr, HANDLER_ABI, readProvider);
          return queryFilterChunked(h, h.filters.LiquidationSettled(), DEPLOY_BLOCK, latestBlock as number);
        })
      );
      const liqEvents = eventsByHandler.flat().filter((e): e is EventLog => e instanceof EventLog);
      liquidations = liqEvents
        .map((e) => ({
          positionId: (e.args.positionId as bigint).toString(),
          collateralAsset: symOf(e.args.collateralAsset as string),
          debtAsset: symOf(e.args.debtAsset as string),
          timestamp: Number(e.args.timestamp as bigint),
          txHash: e.transactionHash,
        }))
        .reverse();
      liquidationsRef.current = liquidations;
      setChainData((prev) => ({ ...prev, liquidations }));
    } catch (err) {
      console.error("refreshChainData: liquidations failed", err);
    }

    try {
      if (latestBlock === null) throw new Error("no latestBlock available this tick");
      // Real interest revenue, not a placeholder: every RewardNotified event
      // is a real token transfer VaultManager already made into ZenStaking
      // (see VaultManager.repay) — summing them here is the same "live sum of
      // on-chain events" pattern used for liquidations above.
      const rewardEvents = (
        await queryFilterChunked(staking, staking.filters.RewardNotified(), DEPLOY_BLOCK, latestBlock)
      ).filter((e): e is EventLog => e instanceof EventLog);
      const interestRevenueByAsset: Record<string, number> = {};
      for (const e of rewardEvents) {
        const sym = symOf(e.args.asset as string);
        interestRevenueByAsset[sym] = (interestRevenueByAsset[sym] ?? 0) + Number(formatEther(e.args.amount as bigint));
      }
      setChainData((prev) => ({ ...prev, interestRevenueByAsset }));
    } catch (err) {
      console.error("refreshChainData: interest revenue failed", err);
    }

    try {
      if (latestBlock === null) throw new Error("no latestBlock available this tick");
      const depositEvents = (
        await queryFilterChunked(vault, vault.filters.Deposited(), DEPLOY_BLOCK, latestBlock)
      ).filter((e): e is EventLog => e instanceof EventLog);
      const uniqueBorrowers = new Set(depositEvents.map((e) => (e.args.user as string).toLowerCase())).size;
      setChainData((prev) => ({ ...prev, uniqueBorrowers }));
    } catch (err) {
      console.error("refreshChainData: unique borrowers failed", err);
    }

    try {
      // Aggregate solvency, without any new circuit: every position must already
      // submit a real, verified Circuit A proof to stay non-stale (PositionRegistry
      // tracks that publicly per position already). So "every currently-open
      // position is solvent" already holds continuously whenever none of them are
      // stale — this just surfaces that existing guarantee as one number, rather
      // than requiring a party nobody actually is (no one holds every user's
      // private collateral/debt to feed a single aggregate proof over all of them).
      // Already-liquidated positions are excluded: they aren't a current risk, and
      // would otherwise show as permanently "stale" since a settled position never
      // submits another proof.
      const liquidatedIds = new Set(liquidations.map((l) => l.positionId));
      const nextPositionId = Number(await registry.nextPositionId());
      const activeIds: number[] = [];
      for (let id = 1; id < nextPositionId; id++) {
        if (!liquidatedIds.has(String(id))) activeIds.push(id);
      }
      const staleFlags: boolean[] = await Promise.all(activeIds.map((id) => registry.isStale(id)));
      const stalePositions = staleFlags.filter(Boolean).length;
      const aggregateSolvency: AggregateSolvency = {
        activePositions: activeIds.length,
        freshPositions: activeIds.length - stalePositions,
        stalePositions,
        allFresh: activeIds.length > 0 && stalePositions === 0,
      };
      setChainData((prev) => ({ ...prev, aggregateSolvency }));
    } catch (err) {
      console.error("refreshChainData: aggregate solvency failed", err);
    }
  }, [readProvider]);

  // ---- connected-account reads ---------------------------------------------
  // Same overlap guard + shared rpcQueue as refreshChainData/refreshStakingData
  // — this effect fires on mount too, and was part of the same three-way
  // concurrent burst that reproduced "could not coalesce error".
  const accountDataRefreshInFlight = useRef(false);
  const refreshAccountData = useCallback(
    async (acct: string) => {
      if (accountDataRefreshInFlight.current) return;
      accountDataRefreshInFlight.current = true;
      try {
        await withRpcQueue(async () => {
          const vault = new Contract(ADDRESSES.vault, VAULT_ABI, readProvider);
          const registry = new Contract(ADDRESSES.registry, REGISTRY_ABI, readProvider);

          const [positionId, active] = await vault.positionOf(acct);
          const pid = Number(positionId);

          let lastProofTimestamp = 0,
            isStale = false,
            isInGracePeriod = false,
            graceRemaining = 0;
          if (active && pid > 0) {
            const [, lastProof] = await registry.positions(pid);
            lastProofTimestamp = Number(lastProof);
            [isStale, isInGracePeriod, graceRemaining] = await Promise.all([
              registry.isStale(pid),
              registry.isInGracePeriod(pid),
              registry.graceRemaining(pid).then((v: bigint) => Number(v)),
            ]);
          }

          const walletBalances: Record<string, number> = {};
          const faucetStatus: Record<string, FaucetStatus> = {};
          for (const sym of MARKET_ASSETS) {
            const token = new Contract(ASSET_ADDRESS[sym], ERC20_ABI, readProvider);
            const [balance, canClaim, nextClaimAt] = await Promise.all([
              token.balanceOf(acct),
              token.canClaimFaucet(acct),
              token.nextFaucetClaimAt(acct).then((v: bigint) => Number(v)),
            ]);
            walletBalances[sym] = Number(formatEther(balance));
            faucetStatus[sym] = { canClaim, nextClaimAt };
          }

          setAccountData({ positionId: pid, positionActive: active, lastProofTimestamp, isStale, isInGracePeriod, graceRemaining, walletBalances, faucetStatus });
          setLocalPosition(loadPosition(acct, ADDRESSES.vault));
        });
      } catch (err) {
        console.error("refreshAccountData failed", err);
      } finally {
        accountDataRefreshInFlight.current = false;
      }
    },
    [readProvider, withRpcQueue]
  );

  // Public pool total + reward-asset list always read; per-user stake and
  // earned amounts only when a wallet is connected — stakedOf/earned are
  // public view functions (anyone can query any address), not gated on the
  // caller, so no signer is needed here either.
  // Same overlapping-invocation guard as refreshChainData, and for the same
  // reason (StrictMode's double-invoke firing this twice on mount) — this
  // one doesn't hit the queryFilter-specific failure mode, but there's no
  // reason to send two full sets of concurrent requests when one guard
  // avoids it for free. Also routed through the shared rpcQueue: this,
  // refreshChainData, and refreshAccountData all fire on mount, and it was
  // that three-way concurrent burst — not any one function overlapping with
  // itself — that reproduced "could not coalesce error" live.
  const stakingRefreshInFlight = useRef(false);
  const refreshStakingData = useCallback(
    async (acct: string | null) => {
      if (stakingRefreshInFlight.current) return;
      stakingRefreshInFlight.current = true;
      try {
        await withRpcQueue(async () => {
          const staking = new Contract(ADDRESSES.zenStaking, ZEN_STAKING_ABI, readProvider);
          const [totalStakedRaw, rewardAssetAddrs] = await Promise.all([staking.totalStaked(), staking.getRewardAssets()]);
          const symOf = (addr: string) =>
            Object.entries(ASSET_ADDRESS).find(([, a]) => a.toLowerCase() === addr.toLowerCase())?.[0] || addr.slice(0, 8);
          const rewardAssets: string[] = (rewardAssetAddrs as string[]).map(symOf);

          let myStake = 0;
          const earned: Record<string, number> = {};
          if (acct) {
            const stakedRaw = await staking.stakedOf(acct);
            myStake = Number(formatEther(stakedRaw));
            await Promise.all(
              rewardAssets.map(async (sym) => {
                const raw = await staking.earned(acct, ASSET_ADDRESS[sym]);
                earned[sym] = Number(formatEther(raw));
              })
            );
          }

          setStakingData({ totalStaked: Number(formatEther(totalStakedRaw)), myStake, rewardAssets, earned });
        });
      } catch (err) {
        console.error("refreshStakingData failed", err);
      } finally {
        stakingRefreshInFlight.current = false;
      }
    },
    [readProvider, withRpcQueue]
  );

  useEffect(() => {
    refreshChainData();
    const id = setInterval(refreshChainData, 10000);
    return () => clearInterval(id);
  }, [refreshChainData]);

  useEffect(() => {
    refreshStakingData(account);
    const id = setInterval(() => refreshStakingData(account), 10000);
    return () => clearInterval(id);
  }, [account, refreshStakingData]);

  // Live prices (see lib/prices.ts) mutate LIVE_PRICES in place — every P[k]
  // lookup across the app already reads that same object, so the only thing
  // needed here is something to make React actually re-render when it
  // changes, since a plain object mutation doesn't do that on its own.
  const [priceInfo, setPriceInfo] = useState<Record<string, PriceInfo>>({});
  useEffect(() => {
    let cancelled = false;
    const tick = () => {
      refreshLivePrices().then((info) => {
        if (!cancelled) setPriceInfo(info);
      });
    };
    tick();
    // CoinGecko's free tier (used for ZEN) has a tight rate limit — 60s
    // keeps us well under it even with React StrictMode's double-invoke
    // in dev. Pyth's on-chain reads (WETH/USDC) have no such constraint.
    const id = setInterval(tick, 60000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  useEffect(() => {
    if (!account) {
      setAccountData(EMPTY_ACCOUNT_DATA);
      return;
    }
    refreshAccountData(account);
    const id = setInterval(() => refreshAccountData(account), 5000);
    return () => clearInterval(id);
  }, [account, refreshAccountData]);

  // ---- wallet connection ----------------------------------------------------
  // Wallet connection itself is RainbowKit's job (see Header.tsx's
  // <ConnectButton>) — this effect just reacts to the result: greets a
  // newly-connected account and warns on the wrong chain.
  const [greeted, setGreeted] = useState<string | null>(null);
  useEffect(() => {
    if (!account) {
      setGreeted(null);
      return;
    }
    if (!chainOk) {
      showToast({ title: "Wrong network", body: `Switch your wallet to chain ${CHAIN_ID} (Horizen Testnet) to use Kryptos Finance.`, color: "var(--amber)", glyph: "!" });
      return;
    }
    if (greeted !== account) {
      setGreeted(account);
      showToast({ title: "Wallet connected", body: `${account.slice(0, 6)}…${account.slice(-4)} · position decrypted locally`, color: "var(--green)", glyph: "✓" });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, chainOk]);

  // ---- ui-only actions --------------------------------------------------
  const toggleTheme = useCallback(() => setUi((s) => ({ ...s, theme: s.theme === "dark" ? "light" : "dark" })), []);
  const setToast = useCallback((t: ToastState | null) => setUi((s) => ({ ...s, toast: t })), []);

  const open = useCallback(
    (kind: ModalKind, asset?: string) => {
      if (!account) {
        showToast({ title: "Connect your wallet first", body: "You need a connected wallet to open a position.", color: "var(--amber)", glyph: "!" });
        return;
      }
      let a = asset;
      if (!a) {
        if (kind === "borrow" || kind === "repay") a = Object.keys(localPosition.borrowed)[0] || "USDC";
        else if (kind === "withdraw") a = Object.keys(localPosition.supplied)[0] || "WETH";
        else if (kind === "stake" || kind === "unstake") a = "ZEN";
        else a = "WETH";
      }
      setUi((s) => ({ ...s, modal: kind, stage: "form", asset: a!, amount: "", selOpen: false }));
    },
    [account, localPosition, showToast]
  );

  const closeModal = useCallback(() => setUi((s) => ({ ...s, modal: null, selOpen: false, amount: "" })), []);
  const setAmount = useCallback((v: string) => setUi((s) => ({ ...s, amount: v })), []);
  const toggleSel = useCallback(() => setUi((s) => ({ ...s, selOpen: !s.selOpen })), []);
  const pickAsset = useCallback((symbol: string) => setUi((s) => ({ ...s, asset: symbol, amount: "", selOpen: false })), []);

  const currentSpec = getModalSpec(ui.modal, ui.asset, ui.amount, localPosition.supplied, localPosition.borrowed, 0, 0, accountData.walletBalances);

  const setMax = useCallback(() => {
    setUi((s) => {
      const spec = getModalSpec(s.modal, s.asset, s.amount, localPosition.supplied, localPosition.borrowed, 0, 0, accountData.walletBalances);
      return { ...s, amount: String(Number((spec?.max || 0).toFixed(6))) };
    });
  }, [localPosition, accountData.walletBalances]);

  // Generates a real Circuit A proof client-side (secrets never leave the
  // browser) and submits it to ProofVerifierAdapter. If the position isn't
  // actually solvent, proof generation itself fails — there is no code path
  // that lets an unhealthy position refresh its liveness.
  const refreshProof = useCallback(async () => {
    if (!account || !signer || !accountData.positionActive) return;
    setTxPending(true);
    try {
      // Must prove against the SAME price/threshold ProofVerifierAdapter will
      // independently read from PriceOracle on-chain — not this app's own
      // live off-chain price feed (lib/prices.ts), which can differ from
      // whatever the oracle last had pushed to it. A proof built against any
      // other numbers just fails to verify; this is what makes the on-chain
      // fix in PriceOracle.sol actually bind (see its own comment for why
      // caller-supplied prices were a real exploit, not just a privacy gap).
      const oracle = new Contract(ADDRESSES.priceOracle, PRICE_ORACLE_ABI, readProvider);
      const [oraclePrices, oracleLiqThresholds]: [bigint[], bigint[]] = await Promise.all([
        oracle.getPrices(),
        oracle.getLiqThresholds(),
      ]);
      const toRecord = (raw: bigint[]) =>
        Object.fromEntries(MARKET_ASSETS.map((sym, i) => [sym, Number(raw[i]) / 1_000_000]));

      const proof = await generateHealthProof(localPosition, toRecord(oraclePrices), toRecord(oracleLiqThresholds));
      const verifier = new Contract(ADDRESSES.proofVerifier, PROOF_VERIFIER_ABI, signer);
      const tx = await verifier.recordProof(accountData.positionId, proof.pA, proof.pB, proof.pC, proof.commitment);
      await tx.wait();
      showToast({ title: "Health proof submitted", body: "Verified onchain via a real ZK proof · check-in refreshed", color: "var(--green)", glyph: "✓" });
      await refreshAccountData(account);
    } catch (err) {
      console.error(err);
      const message = err instanceof Error && /assert/i.test(err.message)
        ? "Your position isn't healthy enough to prove — add collateral or repay debt first."
        : "The transaction was rejected or reverted.";
      showToast({ title: "Proof submission failed", body: message, color: "var(--red)", glyph: "!" });
    } finally {
      setTxPending(false);
    }
  }, [account, signer, accountData.positionActive, accountData.positionId, localPosition, readProvider, refreshAccountData, showToast]);

  // Automated keep-alive, scoped honestly: this can only ever run in this
  // browser tab, because the position's actual collateral/debt/salt live only
  // in this device's localStorage — no server, relayer, or cron job could
  // renew a proof on this wallet's behalf without being handed those secrets,
  // which would defeat the point of never letting them leave the device.
  // "Automated" here means "no manual click needed while the tab stays open,"
  // not "keeps renewing after you close the browser." Defaults on; the
  // manual "Refresh proof now" button stays available either way.
  const [autoRefreshEnabled, setAutoRefreshEnabled] = useState(true);
  const autoRefreshInFlight = useRef(false);
  useEffect(() => {
    if (!autoRefreshEnabled || !account || !signer || !accountData.positionActive) return;
    const tick = async () => {
      if (autoRefreshInFlight.current || txPending) return;
      const ageSec = Math.max(0, Math.floor(Date.now() / 1000) - accountData.lastProofTimestamp);
      if (ageSec < PROOF_INTERVAL_SEC - AUTO_REFRESH_BUFFER_SEC) return;
      autoRefreshInFlight.current = true;
      try {
        await refreshProof();
      } finally {
        autoRefreshInFlight.current = false;
      }
    };
    const id = setInterval(tick, 30_000);
    return () => clearInterval(id);
  }, [autoRefreshEnabled, account, signer, accountData.positionActive, accountData.lastProofTimestamp, txPending, refreshProof]);

  // Self-service liquidation for the connected wallet's own stale position —
  // generates a real Circuit R reveal proof from this device's own local
  // position data (nobody else has it) and submits it to LiquidationHandler.
  // Requires actually repaying the revealed debt amount (approved and pulled
  // by LiquidationHandler) in exchange for the collateral being released —
  // not a free close; see LiquidationHandler.sol's own comment for why real
  // repayment replaced an earlier version that let this happen for free
  // while silently making the protocol less solvent.
  // Only possible because reveal.circom's scope is a single collateral asset
  // and a single debt asset per position; anything wider is rejected here
  // before even attempting proof generation, rather than failing confusingly
  // inside witness generation.
  //
  // Irreversible: VaultManager's positionOf[msg.sender] is a one-time-use
  // latch with no "reopen" path, so once this settles, this wallet can never
  // deposit into this specific vault deployment again — a fresh deployment
  // or a different wallet would be needed. Confirmed by reading VaultManager
  // directly (positionOf.active only ever becomes true, never false again),
  // not assumed.
  const settlePosition = useCallback(async () => {
    if (!account || !signer || !accountData.positionActive || !accountData.isStale) return;
    setTxPending(true);
    try {
      const suppliedEntries = Object.entries(localPosition.supplied).filter(([, v]) => v > 0);
      const borrowedEntries = Object.entries(localPosition.borrowed).filter(([, v]) => v > 0);
      if (suppliedEntries.length > 1 || borrowedEntries.length > 1) {
        showToast({
          title: "Can't settle automatically",
          body: "This position holds more than one collateral or debt asset — self-service settlement only supports a single asset pair in this version.",
          color: "var(--red)",
          glyph: "!",
        });
        return;
      }

      const [collateralAsset, collateralAmountUi] = suppliedEntries[0] ?? [MARKET_ASSETS[0], 0];
      const [debtAsset, debtAmountUi] = borrowedEntries[0] ?? [MARKET_ASSETS[0], 0];
      const collateralScaled = scaleAmount(collateralAmountUi);
      const debtScaled = scaleAmount(debtAmountUi);
      const collateralWei = collateralScaled * 10n ** 12n;
      const debtWei = debtScaled * 10n ** 12n;

      const commitment = await computeCommitment(localPosition);
      const revealProof = await generateRevealProof(
        localPosition,
        ASSET_INDEX[collateralAsset],
        collateralScaled,
        ASSET_INDEX[debtAsset],
        debtScaled
      );

      // Real repayment, not just accounting (see LiquidationHandler.sol's own
      // comment for the bug this replaced): settling now means actually
      // paying back what's owed, in exchange for the collateral being
      // released back to this wallet — not a free close.
      const debtToken = new Contract(ASSET_ADDRESS[debtAsset], ERC20_ABI, signer);
      const allowance = await debtToken.allowance(account, ADDRESSES.handler);
      if (allowance < debtWei) {
        const approveTx = await debtToken.approve(ADDRESSES.handler, debtWei);
        await approveTx.wait();
      }

      const handler = new Contract(ADDRESSES.handler, HANDLER_ABI, signer);
      const tx = await handler.liquidate(
        accountData.positionId,
        ASSET_ADDRESS[collateralAsset],
        ASSET_ADDRESS[debtAsset],
        commitment,
        collateralWei,
        debtWei,
        revealProof
      );
      await tx.wait();

      const closedPosition: LocalPosition = { supplied: {}, borrowed: {}, salt: localPosition.salt };
      savePosition(account, ADDRESSES.vault, closedPosition);
      setLocalPosition(closedPosition);

      showToast({
        title: "Position settled",
        body: "Debt repaid, collateral returned, closed onchain via a real Circuit R reveal proof — this wallet's position on this deployment can't be reopened.",
        color: "var(--green)",
        glyph: "✓",
      });
      await Promise.all([refreshAccountData(account), refreshChainData()]);
    } catch (err) {
      console.error(err);
      const message =
        err instanceof Error && /assert/i.test(err.message)
          ? "Reveal proof generation failed — the local position data doesn't match what's sealed onchain."
          : "The transaction was rejected or reverted.";
      showToast({ title: "Settlement failed", body: message, color: "var(--red)", glyph: "!" });
    } finally {
      setTxPending(false);
    }
  }, [
    account,
    signer,
    accountData.positionActive,
    accountData.isStale,
    accountData.positionId,
    localPosition,
    refreshAccountData,
    refreshChainData,
    showToast,
  ]);

  // Testnet faucet — one claim per address per UTC+1 calendar day, enforced
  // on-chain by MockERC20.claimFaucet() itself (see contracts/src/MockERC20.sol),
  // not just hidden client-side. The drip amount is fixed on-chain; this
  // button doesn't choose it. Real assets obviously don't work this way —
  // this exists only because these are our own throwaway test tokens.
  const mintTestTokens = useCallback(
    async (symbol: string) => {
      if (!account || !signer) return;
      const assetAddr = ASSET_ADDRESS[symbol];
      const dripAmount = FAUCET_AMOUNTS[symbol];
      if (!assetAddr || !dripAmount) return;

      setTxPending(true);
      try {
        const token = new Contract(assetAddr, ERC20_ABI, signer);
        const tx = await token.claimFaucet();
        await tx.wait();
        showToast({ title: "Test tokens received", body: `${dripAmount.toLocaleString()} ${symbol} sent to your wallet · resets 00:00 UTC+1`, color: "var(--green)", glyph: "✓" });
        await refreshAccountData(account);
      } catch (err) {
        console.error(err);
        const message = err instanceof Error && /already claimed today/i.test(err.message)
          ? `Already claimed ${symbol} today — resets at 00:00 UTC+1.`
          : "The transaction was rejected or reverted.";
        showToast({ title: "Faucet claim failed", body: message, color: "var(--red)", glyph: "!" });
      } finally {
        setTxPending(false);
      }
    },
    [account, signer, refreshAccountData, showToast]
  );

  // Staking is plain ERC20 mechanics with no ZK involvement at all — no
  // commitment, no proof, nothing private about a stake or its rewards
  // (stakedOf/earned are public view functions anyone can already query).
  const stakeZen = useCallback(
    async (amountUi: number) => {
      if (!account || !signer || amountUi <= 0) return;
      setTxPending(true);
      try {
        const amountWei = parseEther(String(amountUi));
        const zen = new Contract(ADDRESSES.zen, ERC20_ABI, signer);
        const allowance = await zen.allowance(account, ADDRESSES.zenStaking);
        if (allowance < amountWei) {
          const approveTx = await zen.approve(ADDRESSES.zenStaking, amountWei);
          await approveTx.wait();
        }
        const staking = new Contract(ADDRESSES.zenStaking, ZEN_STAKING_ABI, signer);
        const tx = await staking.stake(amountWei);
        await tx.wait();
        showToast({ title: "Staked", body: `${amountUi} ZEN staked · earning a share of protocol interest revenue`, color: "var(--green)", glyph: "✓" });
        await Promise.all([refreshStakingData(account), refreshAccountData(account)]);
      } catch (err) {
        console.error(err);
        showToast({ title: "Stake failed", body: "The transaction was rejected or reverted.", color: "var(--red)", glyph: "!" });
      } finally {
        setTxPending(false);
      }
    },
    [account, signer, refreshStakingData, refreshAccountData, showToast]
  );

  const unstakeZen = useCallback(
    async (amountUi: number) => {
      if (!account || !signer || amountUi <= 0) return;
      setTxPending(true);
      try {
        const amountWei = parseEther(String(amountUi));
        const staking = new Contract(ADDRESSES.zenStaking, ZEN_STAKING_ABI, signer);
        const tx = await staking.unstake(amountWei);
        await tx.wait();
        showToast({ title: "Unstaked", body: `${amountUi} ZEN returned to your wallet`, color: "var(--green)", glyph: "✓" });
        await Promise.all([refreshStakingData(account), refreshAccountData(account)]);
      } catch (err) {
        console.error(err);
        showToast({ title: "Unstake failed", body: "The transaction was rejected or reverted.", color: "var(--red)", glyph: "!" });
      } finally {
        setTxPending(false);
      }
    },
    [account, signer, refreshStakingData, refreshAccountData, showToast]
  );

  const claimReward = useCallback(
    async (asset: string) => {
      if (!account || !signer) return;
      setTxPending(true);
      try {
        const staking = new Contract(ADDRESSES.zenStaking, ZEN_STAKING_ABI, signer);
        const tx = await staking.claim(ASSET_ADDRESS[asset]);
        await tx.wait();
        showToast({ title: "Reward claimed", body: `${asset} sent to your wallet`, color: "var(--green)", glyph: "✓" });
        await Promise.all([refreshStakingData(account), refreshAccountData(account)]);
      } catch (err) {
        console.error(err);
        showToast({ title: "Claim failed", body: "The transaction was rejected or reverted.", color: "var(--red)", glyph: "!" });
      } finally {
        setTxPending(false);
      }
    },
    [account, signer, refreshStakingData, refreshAccountData, showToast]
  );

  const confirm = useCallback(async () => {
    if (!account || !signer) return;
    const spec = getModalSpec(ui.modal, ui.asset, ui.amount, localPosition.supplied, localPosition.borrowed, 0, 0, accountData.walletBalances);
    if (!spec || spec.disabled || !ui.modal) return;

    const kind = ui.modal;
    const a = ui.asset;
    const n = num(ui.amount);
    const assetAddr = ASSET_ADDRESS[a];

    setTxPending(true);
    try {
      const vault = new Contract(ADDRESSES.vault, VAULT_ABI, signer);

      // Single source of truth for this call's amount, at the transition
      // circuit's own "token units * 1e6" fixed-point scale. The actual
      // on-chain ERC20 transfer size (18 decimals) and the local position's
      // updated commitment are both derived from this same integer — never
      // computed independently — so they can't drift out of sync with each
      // other. VaultManager's real, deployed TransitionRevealAdapter enforces
      // this same 1e12 (1e18/1e6) ratio on-chain and reverts on anything that
      // isn't an exact multiple of it (see TransitionRevealAdapter.sol).
      const deltaScaled = scaleAmount(n);
      const amountWei = deltaScaled * 10n ** 12n;

      // Accrued interest: read the shared public index this position last
      // checkpointed against, and this device's own knowledge of its current
      // debt, to compute exactly how much interest is owed on `a` since then.
      // As of gap #3's fix, this is no longer just a local computation the
      // contract trusts — checkpointIndex/currentIndex get fed into the
      // transition proof below too, and transition.circom independently
      // re-derives the same interest amount from the position's own (private)
      // old debt, rejecting the proof if it doesn't match. Getting this wrong
      // doesn't produce a silently-incorrect transaction; it produces a proof
      // that fails to verify.
      //
      // checkpointIndex/currentIndex must exactly match what VaultManager
      // will independently pass to the adapter, including its own
      // "snapshot 0 (never borrowed this asset) treated as == currentIndex"
      // substitution (see VaultManager._borrowIndexCheckpoint) — replicated
      // here rather than approximated, since any mismatch fails the proof.
      let accruedInterestScaled = 0n;
      let checkpointIndex = 0n;
      let currentIndex = 0n;
      if (kind === "borrow" || kind === "repay") {
        const existingDebtScaled = scaleAmount(localPosition.borrowed[a] || 0);
        const snapshot: bigint = await vault.positionBorrowIndexSnapshot(accountData.positionId, assetAddr);
        currentIndex = await vault.currentBorrowIndex(assetAddr);
        checkpointIndex = snapshot === 0n ? currentIndex : snapshot;
        if (existingDebtScaled > 0n) {
          accruedInterestScaled = (existingDebtScaled * (currentIndex - checkpointIndex)) / checkpointIndex;
        }
      } else {
        // deposit/withdraw never claim interest — any equal pair collapses
        // transition.circom's interest constraint to "0 accrued," matching
        // VaultManager._submitCollateralTransition exactly.
        checkpointIndex = await vault.positionBorrowIndexSnapshot(accountData.positionId, assetAddr);
        currentIndex = checkpointIndex;
      }
      const accruedInterestWei = accruedInterestScaled * 10n ** 12n;

      const nextPosition: LocalPosition = {
        supplied: { ...localPosition.supplied },
        borrowed: { ...localPosition.borrowed },
        salt: localPosition.salt,
      };

      let collateralIncrease = 0n;
      let collateralDecrease = 0n;
      let principalIncrease = 0n;
      let debtDecrease = 0n;

      if (kind === "deposit") {
        const oldScaled = scaleAmount(localPosition.supplied[a] || 0);
        nextPosition.supplied[a] = Number(oldScaled + deltaScaled) / 1_000_000;
        collateralIncrease = deltaScaled;
      }
      if (kind === "withdraw") {
        const oldScaled = scaleAmount(localPosition.supplied[a] || 0);
        const newScaled = deltaScaled > oldScaled ? 0n : oldScaled - deltaScaled;
        nextPosition.supplied[a] = Number(newScaled) / 1_000_000;
        if (nextPosition.supplied[a] < 1e-9) delete nextPosition.supplied[a];
        collateralDecrease = deltaScaled;
      }
      if (kind === "borrow") {
        // Interest owed since the last check-in is added on top of the new
        // borrow — nobody receives extra tokens for it, it just makes debt
        // grow, exactly like real accrued interest on a loan. principalIncrease
        // (the new borrow) and interestAccrued are separate transition.circom
        // inputs now, not combined — only interestAccrued is cryptographically
        // checked against checkpointIndex/currentIndex.
        const oldScaled = scaleAmount(localPosition.borrowed[a] || 0);
        nextPosition.borrowed[a] = Number(oldScaled + deltaScaled + accruedInterestScaled) / 1_000_000;
        principalIncrease = deltaScaled;
      }
      if (kind === "repay") {
        // Interest owed accrues first, then this repayment reduces it — both
        // in the same transition proof (see transition.circom's own support
        // for simultaneous principal/interest/decrease, and IProofVerifier's
        // interface change enabling it here).
        const oldScaled = scaleAmount(localPosition.borrowed[a] || 0) + accruedInterestScaled;
        const newScaled = deltaScaled > oldScaled ? 0n : oldScaled - deltaScaled;
        nextPosition.borrowed[a] = Number(newScaled) / 1_000_000;
        if (nextPosition.borrowed[a] < 1e-9) delete nextPosition.borrowed[a];
        debtDecrease = deltaScaled;
      }
      const newCommitment = await computeCommitment(nextPosition);

      if (kind === "deposit" || kind === "repay") {
        const token = new Contract(assetAddr, ERC20_ABI, signer);
        const allowance = await token.allowance(account, ADDRESSES.vault);
        if (allowance < amountWei) {
          const approveTx = await token.approve(ADDRESSES.vault, amountWei);
          await approveTx.wait();
        }
      }

      // Every call except a brand-new position's very first deposit must
      // prove the transition — VaultManager only skips the check there (see
      // its `!up.active` branch), since there's no prior commitment yet to be
      // consistent with. Every other case now requires this real Circuit T
      // proof: TransitionRevealAdapter (real, deployed) rejects "0x".
      const transitionProof = accountData.positionActive
        ? await generateTransitionProof(
            localPosition,
            nextPosition,
            ASSET_INDEX[a],
            collateralIncrease,
            collateralDecrease,
            principalIncrease,
            debtDecrease,
            accruedInterestScaled,
            checkpointIndex,
            currentIndex
          )
        : "0x";

      let tx;
      if (kind === "deposit") tx = await vault.deposit(assetAddr, amountWei, newCommitment, transitionProof);
      else if (kind === "borrow") tx = await vault.borrow(assetAddr, amountWei, accruedInterestWei, newCommitment, transitionProof);
      else if (kind === "repay") tx = await vault.repay(assetAddr, amountWei, accruedInterestWei, newCommitment, transitionProof);
      else if (kind === "withdraw") tx = await vault.withdraw(assetAddr, amountWei, newCommitment, transitionProof);
      else {
        // stake/unstake: no real contract yet (ZenStaking.sol not built) — should be unreachable
        // since the Staking page no longer opens this modal kind, but guard anyway.
        showToast({ title: "Not available yet", body: "ZEN staking isn't deployed on this devnet yet.", color: "var(--amber)", glyph: "!" });
        setTxPending(false);
        return;
      }
      const receipt = await tx.wait();

      savePosition(account, ADDRESSES.vault, nextPosition);
      setLocalPosition(nextPosition);

      const hf1 = hf(nextPosition.supplied, nextPosition.borrowed);
      const applied = [
        { label: ({ deposit: "Deposited", borrow: "Borrowed", repay: "Repaid", withdraw: "Withdrawn" } as Record<string, string>)[kind] || "Confirmed", value: amt(n, a) },
        { label: "Collateral", value: usd(val(nextPosition.supplied)) },
        { label: "Debt", value: usd(val(nextPosition.borrowed)) },
        { label: "Health factor", value: hfStr(hf1), color: zone(hf1).color },
        { label: "Transaction", value: `${receipt.hash.slice(0, 8)}…${receipt.hash.slice(-6)}`, color: "var(--dim)" },
      ];

      setUi((s) => ({ ...s, stage: "success", applied }));
      showToast({ title: spec.successTitle || "Confirmed", body: "Health factor now " + hfStr(hf1) + " · sent onchain", color: "var(--green)", glyph: "✓" });

      await Promise.all([refreshAccountData(account), refreshChainData()]);
    } catch (err) {
      console.error(err);
      showToast({ title: "Transaction failed", body: "It was rejected or reverted — nothing changed.", color: "var(--red)", glyph: "!" });
    } finally {
      setTxPending(false);
    }
  }, [account, signer, ui.modal, ui.asset, ui.amount, localPosition, accountData.walletBalances, accountData.positionActive, refreshAccountData, refreshChainData, showToast]);

  const hfValue = hf(localPosition.supplied, localPosition.borrowed);
  const collateral = val(localPosition.supplied);
  const debt = val(localPosition.borrowed);
  const hasPosition = !!account && accountData.positionActive && Object.keys(localPosition.supplied).length > 0;

  const value: AppContextValue = {
    account,
    chainOk,
    ui,
    toggleTheme,
    setToast,
    localPosition,
    chainData,
    priceInfo,
    accountData,
    proofStatus: proofStatusFor(accountData.lastProofTimestamp, accountData.isStale, accountData.isInGracePeriod, accountData.graceRemaining, hasPosition),
    stakingData,
    modalSpec: currentSpec,
    hfValue,
    hfDisplay: hfStr(hfValue),
    hfZone: zone(hfValue),
    collateralUsd: usd(collateral),
    debtUsd: usd(debt),
    availableUsd: usd(Math.max(0, pow(localPosition.supplied) - debt)),
    hasPosition,
    open,
    closeModal,
    setAmount,
    setMax,
    toggleSel,
    pickAsset,
    confirm,
    refreshProof,
    autoRefreshEnabled,
    setAutoRefreshEnabled,
    settlePosition,
    mintTestTokens,
    stakeZen,
    unstakeZen,
    claimReward,
    txPending,
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useApp() {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp must be used within AppProvider");
  return ctx;
}
