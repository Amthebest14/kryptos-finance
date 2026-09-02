pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/bitify.circom";

// Circuit A — Health-Factor Proof.
//
// Proves a position is solvent (weighted collateral value >= debt value)
// without revealing collateral, debt, or the salt — only that the private
// values behind `commitment` satisfy the inequality, given public prices and
// liquidation thresholds. A proof can only be constructed when the position
// genuinely IS healthy: the health check is asserted inline (not an output
// signal a caller could generate-then-discard), so "a valid proof exists" and
// "the position is solvent" are the same statement.
//
// Fixed-point convention (all fixed-point, no floats — circom has no
// division primitive safe enough to use here, so everything is scaled
// integers and comparisons, never division):
//   collateral[i], debt[i] : token amount * 1e6   (private)
//   price[i]               : USD price * 1e6      (public)
//   liqThreshold[i]        : ratio * 1e6, e.g. 0.83 -> 830000  (public)
//   commitment             : Poseidon(collateral[0..2], debt[0..2], salt)
//
// Asset order is fixed: [WETH, USDC, ZEN], matching MARKET_ASSETS in the
// frontend. Three slots because that's the exact, complete set of assets
// this protocol supports today — not an approximation of a general N-asset
// system.
//
// Range checks below are not incidental — circomlib's comparators are only
// sound if their inputs are already known to fit within the claimed bit
// width (the field wraps otherwise, which a malicious prover could exploit
// to "prove" an unhealthy position healthy). Num2Bits enforces that by
// construction: the constraint system is unsatisfiable if a value needs more
// bits than given.
template HealthFactorProof() {
    signal input collateral[3];
    signal input debt[3];
    signal input salt;

    signal input price[3];
    signal input liqThreshold[3];
    signal input commitment;

    // AMOUNT_BITS(50) + PRICE_BITS(40) + LT_BITS(20) = 110 bits per term,
    // +2 bits of headroom for summing three terms = 112 bits max — safely
    // under the 128-bit comparator below, with real margin to spare.
    component cBits[3];
    component dBits[3];
    component pBits[3];
    component ltBits[3];
    for (var i = 0; i < 3; i++) {
        cBits[i] = Num2Bits(50);
        cBits[i].in <== collateral[i];
        dBits[i] = Num2Bits(50);
        dBits[i].in <== debt[i];
        pBits[i] = Num2Bits(40);
        pBits[i].in <== price[i];
        ltBits[i] = Num2Bits(20);
        ltBits[i].in <== liqThreshold[i];
    }

    // commitment == Poseidon(collateral[0..2], debt[0..2], salt)
    component hasher = Poseidon(7);
    for (var i = 0; i < 3; i++) {
        hasher.inputs[i] <== collateral[i];
        hasher.inputs[3 + i] <== debt[i];
    }
    hasher.inputs[6] <== salt;
    commitment === hasher.out;

    // collatTerm[i] = collateral[i] * price[i] * liqThreshold[i]
    // debtTerm[i]   = debt[i] * price[i] * 1_000_000  (the constant matches
    //                 liqThreshold's implicit 1e6 scale, so both sides land
    //                 in the same fixed-point units for a direct comparison)
    // circom constraints are quadratic only, so each three-way product is
    // split into two multiplications rather than written as one expression.
    signal collatStep[3];
    signal collatTerm[3];
    signal debtTerm[3];
    for (var i = 0; i < 3; i++) {
        collatStep[i] <== collateral[i] * price[i];
        collatTerm[i] <== collatStep[i] * liqThreshold[i];
        debtTerm[i] <== debt[i] * price[i] * 1000000;
    }

    signal collatSum;
    signal debtSum;
    collatSum <== collatTerm[0] + collatTerm[1] + collatTerm[2];
    debtSum <== debtTerm[0] + debtTerm[1] + debtTerm[2];

    component ge = GreaterEqThan(128);
    ge.in[0] <== collatSum;
    ge.in[1] <== debtSum;

    // Asserted directly, not exposed as an output — there is no way to
    // generate a valid proof for an unhealthy position and just ignore the
    // result, because an unhealthy position makes the constraint system
    // itself unsatisfiable.
    ge.out === 1;
}

component main {public [price, liqThreshold, commitment]} = HealthFactorProof();
