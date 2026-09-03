pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/bitify.circom";

// Circuit T — Transition Proof.
//
// Used on every deposit/withdraw/borrow/repay. VaultManager knows the public
// token amount moved and which asset — it never learns the position's actual
// balances, only that the new sealed commitment is the old one with exactly
// that already-public change applied to exactly that asset slot, nothing
// else touched. Without this, a user could deposit real tokens but seal a
// commitment claiming a different balance entirely, producing valid
// health-factor proofs off numbers the protocol never actually received.
//
// Same fixed-point convention as health_factor.circom (amounts = token units
// * 1e6). Salt is a single persistent secret reused for the position's whole
// lifetime, matching how the frontend actually manages it — not
// independently randomized per transaction, so there is one salt input, not
// an old/new pair.
//
// gap #3 fix (self-reported interest was previously unconstrained): debt can
// grow for two genuinely different reasons — a new borrow (freely chosen by
// the caller, `principalIncrease`) and accrued interest on EXISTING debt
// (`interestAccrued`, which must match VaultManager's own on-chain
// `borrowIndex` ratio, not whatever the caller feels like claiming).
// `checkpointIndex`/`currentIndex` are WAD-scaled (1e18) public inputs the
// contract supplies from its own state (VaultManager.positionBorrowIndexSnapshot
// and .currentBorrowIndex respectively) — never caller-chosen, the same fix
// pattern PriceOracle.sol used for gap #1. For a call that isn't claiming any
// interest (deposit, withdraw, or a borrow/repay with nothing accrued yet),
// VaultManager passes checkpointIndex == currentIndex, which forces
// `interestAccrued === 0` regardless of oldDebt (see the remainder check
// below — indexDelta collapsing to 0 leaves no room for anything else).
//
// interestAccrued is proven as floor(oldDebt * indexDelta / checkpointIndex),
// not required to divide out exactly — a real, previously-shipped bug here
// demanded exact equality, which real interest essentially never satisfies
// (checkpointIndex is a huge WAD-scaled value with no reason to divide the
// product evenly), failing on essentially every call with any nonzero
// elapsed time. Caught live, on a real repay, not in testing — every prior
// test happened to touch its asset with zero elapsed interest, collapsing
// the old check to the trivial 0 === 0 case.
template TransitionProof() {
    signal input oldCollateral[3];
    signal input oldDebt[3];
    signal input newCollateral[3];
    signal input newDebt[3];
    signal input salt;

    signal input oldCommitment;
    signal input newCommitment;
    signal input assetIndex; // which of [WETH, USDC, ZEN] this transaction touched
    signal input collateralIncrease;
    signal input collateralDecrease;
    signal input principalIncrease;
    signal input debtDecrease;
    signal input interestAccrued;
    signal input checkpointIndex;
    signal input currentIndex;

    // Range checks — comparators/selectors below are only sound if these are
    // already known to fit their claimed bit width (see health_factor.circom
    // for why this isn't optional hardening). Index values get a wider bound
    // (100 bits) than token amounts (50 bits): WAD-scaled (1e18 ~ 2^60) and
    // growing multiplicatively over the life of the market, unlike a single
    // transaction's bounded token amount.
    component ocBits[3];
    component odBits[3];
    component ncBits[3];
    component ndBits[3];
    for (var i = 0; i < 3; i++) {
        ocBits[i] = Num2Bits(50);
        ocBits[i].in <== oldCollateral[i];
        odBits[i] = Num2Bits(50);
        odBits[i].in <== oldDebt[i];
        ncBits[i] = Num2Bits(50);
        ncBits[i].in <== newCollateral[i];
        ndBits[i] = Num2Bits(50);
        ndBits[i].in <== newDebt[i];
    }
    component ciBits = Num2Bits(50);
    ciBits.in <== collateralIncrease;
    component cdBits = Num2Bits(50);
    cdBits.in <== collateralDecrease;
    component piBits = Num2Bits(50);
    piBits.in <== principalIncrease;
    component ddBits = Num2Bits(50);
    ddBits.in <== debtDecrease;
    component iaBits = Num2Bits(50);
    iaBits.in <== interestAccrued;
    component ckBits = Num2Bits(100);
    ckBits.in <== checkpointIndex;
    component cuBits = Num2Bits(100);
    cuBits.in <== currentIndex;

    component oldHasher = Poseidon(7);
    component newHasher = Poseidon(7);
    for (var i = 0; i < 3; i++) {
        oldHasher.inputs[i] <== oldCollateral[i];
        oldHasher.inputs[3 + i] <== oldDebt[i];
        newHasher.inputs[i] <== newCollateral[i];
        newHasher.inputs[3 + i] <== newDebt[i];
    }
    oldHasher.inputs[6] <== salt;
    newHasher.inputs[6] <== salt;
    oldCommitment === oldHasher.out;
    newCommitment === newHasher.out;

    // sel[i] = 1 iff assetIndex == i. Requiring the three sum to exactly 1
    // also constrains assetIndex to genuinely be one of {0,1,2} — a value
    // outside that range would make every sel[i] zero, failing the sum check.
    component eq[3];
    signal sel[3];
    for (var i = 0; i < 3; i++) {
        eq[i] = IsEqual();
        eq[i].in[0] <== assetIndex;
        eq[i].in[1] <== i;
        sel[i] <== eq[i].out;
    }
    signal selSum;
    selSum <== sel[0] + sel[1] + sel[2];
    selSum === 1;

    // currentIndex can only ever grow relative to checkpointIndex — a
    // defensive bound, not load-bearing for the constraint below (which
    // works whichever direction the subtraction went), but cheap insurance
    // against a checkpoint ordering bug upstream ever going unnoticed.
    component indexOrder = GreaterEqThan(100);
    indexOrder.in[0] <== currentIndex;
    indexOrder.in[1] <== checkpointIndex;
    indexOrder.out === 1;

    // The interest actually owed on the touched asset's EXISTING debt since
    // its last checkpoint is oldDebtSelected * (currentIndex/checkpointIndex - 1).
    // Restated as a cross-multiplication to avoid field division:
    //   interestAccrued * checkpointIndex === oldDebtSelected * (currentIndex - checkpointIndex)
    // When checkpointIndex == currentIndex (nothing accrued to claim this
    // call), the right side is forced to 0, which forces interestAccrued to
    // 0 too — exactly the "no interest claimed" case, regardless of
    // oldDebtSelected's value.
    signal oldDebtSel[3];
    for (var i = 0; i < 3; i++) {
        oldDebtSel[i] <== sel[i] * oldDebt[i];
    }
    signal oldDebtSelected;
    oldDebtSelected <== oldDebtSel[0] + oldDebtSel[1] + oldDebtSel[2];
    signal indexDelta;
    indexDelta <== currentIndex - checkpointIndex;
    // Split into two quadratic steps (circom constraints are quadratic-only —
    // see health_factor.circom's own collatStep/collatTerm split for the same
    // reasoning applied to a three-way product).
    signal interestLHS;
    interestLHS <== interestAccrued * checkpointIndex;
    signal interestRHS;
    interestRHS <== oldDebtSelected * indexDelta;
    // Floor division, proven via a bounded remainder rather than asking
    // interestLHS to equal interestRHS exactly. Both products can run up to
    // ~150 bits (50-bit debt/interest values times 100-bit index values),
    // but the remainder itself is provably under checkpointIndex (<2^100),
    // so only that difference — not the full products — needs range-checking.
    // Num2Bits(100) alone already rejects an over-claimed interestAccrued
    // (the subtraction goes negative, wrapping to a field element nowhere
    // near representable in 100 bits); the LessThan below catches an
    // under-claimed one (a remainder that's nonnegative but not actually
    // smaller than checkpointIndex).
    signal interestRemainder;
    interestRemainder <== interestRHS - interestLHS;
    component remainderBits = Num2Bits(100);
    remainderBits.in <== interestRemainder;
    component remainderLtCheckpoint = LessThan(100);
    remainderLtCheckpoint.in[0] <== interestRemainder;
    remainderLtCheckpoint.in[1] <== checkpointIndex;
    remainderLtCheckpoint.out === 1;

    // newCollateral[i] == oldCollateral[i] + sel[i]*(increase - decrease), and
    // likewise for debt (principal borrow + accrued interest, minus
    // repayment) — the untouched slots (sel[i] == 0) collapse to
    // "unchanged", the touched slot gets exactly the claimed delta.
    signal cInc[3];
    signal cDec[3];
    signal dPrin[3];
    signal dInt[3];
    signal dDec[3];
    for (var i = 0; i < 3; i++) {
        cInc[i] <== sel[i] * collateralIncrease;
        cDec[i] <== sel[i] * collateralDecrease;
        dPrin[i] <== sel[i] * principalIncrease;
        dInt[i] <== sel[i] * interestAccrued;
        dDec[i] <== sel[i] * debtDecrease;
        newCollateral[i] === oldCollateral[i] + cInc[i] - cDec[i];
        newDebt[i] === oldDebt[i] + dPrin[i] + dInt[i] - dDec[i];
    }
}

component main {public [
    oldCommitment, newCommitment, assetIndex,
    collateralIncrease, collateralDecrease,
    principalIncrease, debtDecrease, interestAccrued,
    checkpointIndex, currentIndex
]} = TransitionProof();
