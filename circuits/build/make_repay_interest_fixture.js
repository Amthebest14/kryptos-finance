// Fixture proving transition.circom's debtIncrease AND debtDecrease can both
// be nonzero in the SAME proof — the exact scenario the IProofVerifier
// interface was changed to support: a repay that also folds in self-reported
// accrued interest (debt grows by interest owed, then shrinks by the
// repayment, in one call).
const { buildPoseidon } = require("circomlibjs");
const fs = require("fs");

async function main() {
  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const commit = (arr) => F.toObject(poseidon(arr.map(BigInt))).toString();

  // 5 WETH collateral, 1000 USDC debt -> repay 100 USDC but 50 USDC of
  // interest accrued since the last snapshot, net debt: 1000 + 50 - 100 = 950.
  const oldCollateral = ["5000000", "0", "0"];
  const oldDebt = ["0", "1000000000", "0"];
  const salt = "12345";
  const oldCommitment = commit([...oldCollateral, ...oldDebt, salt]);

  const newCollateral = ["5000000", "0", "0"];
  const newDebt = ["0", "950000000", "0"];
  const newCommitment = commit([...newCollateral, ...newDebt, salt]);

  const input = {
    oldCollateral, oldDebt, newCollateral, newDebt, salt,
    oldCommitment, newCommitment,
    assetIndex: "1", // USDC
    collateralIncrease: "0", collateralDecrease: "0",
    debtIncrease: "50000000", debtDecrease: "100000000",
  };
  fs.writeFileSync("input_repay_interest.json", JSON.stringify(input, null, 2));
  console.log("repay-with-interest oldCommitment:", oldCommitment);
  console.log("repay-with-interest newCommitment:", newCommitment);
}

main();
