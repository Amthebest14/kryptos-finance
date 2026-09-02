// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PositionRegistry} from "./PositionRegistry.sol";
import {VaultManager} from "./VaultManager.sol";
import {IProofVerifier} from "./interfaces/IProofVerifier.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Settles stale positions. This is the answer to the hardest question in
/// private lending: how do you liquidate an undercollateralized position without
/// revealing who is undercollateralized?
///
/// Our answer, honestly scoped: liquidation here is a REVEAL, not a leak. A stale
/// position's owner (in practice, the same background agent that was submitting
/// their 30-minute health proofs) submits a proof that their sealed commitment opens
/// to specific collateral/debt amounts, and only THEN do those numbers become public
/// — for that one settlement, on a position that already failed to prove it was
/// healthy. Nobody ever had to watch a healthy position to catch this; the position
/// became visible by failing to check in, not by being spied on.
///
/// Real repayment, not just accounting: `liquidate()` requires the caller to
/// actually supply `debtAmount` of `debtAsset`, forwarded straight to
/// VaultManager, in exchange for the seized collateral. A previous version of
/// this contract let `seizeAndRepay` decrement VaultManager's totalBorrowed
/// accounting without ever receiving real tokens back, and never forwarded
/// the seized collateral to anyone — collateral sat frozen in this contract
/// forever (no withdrawal function existed), while the vault's real
/// liquidity was never actually restored despite the books claiming the
/// debt was repaid. Every liquidation under that version, including every
/// self-liquidation via "Settle now," silently made the protocol less
/// solvent than its own accounting claimed. Fixed here the standard way
/// (matching Aave/Compound's own liquidation pattern): whoever pays the real
/// debt receives the real collateral — repayment happens because someone
/// genuinely supplies it, not because a number was decremented.
///
/// gap #5's backstop, added below (proposeAbandonedClose / finalizeWithProof /
/// finalizeByTimeout): what to do about an owner who goes fully
/// unresponsive — no proof, no reveal, indefinitely. Stated precisely rather
/// than oversold, because the honest limit matters here: only the position
/// owner (or whoever holds the secret behind the commitment) can ever
/// construct a valid reveal proof. A textbook optimistic-challenge design
/// (bonded proposal, anyone can dispute with proof) assumes ANYONE with the
/// public data can construct a disputing proof — that assumption fails here
/// by design, since the whole point of sealing collateral/debt behind a
/// commitment is that nobody but the secret-holder can prove what the real
/// numbers are. So the challenge mechanism below provides REAL protection
/// only as long as the true secret-holder remains reachable (the common
/// case: slow or inattentive, not gone forever) — for a position that is
/// truly, permanently abandoned, an economically-discouraged (large bond,
/// long window) but not cryptographically-verified proposal will eventually
/// go through unchallenged. A real improvement over "frozen forever," not a
/// trustless guarantee in the hard case — documented here so nobody mistakes
/// it for one.
contract LiquidationHandler {
    PositionRegistry public immutable registry;
    VaultManager public immutable vault;
    IProofVerifier public immutable proofVerifier;

    // Extra time required, ON TOP OF a position already being stale (past
    // PROOF_INTERVAL + GRACE_PERIOD), before the backstop applies at all —
    // stale alone means "missed one 30-minute check-in," which happens to
    // perfectly healthy automation all the time; this is specifically for
    // positions nobody has touched in a long while.
    uint256 public constant ABANDONMENT_WINDOW = 24 hours;
    // How long a proposal stays open to a real reveal-proof correction
    // before it can be finalized unchallenged.
    uint256 public constant CHALLENGE_PERIOD = 48 hours;
    // Bond size as a fraction of the PROPOSER'S OWN claimed debt amount —
    // stated honestly: this is a real but imperfect deterrent. Because the
    // bond is pegged to the same number being claimed, an attacker who
    // deliberately under-claims debt also shrinks their own bond, so this
    // does not perfectly neutralize that specific attack — it raises the
    // cost and risk of trying, on a position only a truly negligent or
    // absent owner would fail to ever notice within the full
    // ABANDONMENT_WINDOW + CHALLENGE_PERIOD.
    uint256 public constant BOND_BPS = 5000; // 50%

    struct ProposedClose {
        address proposer;
        address collateralAsset;
        uint256 collateralAmount;
        address debtAsset;
        uint256 debtAmount;
        uint256 bond;
        uint256 proposedAt;
        bool active;
    }

    mapping(uint256 => ProposedClose) public proposedCloses;

    // No amounts here — matches the public feed's privacy rule (position ID + asset
    // pair + settled, nothing else). Amounts are visible only by deliberately
    // decoding this transaction's calldata, not surfaced to any indexer by default.
    event LiquidationSettled(
        uint256 indexed positionId, address indexed collateralAsset, address indexed debtAsset, uint256 timestamp
    );
    event CloseProposed(uint256 indexed positionId, address indexed proposer, uint256 bond);
    event CloseFinalized(uint256 indexed positionId, address indexed finalizer, bool proposalWasAccurate);
    event ProposalVoided(uint256 indexed positionId);

    constructor(address _registry, address _vault, address _proofVerifier) {
        registry = PositionRegistry(_registry);
        vault = VaultManager(_vault);
        proofVerifier = IProofVerifier(_proofVerifier);
    }

    /// @notice Settles a stale position in full: seizes all revealed collateral,
    /// repays all revealed debt, and closes the position. Partial liquidation
    /// (seizing less than the full position) is a known future refinement, not
    /// implemented here.
    ///
    /// `collateralAsset`/`debtAsset` are supplied by the caller rather than looked
    /// up on-chain — VaultManager only tracks global per-asset totals, never which
    /// asset a specific position used, so as not to store even that much about a
    /// position in the clear. Whoever calls this (in practice: the position's own
    /// automation) already knows the correct assets from that position's own
    /// deposit/borrow event history, which is public per-transaction by necessity.
    function liquidate(
        uint256 positionId,
        address collateralAsset,
        address debtAsset,
        bytes32 commitment,
        uint256 collateralAmount,
        uint256 debtAmount,
        bytes calldata revealProof
    ) external {
        require(registry.isStale(positionId), "LiquidationHandler: not stale");

        (bytes32 currentCommitment,,) = registry.positions(positionId);
        require(commitment == currentCommitment, "LiquidationHandler: commitment mismatch");

        require(
            proofVerifier.verifyReveal(
                positionId,
                commitment,
                vault.assetIndex(collateralAsset),
                collateralAmount,
                vault.assetIndex(debtAsset),
                debtAmount,
                revealProof
            ),
            "LiquidationHandler: invalid reveal proof"
        );

        _settle(positionId, collateralAsset, collateralAmount, debtAsset, debtAmount, "closed");
        emit LiquidationSettled(positionId, collateralAsset, debtAsset, block.timestamp);
    }

    /// @notice Starts the backstop clock on a position abandoned well beyond
    /// ordinary staleness. `collateralAmount`/`debtAmount` are the proposer's
    /// own claim — typically reconstructed off-chain from this position's
    /// public Deposited/Withdrawn/Borrowed/Repaid event history (a real,
    /// unavoidable property of this system: amounts are proven, not
    /// disclosed, in contract storage, but the public event log itself is
    /// still replayable by anyone) — not independently verified here beyond
    /// a sanity bound against the asset's own protocol-wide totals, and
    /// backed by a bond sized off that
    /// same claim (see BOND_BPS's own comment for why that's an honest,
    /// imperfect deterrent rather than a guarantee).
    function proposeAbandonedClose(
        uint256 positionId,
        address collateralAsset,
        uint256 collateralAmount,
        address debtAsset,
        uint256 debtAmount
    ) external {
        require(!proposedCloses[positionId].active, "LiquidationHandler: proposal already active");
        require(collateralAmount > 0 && debtAmount > 0, "LiquidationHandler: zero amount");
        // A position can never plausibly hold more of an asset than the
        // entire vault does — cheap, real, doesn't require the secret to
        // check, and rules out wildly implausible claims outright.
        require(collateralAmount <= vault.totalSupplied(collateralAsset), "LiquidationHandler: implausible collateral");
        require(debtAmount <= vault.totalBorrowed(debtAsset), "LiquidationHandler: implausible debt");

        (, uint64 lastProof, bool exists) = registry.positions(positionId);
        require(exists, "LiquidationHandler: no such position");
        uint256 staleAt = uint256(lastProof) + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD();
        require(block.timestamp > staleAt + ABANDONMENT_WINDOW, "LiquidationHandler: not abandoned long enough");

        uint256 bond = (debtAmount * BOND_BPS) / 10_000;
        require(IERC20(debtAsset).transferFrom(msg.sender, address(this), bond), "LiquidationHandler: bond payment failed");

        proposedCloses[positionId] = ProposedClose({
            proposer: msg.sender,
            collateralAsset: collateralAsset,
            collateralAmount: collateralAmount,
            debtAsset: debtAsset,
            debtAmount: debtAmount,
            bond: bond,
            proposedAt: block.timestamp,
            active: true
        });
        emit CloseProposed(positionId, msg.sender, bond);
    }

    /// @notice The safety valve: settles immediately using a REAL reveal
    /// proof instead of waiting out CHALLENGE_PERIOD — usable by the true
    /// owner correcting a wrong proposal, or by anyone else who happens to
    /// hold the secret. If the proof's real numbers match the pending
    /// proposal exactly, the proposer's bond is simply returned (they were
    /// right, no penalty). If they don't, the proposal was wrong — the
    /// bond goes to whoever proved the truth, as the reward for catching it.
    /// Either way, `msg.sender` completes the actual settlement here (real
    /// debt payment, real collateral in exchange), same as `liquidate()`.
    function finalizeWithProof(
        uint256 positionId,
        bytes32 commitment,
        address realCollateralAsset,
        uint256 realCollateralAmount,
        address realDebtAsset,
        uint256 realDebtAmount,
        bytes calldata revealProof
    ) external {
        ProposedClose memory p = proposedCloses[positionId];
        require(p.active, "LiquidationHandler: no active proposal");
        proposedCloses[positionId].active = false;

        if (_voidIfRecovered(positionId, p)) return;

        (bytes32 currentCommitment,,) = registry.positions(positionId);
        require(commitment == currentCommitment, "LiquidationHandler: commitment mismatch");
        require(
            proofVerifier.verifyReveal(
                positionId,
                commitment,
                vault.assetIndex(realCollateralAsset),
                realCollateralAmount,
                vault.assetIndex(realDebtAsset),
                realDebtAmount,
                revealProof
            ),
            "LiquidationHandler: invalid reveal proof"
        );

        bool accurate = p.collateralAsset == realCollateralAsset && p.collateralAmount == realCollateralAmount
            && p.debtAsset == realDebtAsset && p.debtAmount == realDebtAmount;
        address bondRecipient = accurate ? p.proposer : msg.sender;
        require(IERC20(p.debtAsset).transfer(bondRecipient, p.bond), "LiquidationHandler: bond transfer failed");

        _settle(positionId, realCollateralAsset, realCollateralAmount, realDebtAsset, realDebtAmount, "abandoned-closed");
        emit CloseFinalized(positionId, msg.sender, accurate);
    }

    /// @notice Anyone can complete an unchallenged proposal once
    /// CHALLENGE_PERIOD has passed — the proposer's bond returns to them
    /// (nobody proved them wrong), and `msg.sender` completes the actual
    /// settlement (real debt payment, real collateral in exchange).
    function finalizeByTimeout(uint256 positionId) external {
        ProposedClose memory p = proposedCloses[positionId];
        require(p.active, "LiquidationHandler: no active proposal");
        require(block.timestamp > p.proposedAt + CHALLENGE_PERIOD, "LiquidationHandler: challenge period not over");
        proposedCloses[positionId].active = false;

        if (_voidIfRecovered(positionId, p)) return;

        require(IERC20(p.debtAsset).transfer(p.proposer, p.bond), "LiquidationHandler: bond refund failed");
        _settle(positionId, p.collateralAsset, p.collateralAmount, p.debtAsset, p.debtAmount, "abandoned-closed");
        emit CloseFinalized(positionId, msg.sender, true);
    }

    /// @notice A position can recover on its own mid-proposal — the true
    /// owner resurfaces and submits a fresh health proof, un-staling it —
    /// without anyone touching this pending proposal. seizeAndRepay would
    /// simply revert against a non-stale position, which is safe but would
    /// leave the proposer's bond stuck forever with no path to reclaim it.
    /// Detected and voided here instead, refunding the bond — the proposer
    /// wasn't wrong, the situation just changed.
    function _voidIfRecovered(uint256 positionId, ProposedClose memory p) private returns (bool voided) {
        if (registry.isStale(positionId)) return false;
        require(IERC20(p.debtAsset).transfer(p.proposer, p.bond), "LiquidationHandler: bond refund failed");
        emit ProposalVoided(positionId);
        return true;
    }

    /// @notice Shared by every settlement path: real debt payment pulled
    /// from the caller straight into the vault (restoring its actual
    /// liquidity, not merely decrementing an accounting number), then the
    /// seized collateral forwarded from this contract on to the caller —
    /// seizeAndRepay only knows VaultManager's own liquidationHandler
    /// address, so it lands here first regardless.
    function _settle(
        uint256 positionId,
        address collateralAsset,
        uint256 collateralAmount,
        address debtAsset,
        uint256 debtAmount,
        bytes memory sealTag
    ) private {
        require(
            IERC20(debtAsset).transferFrom(msg.sender, address(vault), debtAmount),
            "LiquidationHandler: debt payment failed"
        );

        bytes32 closedSeal = keccak256(abi.encode(sealTag, positionId, block.timestamp));
        vault.seizeAndRepay(positionId, collateralAsset, collateralAmount, debtAsset, debtAmount, closedSeal);

        require(
            IERC20(collateralAsset).transfer(msg.sender, collateralAmount), "LiquidationHandler: collateral payout failed"
        );
    }
}
