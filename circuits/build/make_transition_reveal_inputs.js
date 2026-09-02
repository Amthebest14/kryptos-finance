const { buildPoseidon } = require("circomlibjs");
const fs = require("fs");

async function main() {
  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const commit = (arr) => F.toObject(poseidon(arr.map(BigInt))).toString();

  // --- Transition fixture: second deposit, 5 WETH -> 7 WETH, no debt ---
  const oldCollateral = ["5000000", "0", "0"];
  const oldDebt = ["0", "0", "0"];
  const salt = "12345";
  const oldCommitment = commit([...oldCollateral, ...oldDebt, salt]);

  const newCollateral = ["7000000", "0", "0"]; // +2 WETH at index 0
  const newDebt = ["0", "0", "0"];
  const newCommitment = commit([...newCollateral, ...newDebt, salt]);

  const transitionInput = {
    oldCollateral, oldDebt, newCollateral, newDebt, salt,
    oldCommitment, newCommitment,
    assetIndex: "0",
    collateralIncrease: "2000000", collateralDecrease: "0",
    debtIncrease: "0", debtDecrease: "0",
  };
  fs.writeFileSync("input_transition.json", JSON.stringify(transitionInput, null, 2));
  console.log("transition oldCommitment:", oldCommitment);
  console.log("transition newCommitment:", newCommitment);

  // A transition claiming the WRONG delta against the same real commitments —
  // used to confirm witness generation genuinely fails for a dishonest claim.
  const transitionInputBad = { ...transitionInput, collateralIncrease: "3000000" };
  fs.writeFileSync("input_transition_bad.json", JSON.stringify(transitionInputBad, null, 2));

  // --- Reveal fixture: 5 WETH collateral, 1000 USDC debt (same as Circuit A's fixture) ---
  const collateral = ["5000000", "0", "0"];
  const debt = ["0", "1000000000", "0"];
  const revealSalt = "12345";
  const commitment = commit([...collateral, ...debt, revealSalt]);

  const revealInput = {
    collateral, debt, salt: revealSalt,
    commitment,
    collateralAssetIndex: "0", collateralAmount: "5000000",
    debtAssetIndex: "1", debtAmount: "1000000000",
  };
  fs.writeFileSync("input_reveal.json", JSON.stringify(revealInput, null, 2));
  console.log("reveal commitment:", commitment);

  // A reveal claiming the wrong debt amount — must fail to even generate a witness.
  const revealInputBad = { ...revealInput, debtAmount: "999999999" };
  fs.writeFileSync("input_reveal_bad.json", JSON.stringify(revealInputBad, null, 2));
}

main();
