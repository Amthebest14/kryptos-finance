// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Groth16Verifier as TransitionGroth16Verifier} from "./TransitionVerifier.sol";
import {Groth16Verifier as RevealGroth16Verifier} from "./RevealVerifier.sol";
import {IProofVerifier} from "./interfaces/IProofVerifier.sol";

/// @notice The real Phase 5 verifier behind every deposit/withdraw/borrow/repay
/// (Circuit T, transition.circom) and every liquidation (Circuit R, reveal.circom).
/// Before this contract, VaultManager and LiquidationHandler were wired to
/// MockProofVerifier, which accepted any proof unconditionally — a real, open gap
/// that let a caller move real tokens while sealing an arbitrary commitment. This
/// adapter is the fix: it holds no state of its own, only relays the caller's public
/// inputs to the matching Groth16 verifier and returns its answer unmodified.
///
/// `proof` in both functions is `abi.encode(pA, pB, pC)` — the raw Groth16 proof
/// components snarkjs produces, ABI-encoded as (uint256[2], uint256[2][2], uint256[2])
/// rather than passed as the separate calldata array a Foundry test would use
/// directly. This keeps the shared IProofVerifier interface's `bytes calldata proof`
/// parameter untouched across both the mock and this real implementation.
///
/// Unit conversion, and why it matters: VaultManager's `amount` (and therefore
/// every `collateralIncrease`/`collateralDecrease`/`debtIncrease`/`debtDecrease`/
/// `collateralAmount`/`debtAmount` this contract receives) is a raw ERC20 value
/// at 18 decimals. Both circuits
/// (transition.circom, reveal.circom) — and the Poseidon commitment scheme
/// they check against (kryptos-frontend/src/lib/localPosition.ts) — work in a
/// fixed-point convention of token units * 1e6, deliberately kept small enough
/// to fit the circuits' Num2Bits(50) range checks. The two scales differ by
/// exactly 1e12 (1e18 / 1e6), so every amount is converted here before being
/// placed in a circuit's public-signal array. Converting via integer division
/// and requiring an exact multiple (rather than silently flooring) matters for
/// more than tidiness: flooring would let a caller submit a valid proof for a
/// rounded-down delta while VaultManager still moves the *un-rounded* token
/// amount — e.g. a withdrawal of `K*1e12 + 999999999999` wei would only need
/// to prove removing `K` circuit-units of collateral, letting up to just under
/// 1e12 wei (a millionth of one token) leave the vault uncommitted-for. The
/// require below closes that off entirely rather than accepting the dust.
contract TransitionRevealAdapter is IProofVerifier {
    TransitionGroth16Verifier public immutable transitionVerifier;
    RevealGroth16Verifier public immutable revealVerifier;

    // 1e18 (ERC20 decimals) / 1e6 (circuit fixed-point scale).
    uint256 private constant WEI_PER_CIRCUIT_UNIT = 1e12;

    constructor(address _transitionVerifier, address _revealVerifier) {
        transitionVerifier = TransitionGroth16Verifier(_transitionVerifier);
        revealVerifier = RevealGroth16Verifier(_revealVerifier);
    }

    function _toCircuitUnits(uint256 weiAmount) private pure returns (uint256) {
        require(weiAmount % WEI_PER_CIRCUIT_UNIT == 0, "TransitionRevealAdapter: sub-circuit-precision amount");
        return weiAmount / WEI_PER_CIRCUIT_UNIT;
    }

    // Bundled into a struct purely to keep verifyTransition's own stack depth
    // low enough for solc's legacy codegen — 11 calldata parameters plus the
    // decoded proof components already pushes past what a single function
    // body can hold live at once ("stack too deep") without this.
    struct TransitionArgs {
        bytes32 oldCommitment;
        bytes32 newCommitment;
        uint256 assetIndex;
        uint256 collateralIncrease;
        uint256 collateralDecrease;
        uint256 principalIncrease;
        uint256 debtDecrease;
        uint256 interestAccrued;
        uint256 checkpointIndex;
        uint256 currentIndex;
    }

    /// @notice Token-amount fields (collateral/principal/debt-decrease/interest)
    /// are each independently converted from wei to circuit units.
    /// `checkpointIndex`/`currentIndex` are NOT converted — they're WAD-scaled
    /// (1e18) borrowIndex ratios, not token amounts, and transition.circom
    /// expects them in that native scale (see the circuit's own comment on why
    /// a ratio doesn't need the wei/circuit-unit conversion an amount does).
    function verifyTransition(
        uint256, /* positionId */
        bytes32 oldCommitment,
        bytes32 newCommitment,
        uint256 assetIndex,
        uint256 collateralIncrease,
        uint256 collateralDecrease,
        uint256 principalIncrease,
        uint256 debtDecrease,
        uint256 interestAccrued,
        uint256 checkpointIndex,
        uint256 currentIndex,
        bytes calldata proof
    ) external view override returns (bool) {
        TransitionArgs memory args;
        args.oldCommitment = oldCommitment;
        args.newCommitment = newCommitment;
        args.assetIndex = assetIndex;
        args.collateralIncrease = collateralIncrease;
        args.collateralDecrease = collateralDecrease;
        args.principalIncrease = principalIncrease;
        args.debtDecrease = debtDecrease;
        args.interestAccrued = interestAccrued;
        args.checkpointIndex = checkpointIndex;
        args.currentIndex = currentIndex;

        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));
        uint256[10] memory pubSignals = _transitionPublicSignals(args);

        return transitionVerifier.verifyProof(pA, pB, pC, pubSignals);
    }

    function _transitionPublicSignals(TransitionArgs memory a) private pure returns (uint256[10] memory) {
        return [
            uint256(a.oldCommitment),
            uint256(a.newCommitment),
            a.assetIndex,
            _toCircuitUnits(a.collateralIncrease),
            _toCircuitUnits(a.collateralDecrease),
            _toCircuitUnits(a.principalIncrease),
            _toCircuitUnits(a.debtDecrease),
            _toCircuitUnits(a.interestAccrued),
            a.checkpointIndex,
            a.currentIndex
        ];
    }

    function verifyReveal(
        uint256, /* positionId */
        bytes32 commitment,
        uint256 collateralAssetIndex,
        uint256 collateralAmount,
        uint256 debtAssetIndex,
        uint256 debtAmount,
        bytes calldata proof
    ) external view override returns (bool) {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));

        uint256[5] memory pubSignals = [
            uint256(commitment),
            collateralAssetIndex,
            _toCircuitUnits(collateralAmount),
            debtAssetIndex,
            _toCircuitUnits(debtAmount)
        ];

        return revealVerifier.verifyProof(pA, pB, pC, pubSignals);
    }
}
