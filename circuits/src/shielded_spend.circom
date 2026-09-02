pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/mux1.circom";

// Circuit S — Shielded Spend. Proof-of-concept for gap #2 (event-log balance
// reconstruction), deliberately scoped: this proves the CORE mechanism of a
// variable-amount shielded pool works —
// it is NOT wired into VaultManager/borrow/repay/liquidation. Doing that is
// real future work (see ShieldedPool.sol's own top comment for the honest
// reason: it's a different data model — spend-a-note vs. update-a-position —
// not a small change to the existing contracts).
//
// A note is `commitment = Poseidon([amount, secret, 0])`, sitting as a leaf
// in a pool-wide (not per-position) Merkle tree of depth TREE_DEPTH. This
// circuit proves: "I know a genuine note in the tree at `root`, and here is
// its nullifier (uniquely tied to `secret`, so it can be spent only once,
// but reveals nothing about which leaf it came from) — I am publicly
// withdrawing `withdrawAmount` from it, and sealing the remainder into a new
// `newCommitment` note." Unlike Tornado Cash's fixed-denomination design,
// amounts here are arbitrary — value conservation (in-circuit, not via a
// separate homomorphic commitment scheme) is what makes that safe: the
// circuit knows the real amount as a private witness and enforces
// `withdrawAmount + changeAmount === amount` directly, the same pattern
// transition.circom already uses for collateral/debt deltas.
template ShieldedSpend(TREE_DEPTH) {
    // --- private ---
    signal input amount;
    signal input secret;
    signal input changeSecret;
    signal input pathElements[TREE_DEPTH];
    signal input pathIndices[TREE_DEPTH]; // 0 = current node is the left child, 1 = right

    // --- public ---
    signal input root;
    signal input nullifier;
    signal input withdrawAmount;
    signal input newCommitment;
    signal input recipient; // bound into the proof purely so a copied

    // Range checks, same purpose as every other circuit in this repo: a
    // GreaterEqThan/LessEqThan comparator is only sound once its inputs are
    // known to fit the claimed bit width.
    component amountBits = Num2Bits(50);
    amountBits.in <== amount;
    component withdrawBits = Num2Bits(50);
    withdrawBits.in <== withdrawAmount;

    component hasher = Poseidon(3);
    hasher.inputs[0] <== amount;
    hasher.inputs[1] <== secret;
    hasher.inputs[2] <== 0;
    signal commitment;
    commitment <== hasher.out;

    // Merkle inclusion proof: hash up from the leaf using the supplied
    // sibling path, selecting (left, right) order at each level via
    // pathIndices. Poseidon(2) here matches PoseidonT3.sol exactly — the
    // on-chain tree in ShieldedPool.sol is built with the very same
    // generated Poseidon contract, not a different hash pretending to agree.
    component levelHash[TREE_DEPTH];
    component left[TREE_DEPTH];
    component right[TREE_DEPTH];
    signal levels[TREE_DEPTH + 1];
    levels[0] <== commitment;
    for (var i = 0; i < TREE_DEPTH; i++) {
        pathIndices[i] * (1 - pathIndices[i]) === 0; // must be a bit

        left[i] = Mux1();
        left[i].c[0] <== levels[i];
        left[i].c[1] <== pathElements[i];
        left[i].s <== pathIndices[i];

        right[i] = Mux1();
        right[i].c[0] <== pathElements[i];
        right[i].c[1] <== levels[i];
        right[i].s <== pathIndices[i];

        levelHash[i] = Poseidon(2);
        levelHash[i].inputs[0] <== left[i].out;
        levelHash[i].inputs[1] <== right[i].out;
        levels[i + 1] <== levelHash[i].out;
    }
    levels[TREE_DEPTH] === root;

    // Nullifier: domain-separated from the commitment (tag 1 vs. tag 0) by
    // a different Poseidon arity, not just a different constant, so the two
    // can never collide as inputs to each other's hash.
    component nullifierHasher = Poseidon(2);
    nullifierHasher.inputs[0] <== secret;
    nullifierHasher.inputs[1] <== 1;
    nullifier === nullifierHasher.out;

    // withdrawAmount <= amount, so change can never underflow.
    component leq = LessEqThan(50);
    leq.in[0] <== withdrawAmount;
    leq.in[1] <== amount;
    leq.out === 1;

    signal changeAmount;
    changeAmount <== amount - withdrawAmount;

    component changeHasher = Poseidon(3);
    changeHasher.inputs[0] <== changeAmount;
    changeHasher.inputs[1] <== changeSecret;
    changeHasher.inputs[2] <== 0;
    newCommitment === changeHasher.out;

    // Defensive belt-and-suspenders binding for `recipient`, matching
    // Tornado Cash's own circuit convention: Groth16 already makes forging a
    // proof for different public inputs impossible, but squaring a public
    // signal that would otherwise appear in no constraint guards against a
    // narrower class of circuit-compiler bugs, at negligible cost.
    signal recipientSquare;
    recipientSquare <== recipient * recipient;
}

component main {public [root, nullifier, withdrawAmount, newCommitment, recipient]} = ShieldedSpend(8);
