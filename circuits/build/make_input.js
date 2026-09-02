const { buildPoseidon } = require("circomlibjs");
const fs = require("fs");

async function main() {
  const poseidon = await buildPoseidon();
  const F = poseidon.F;

  // Healthy case: 5 WETH collateral, 1000 USDC debt.
  const collateral = ["5000000", "0", "0"];
  const debt = ["0", "1000000000", "0"];
  const salt = "12345";
  const price = ["2473760000", "1000000", "5000000"];
  const liqThreshold = ["830000", "900000", "650000"];

  const hash = poseidon([...collateral, ...debt, salt].map(BigInt));
  const commitment = F.toObject(hash).toString();

  const input = { collateral, debt, salt, price, liqThreshold, commitment };
  fs.writeFileSync("input_healthy.json", JSON.stringify(input, null, 2));
  console.log("commitment:", commitment);
  console.log("wrote input_healthy.json");

  // Unhealthy case: same commitment inputs but debt way too high relative to
  // collateral — used to confirm the circuit REFUSES to produce a proof.
  const debtUnhealthy = ["0", "50000000000", "0"]; // 50,000 USDC debt against 5 WETH
  const hashUnhealthy = poseidon([...collateral, ...debtUnhealthy, salt].map(BigInt));
  const commitmentUnhealthy = F.toObject(hashUnhealthy).toString();
  const inputUnhealthy = { collateral, debt: debtUnhealthy, salt, price, liqThreshold, commitment: commitmentUnhealthy };
  fs.writeFileSync("input_unhealthy.json", JSON.stringify(inputUnhealthy, null, 2));
  console.log("wrote input_unhealthy.json");
}

main();
