pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/bitify.circom";

// Circuit R — Reveal Proof.
//
// Used only at liquidation, on a position already flagged stale (a pure
// public-timestamp check — see PositionRegistry.isStale — no secrets
// involved in reaching this point). Proves the sealed commitment truly
// opens to the now-public collateralAmount/debtAmount at the claimed asset
// slots, and that every other slot is zero. The liquidator can't be lied to
// about how much to seize: the revealed numbers are cryptographically tied
// to the commitment that was sealed all along, not asserted unchecked.
//
// Deliberate MVP scope, stated plainly: this handles a single collateral
// asset and a single debt asset per position, not an arbitrary multi-asset
// mix — matching LiquidationHandler's existing single-pair design. A
// position holding collateral or debt in more than one asset at the moment
// it goes stale cannot produce a valid reveal proof; extending this to
// multi-asset liquidation is a known follow-up, not attempted here.
template RevealProof() {
    signal input collateral[3];
    signal input debt[3];
    signal input salt;

    signal input commitment;
    signal input collateralAssetIndex;
    signal input collateralAmount;
    signal input debtAssetIndex;
    signal input debtAmount;

    component cBits[3];
    component dBits[3];
    for (var i = 0; i < 3; i++) {
        cBits[i] = Num2Bits(50);
        cBits[i].in <== collateral[i];
        dBits[i] = Num2Bits(50);
        dBits[i].in <== debt[i];
    }

    component hasher = Poseidon(7);
    for (var i = 0; i < 3; i++) {
        hasher.inputs[i] <== collateral[i];
        hasher.inputs[3 + i] <== debt[i];
    }
    hasher.inputs[6] <== salt;
    commitment === hasher.out;

    component ceq[3];
    signal cSel[3];
    for (var i = 0; i < 3; i++) {
        ceq[i] = IsEqual();
        ceq[i].in[0] <== collateralAssetIndex;
        ceq[i].in[1] <== i;
        cSel[i] <== ceq[i].out;
    }
    signal cSelSum;
    cSelSum <== cSel[0] + cSel[1] + cSel[2];
    cSelSum === 1;

    component deq[3];
    signal dSel[3];
    for (var i = 0; i < 3; i++) {
        deq[i] = IsEqual();
        deq[i].in[0] <== debtAssetIndex;
        deq[i].in[1] <== i;
        dSel[i] <== deq[i].out;
    }
    signal dSelSum;
    dSelSum <== dSel[0] + dSel[1] + dSel[2];
    dSelSum === 1;

    // Forces collateral[i] == collateralAmount at the selected slot and 0
    // everywhere else in one step — an unrevealed nonzero slot elsewhere
    // would make this constraint unsatisfiable, which is exactly the point.
    for (var i = 0; i < 3; i++) {
        collateral[i] === cSel[i] * collateralAmount;
        debt[i] === dSel[i] * debtAmount;
    }
}

component main {public [commitment, collateralAssetIndex, collateralAmount, debtAssetIndex, debtAmount]} = RevealProof();
