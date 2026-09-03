// Regenerates every hardcoded proof fixture used by the Foundry tests,
// because gap #4's real multi-party ptau swap changed the trusted setup for
// ALL FOUR circuits (a Groth16 proof is bound to the specific zkey/verifying
// key it was proven under — a proof from the old setup does not verify
// against the new one, even for a circuit whose source didn't change), and
// gap #3 additionally changed transition.circom's own public input shape.
const { buildPoseidon } = require("circomlibjs");
const snarkjs = require("snarkjs");
const fs = require("fs");

function parseCalldata(calldata) {
  const [pA, pB, pC, pub] = JSON.parse("[" + calldata.replace(/\]\[/g, "],[") + "]");
  return { pA, pB, pC, pub };
}

async function proveAndExtract(input, wasmPath, zkeyPath) {
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, wasmPath, zkeyPath);
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  return parseCalldata(calldata);
}

async function main() {
  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const commit = (arr) => F.toObject(poseidon(arr.map(BigInt))).toString();
  const out = {};

  // === health_factor (circuit unchanged, setup regenerated) ===
  {
    const collateral = ["5000000", "0", "0"];
    const debt = ["0", "1000000000", "0"];
    const salt = "12345";
    const price = ["2473760000", "1000000", "5000000"];
    const liqThreshold = ["830000", "900000", "650000"];
    const commitment = commit([...collateral, ...debt, salt]);
    const input = { collateral, debt, salt, price, liqThreshold, commitment };
    const r = await proveAndExtract(input, "health_factor_js/health_factor.wasm", "health_factor_final.zkey");
    out.healthFactor = { ...r, commitment, price, liqThreshold };
    console.log("health_factor done. commitment:", commitment);
  }

  // === transition: plain deposit, 5 -> 7 WETH, no interest ===
  {
    const oldCollateral = ["5000000", "0", "0"];
    const oldDebt = ["0", "0", "0"];
    const salt = "12345";
    const oldCommitment = commit([...oldCollateral, ...oldDebt, salt]);
    const newCollateral = ["7000000", "0", "0"];
    const newDebt = ["0", "0", "0"];
    const newCommitment = commit([...newCollateral, ...newDebt, salt]);
    const idx = "1000000000000000000"; // 1e18 WAD, arbitrary equal checkpoint/current (no interest claimed)
    const input = {
      oldCollateral, oldDebt, newCollateral, newDebt, salt,
      oldCommitment, newCommitment, assetIndex: "0",
      collateralIncrease: "2000000", collateralDecrease: "0",
      principalIncrease: "0", debtDecrease: "0", interestAccrued: "0",
      checkpointIndex: idx, currentIndex: idx,
    };
    const r = await proveAndExtract(input, "transition_js/transition.wasm", "transition_final.zkey");
    out.transitionDeposit = { ...r, oldCommitment, newCommitment };
    console.log("transition (deposit) done.");
  }

  // === transition: repay with interest, 1000 USDC debt -> 950 (50 accrued, 100 repaid) ===
  {
    const oldCollateral = ["5000000", "0", "0"];
    const oldDebt = ["0", "1000000000", "0"];
    const salt = "12345";
    const oldCommitment = commit([...oldCollateral, ...oldDebt, salt]);
    const newCollateral = ["5000000", "0", "0"];
    const newDebt = ["0", "950000000", "0"];
    const newCommitment = commit([...newCollateral, ...newDebt, salt]);
    // 1000000000 * (currentIndex - checkpointIndex) / checkpointIndex == 50000000
    // checkpointIndex = 1e18 -> currentIndex = 1.05e18
    const checkpointIndex = "1000000000000000000";
    const currentIndex = "1050000000000000000";
    const input = {
      oldCollateral, oldDebt, newCollateral, newDebt, salt,
      oldCommitment, newCommitment, assetIndex: "1",
      collateralIncrease: "0", collateralDecrease: "0",
      principalIncrease: "0", debtDecrease: "100000000", interestAccrued: "50000000",
      checkpointIndex, currentIndex,
    };
    const r = await proveAndExtract(input, "transition_js/transition.wasm", "transition_final.zkey");
    out.transitionRepayInterest = { ...r, oldCommitment, newCommitment, checkpointIndex, currentIndex };
    console.log("transition (repay+interest) done.");
  }

  // === transition: repay with interest, non-round index delta — regression
  // fixture for a real bug found live. The 5% fixture above happens to
  // divide out to a whole number (1000 * 5% = 50 exactly), which is exactly
  // why it never caught the bug: the old circuit demanded interestAccrued
  // divide out of debt*indexDelta/checkpointIndex EXACTLY, and this fixture
  // uses the real currentIndex captured from a live failed transaction
  // (checkpointIndex=1e18 -> currentIndex=1000009886986254466), which does
  // NOT divide evenly — floor(900e6 * 9886986254466 / 1e18) = 8898, with a
  // real nonzero remainder the old exact-equality check would have rejected. ===
  {
    const oldCollateral = ["0", "0", "5000000"];
    const oldDebt = ["0", "0", "900000000"];
    const salt = "12345";
    const oldCommitment = commit([...oldCollateral, ...oldDebt, salt]);
    const newCollateral = ["0", "0", "5000000"];
    const newDebt = ["0", "0", "400008898"]; // 900000000 + 8898 - 500000000
    const newCommitment = commit([...newCollateral, ...newDebt, salt]);
    const checkpointIndex = "1000000000000000000";
    const currentIndex = "1000009886986254466";
    const input = {
      oldCollateral, oldDebt, newCollateral, newDebt, salt,
      oldCommitment, newCommitment, assetIndex: "2",
      collateralIncrease: "0", collateralDecrease: "0",
      principalIncrease: "0", debtDecrease: "500000000", interestAccrued: "8898",
      checkpointIndex, currentIndex,
    };
    const r = await proveAndExtract(input, "transition_js/transition.wasm", "transition_final.zkey");
    out.transitionRepayNonRoundInterest = { ...r, oldCommitment, newCommitment, checkpointIndex, currentIndex };
    console.log("transition (repay+non-round interest) done.");
  }

  // === reveal (circuit unchanged, setup regenerated) — same fixture as before ===
  {
    const collateral = ["5000000", "0", "0"];
    const debt = ["0", "1000000000", "0"];
    const salt = "12345";
    const commitment = commit([...collateral, ...debt, salt]);
    const input = {
      collateral, debt, salt, commitment,
      collateralAssetIndex: "0", collateralAmount: "5000000",
      debtAssetIndex: "1", debtAmount: "1000000000",
    };
    const r = await proveAndExtract(input, "reveal_js/reveal.wasm", "reveal_final.zkey");
    out.reveal = { ...r, commitment };
    console.log("reveal done.");
  }

  // === shielded_spend (circuit unchanged, setup regenerated) — same fixture as before ===
  {
    const TREE_DEPTH = 8;
    const P2 = (a, b) => F.toObject(poseidon([BigInt(a), BigInt(b)])).toString();
    const P3 = (a, b, c) => F.toObject(poseidon([BigInt(a), BigInt(b), BigInt(c)])).toString();
    const zeros = ["0"];
    for (let i = 1; i < TREE_DEPTH; i++) zeros.push(P2(zeros[i - 1], zeros[i - 1]));
    const amount = "3000000";
    const secret = "111222333";
    const commitment = P3(amount, secret, "0");
    const pathElements = zeros;
    const pathIndices = new Array(TREE_DEPTH).fill("0");
    let level = commitment;
    for (let i = 0; i < TREE_DEPTH; i++) level = P2(level, zeros[i]);
    const root = level;
    const withdrawAmount = "1000000";
    const changeAmount = "2000000";
    const changeSecret = "444555666";
    const newCommitment = P3(changeAmount, changeSecret, "0");
    const nullifier = P2(secret, "1");
    const recipient = "48879"; // address(0xBEEF)
    const input = { amount, secret, changeSecret, pathElements, pathIndices, root, nullifier, withdrawAmount, newCommitment, recipient };
    const r = await proveAndExtract(input, "shielded_spend_js/shielded_spend.wasm", "shielded_spend_final.zkey");
    out.shieldedSpend = { ...r, commitment, root, nullifier, newCommitment };
    console.log("shielded_spend done.");
  }

  fs.writeFileSync("all_fixtures.json", JSON.stringify(out, null, 2));
  console.log("\nWrote all_fixtures.json");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
