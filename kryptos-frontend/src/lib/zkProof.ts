// Generates a real Circuit A (health-factor) Groth16 proof entirely in the
// browser — the position's actual collateral/debt never leaves the device;
// only the proof and the already-public price/threshold values are sent
// on-chain. Circuit artifacts are served as static files (public/circuits/)
// rather than bundled, since a ~2.4MB wasm + ~800KB zkey have no business
// being in the JS bundle proper.
import * as snarkjs from "snarkjs";
import { AbiCoder } from "ethers";
import { scaledAssetArray, computeCommitmentField, type LocalPosition } from "./localPosition";

const WASM_URL = "/circuits/health_factor.wasm";
const ZKEY_URL = "/circuits/health_factor_final.zkey";
const TRANSITION_WASM_URL = "/circuits/transition.wasm";
const TRANSITION_ZKEY_URL = "/circuits/transition_final.zkey";
const REVEAL_WASM_URL = "/circuits/reveal.wasm";
const REVEAL_ZKEY_URL = "/circuits/reveal_final.zkey";

export interface HealthProof {
  pA: [string, string];
  pB: [[string, string], [string, string]];
  pC: [string, string];
  commitment: string; // decimal string — matches the adapter's uint256 param
}

/// Throws if the position is not actually solvent — matching the circuit's
/// own behavior (an unhealthy position makes the constraint system
/// unsatisfiable, so witness generation itself fails; there is no way to
/// generate a proof for a position that isn't genuinely healthy).
///
/// `prices`/`liqThresholds` must be the exact values PriceOracle.sol holds
/// on-chain right now (see AppContext.tsx's refreshProof, which reads them
/// from the oracle before calling this) — not this app's own live off-chain
/// price feed. ProofVerifierAdapter independently reads the same oracle to
/// assemble its own public-signal array; a proof built against different
/// numbers just fails to verify, it doesn't silently use the "wrong" price.
export async function generateHealthProof(
  position: LocalPosition,
  prices: Record<string, number>,
  liqThresholds: Record<string, number>
): Promise<HealthProof> {
  const collateral = scaledAssetArray(position.supplied).map(String);
  const debt = scaledAssetArray(position.borrowed).map(String);
  const price = scaledAssetArray(prices).map(String);
  const liqThreshold = scaledAssetArray(liqThresholds).map(String);
  const commitment = await computeCommitmentField(position);

  const circuitInput = { collateral, debt, salt: position.salt, price, liqThreshold, commitment };

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(circuitInput, WASM_URL, ZKEY_URL);
  const calldata: string = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const [pA, pB, pC] = JSON.parse("[" + calldata.replace(/\]\[/g, "],[") + "]");

  return { pA, pB, pC, commitment };
}

async function encodeGroth16Calldata(proof: unknown, publicSignals: unknown): Promise<string> {
  const calldata: string = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const [pA, pB, pC] = JSON.parse("[" + calldata.replace(/\]\[/g, "],[") + "]");
  return AbiCoder.defaultAbiCoder().encode(["uint256[2]", "uint256[2][2]", "uint256[2]"], [pA, pB, pC]);
}

/// Generates a real Circuit T (transition) proof and ABI-encodes it exactly as
/// TransitionRevealAdapter.verifyTransition expects its `bytes calldata proof`
/// (abi.encode(pA, pB, pC)) — the returned string can be passed directly as
/// VaultManager's `transitionProof` argument.
///
/// `collateralIncrease`/`collateralDecrease`/`principalIncrease`/`debtDecrease`/
/// `interestAccrued` are the circuit's own "token units * 1e6" fixed-point
/// scale, matching localPosition.ts's commitment scheme — NOT the 18-decimal
/// wei amount VaultManager moves on-chain. Callers must convert (see
/// AppContext.tsx's `confirm()`) before calling this; getting that conversion
/// wrong doesn't silently misbehave, it makes the adapter revert or the proof
/// fail to match.
///
/// `checkpointIndex`/`currentIndex` are different in kind, not just scale:
/// WAD-scaled (1e18) borrowIndex ratios read directly from VaultManager
/// on-chain (positionBorrowIndexSnapshot / currentBorrowIndex), passed
/// through unconverted — gap #3's fix, which cryptographically ties
/// `interestAccrued` to these instead of trusting whatever the caller
/// claims. For a call that isn't claiming any interest (deposit, withdraw,
/// or a borrow/repay with nothing accrued), pass equal values for both —
/// see AppContext.tsx's `confirm()` for where those come from.
///
/// Throws if the claimed deltas aren't actually consistent with
/// oldPosition -> newPosition, or if `interestAccrued` doesn't match what
/// `checkpointIndex`/`currentIndex` actually justify — witness generation
/// itself fails, matching every other circuit in this project: there's no
/// way to generate a proof for a transition that didn't really happen this
/// way.
export async function generateTransitionProof(
  oldPosition: LocalPosition,
  newPosition: LocalPosition,
  assetIndex: number,
  collateralIncrease: bigint,
  collateralDecrease: bigint,
  principalIncrease: bigint,
  debtDecrease: bigint,
  interestAccrued: bigint,
  checkpointIndex: bigint,
  currentIndex: bigint
): Promise<string> {
  const oldCollateral = scaledAssetArray(oldPosition.supplied).map(String);
  const oldDebt = scaledAssetArray(oldPosition.borrowed).map(String);
  const newCollateral = scaledAssetArray(newPosition.supplied).map(String);
  const newDebt = scaledAssetArray(newPosition.borrowed).map(String);
  const oldCommitment = await computeCommitmentField(oldPosition);
  const newCommitment = await computeCommitmentField(newPosition);

  const circuitInput = {
    oldCollateral,
    oldDebt,
    newCollateral,
    newDebt,
    salt: oldPosition.salt,
    oldCommitment,
    newCommitment,
    assetIndex: String(assetIndex),
    collateralIncrease: collateralIncrease.toString(),
    collateralDecrease: collateralDecrease.toString(),
    principalIncrease: principalIncrease.toString(),
    debtDecrease: debtDecrease.toString(),
    interestAccrued: interestAccrued.toString(),
    checkpointIndex: checkpointIndex.toString(),
    currentIndex: currentIndex.toString(),
  };

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(circuitInput, TRANSITION_WASM_URL, TRANSITION_ZKEY_URL);
  return encodeGroth16Calldata(proof, publicSignals);
}

/// Generates a real Circuit R (reveal) proof, ABI-encoded the same way as
/// generateTransitionProof above — ready to pass directly as
/// LiquidationHandler.liquidate's `revealProof` argument. Wired to the
/// Dashboard's self-service "Settle now" flow for the connected wallet's own
/// stale position (see AppContext.tsx's settlePosition); LiquidationsFeed.tsx
/// remains read-only for positions other than your own.
///
/// `collateralAmount`/`debtAmount` are circuit-scale (1e6), same caveat as
/// generateTransitionProof.
export async function generateRevealProof(
  position: LocalPosition,
  collateralAssetIndex: number,
  collateralAmount: bigint,
  debtAssetIndex: number,
  debtAmount: bigint
): Promise<string> {
  const collateral = scaledAssetArray(position.supplied).map(String);
  const debt = scaledAssetArray(position.borrowed).map(String);
  const commitment = await computeCommitmentField(position);

  const circuitInput = {
    collateral,
    debt,
    salt: position.salt,
    commitment,
    collateralAssetIndex: String(collateralAssetIndex),
    collateralAmount: collateralAmount.toString(),
    debtAssetIndex: String(debtAssetIndex),
    debtAmount: debtAmount.toString(),
  };

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(circuitInput, REVEAL_WASM_URL, REVEAL_ZKEY_URL);
  return encodeGroth16Calldata(proof, publicSignals);
}
