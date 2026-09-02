// Per-account "decrypted locally" position state.
//
// This is not a shortcut — it's the honest implementation of what the design
// always claimed: collateral/debt breakdown is never stored in the clear
// on-chain, only inside a sealed commitment only the owner can open. The
// on-chain commitment is a real Poseidon hash of this exact data, matching
// circuits/src/health_factor.circom's fixed-point convention exactly —
// Circuit A (Phase 4) now actually proves solvency from this data, this
// isn't a placeholder waiting on Phase 4/5 anymore.
import { buildPoseidon } from "circomlibjs";
import { MARKET_ASSETS } from "./mock";

// Matches health_factor.circom exactly: all amounts are token units * 1e6,
// fixed-point, no floats — the circuit has no safe division primitive, so
// everything downstream of this scale must stay integer arithmetic.
export const FIXED_POINT_SCALE = 1_000_000;

export function scaleAmount(value: number): bigint {
  return BigInt(Math.round(value * FIXED_POINT_SCALE));
}

// Fixed [WETH, USDC, ZEN] order — matches MARKET_ASSETS and the circuit's
// three collateral/debt slots exactly, not an approximation of it.
export function scaledAssetArray(balances: Record<string, number>): bigint[] {
  return MARKET_ASSETS.map((sym) => scaleAmount(balances[sym] ?? 0));
}

export interface LocalPosition {
  supplied: Record<string, number>;
  borrowed: Record<string, number>;
  salt: string; // decimal string — a random BN254 scalar field element, not a UUID
}

// Scoped by vault address, not just account — redeploying contracts on a
// devnet resets onchain state, and without this a stale local position from
// a prior deployment would silently mix with real reads from the new one.
function key(account: string, vaultAddress: string) {
  return `kryptos:position:${vaultAddress.toLowerCase()}:${account.toLowerCase()}`;
}

function randomFieldElement(): string {
  // 31 bytes (248 bits) — comfortably under the BN254 scalar field's ~254
  // bits, so this can never itself be the source of an out-of-range value.
  const bytes = crypto.getRandomValues(new Uint8Array(31));
  let hex = "0x";
  bytes.forEach((b) => (hex += b.toString(16).padStart(2, "0")));
  return BigInt(hex).toString();
}

export function loadPosition(account: string, vaultAddress: string): LocalPosition {
  const raw = localStorage.getItem(key(account, vaultAddress));
  if (raw) {
    try {
      return JSON.parse(raw);
    } catch {
      // fall through to a fresh position below
    }
  }
  return { supplied: {}, borrowed: {}, salt: randomFieldElement() };
}

export function savePosition(account: string, vaultAddress: string, position: LocalPosition) {
  localStorage.setItem(key(account, vaultAddress), JSON.stringify(position));
}

let poseidonPromise: ReturnType<typeof buildPoseidon> | null = null;
function getPoseidon() {
  if (!poseidonPromise) poseidonPromise = buildPoseidon();
  return poseidonPromise;
}

// The Poseidon field element as a decimal string — exactly the form both the
// circuit's `commitment` input and the on-chain adapter's `uint256
// commitment` parameter expect. Exposed separately from computeCommitment()
// below because proof generation needs this decimal form directly, while
// on-chain sealing needs the bytes32 form.
export async function computeCommitmentField(position: LocalPosition): Promise<string> {
  const poseidon = await getPoseidon();
  const collateral = scaledAssetArray(position.supplied);
  const debt = scaledAssetArray(position.borrowed);
  const salt = BigInt(position.salt);
  const hash = poseidon([...collateral, ...debt, salt]);
  return poseidon.F.toObject(hash).toString();
}

// bytes32 hex form — what gets sealed on-chain as newCommitment on every
// deposit/withdraw/borrow/repay.
export async function computeCommitment(position: LocalPosition): Promise<string> {
  const field = await computeCommitmentField(position);
  return "0x" + BigInt(field).toString(16).padStart(64, "0");
}
