// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Verifies zero-knowledge proofs submitted against a position's sealed
/// commitment. The real implementation (Phase 5) relays these to zkVerify; for now
/// VaultManager is built against this interface so it can be tested independently
/// of the circuit work.
interface IProofVerifier {
    /// @notice Proves `newCommitment` is `oldCommitment` correctly updated by the
    /// given public collateral/debt amounts — without revealing the underlying
    /// collateral or debt values themselves. `oldCommitment == bytes32(0)` means
    /// there is no prior state to be consistent with (a freshly opened position).
    /// `assetIndex` identifies which listed asset (VaultManager's fixed
    /// [WETH, USDC, ZEN] ordering) this transaction touched — the circuit needs
    /// it to know which of the three collateral/debt slots applies.
    ///
    /// Debt has three independent components, not one signed delta, because a
    /// single call can genuinely need more than one at once — a repay that also
    /// folds in accrued interest needs debt to go up (interest) and down
    /// (the repayment) in the same transition proof:
    ///   - `principalIncrease`: new borrowing, freely chosen by the caller.
    ///   - `debtDecrease`: repayment, freely chosen by the caller.
    ///   - `interestAccrued`: NOT freely chosen — transition.circom constrains
    ///     it against `checkpointIndex`/`currentIndex` (VaultManager's own
    ///     borrowIndex ratio for this asset, supplied by the caller here from
    ///     its own on-chain state, never accepted from whoever is calling
    ///     VaultManager). This is what makes gap #3's fix real: before it,
    ///     what's now `interestAccrued` was folded into an unconstrained
    ///     `debtIncrease` a caller could set to anything.
    function verifyTransition(
        uint256 positionId,
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
    ) external returns (bool);

    /// @notice Proves `commitment` opens to exactly `collateralAmount` at
    /// `collateralAssetIndex` and `debtAmount` at `debtAssetIndex` (with every other
    /// slot zero). Used only at liquidation, to reveal a stale position's true
    /// numbers under cryptographic guarantee — a liquidator acting on this can't be
    /// lied to about how much to seize. Revealing is the mechanism here, not a leak:
    /// it only happens for a position that already failed to prove it was healthy.
    function verifyReveal(
        uint256 positionId,
        bytes32 commitment,
        uint256 collateralAssetIndex,
        uint256 collateralAmount,
        uint256 debtAssetIndex,
        uint256 debtAmount,
        bytes calldata proof
    ) external returns (bool);
}
