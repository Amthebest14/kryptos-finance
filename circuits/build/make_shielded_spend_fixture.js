// Generates a real Circuit S (shielded_spend) witness/proof fixture for a
// single-leaf tree: leaf index 0's Merkle path against an otherwise-empty
// TREE_DEPTH=8 tree is trivial (every level: current is "left", sibling is
// zeros[i]) — this matches exactly what ShieldedPool.sol's constructor and
// _insert() compute on-chain for the very first deposit, so the fixture is
// exact, not approximate.
const { buildPoseidon } = require("circomlibjs");
const snarkjs = require("snarkjs");
const fs = require("fs");

const TREE_DEPTH = 8;
// address(0xBEEF) in the eventual Foundry test, as a decimal field element.
const RECIPIENT = "48879";

async function main() {
  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const toBig = (x) => F.toObject(x).toString();
  const P2 = (a, b) => toBig(poseidon([BigInt(a), BigInt(b)]));
  const P3 = (a, b, c) => toBig(poseidon([BigInt(a), BigInt(b), BigInt(c)]));

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
  const changeAmount = "2000000"; // amount - withdrawAmount
  const changeSecret = "444555666";
  const newCommitment = P3(changeAmount, changeSecret, "0");
  const nullifier = P2(secret, "1");

  const input = {
    amount, secret, changeSecret, pathElements, pathIndices,
    root, nullifier, withdrawAmount, newCommitment, recipient: RECIPIENT,
  };
  fs.writeFileSync("input_shielded_spend.json", JSON.stringify(input, null, 2));

  console.log("commitment:", commitment);
  console.log("root:", root);
  console.log("nullifier:", nullifier);
  console.log("newCommitment:", newCommitment);

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(
    input,
    "shielded_spend_js/shielded_spend.wasm",
    "shielded_spend_final.zkey"
  );
  console.log("publicSignals:", publicSignals);

  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const [pA, pB, pC, pub] = JSON.parse("[" + calldata.replace(/\]\[/g, "],[") + "]");
  fs.writeFileSync("shielded_spend_fixture.json", JSON.stringify({ pA, pB, pC, pub, commitment, root, nullifier, newCommitment, amount, withdrawAmount, changeAmount }, null, 2));
  console.log("Wrote shielded_spend_fixture.json");

  // Also verify locally before trusting it downstream.
  const vk = JSON.parse(fs.readFileSync("shielded_spend_verification_key.json"));
  const ok = await snarkjs.groth16.verify(vk, publicSignals, proof);
  console.log("Local verification:", ok);
}

main();
