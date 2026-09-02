// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PositionRegistry} from "./PositionRegistry.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IProofVerifier} from "./interfaces/IProofVerifier.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import {ZenStaking} from "./ZenStaking.sol";

/// @notice Moves real tokens and keeps PositionRegistry's sealed commitment in sync.
///
/// Every state-changing call after a position's first deposit requires a transition
/// proof: cryptographic evidence that the new commitment correctly reflects the old
/// commitment plus this call's public token delta. Without that, a user could deposit
/// real tokens but seal an inflated commitment, then generate valid health-factor
/// proofs off numbers the protocol never actually received — silent bad debt with no
/// on-chain trace. The transfer amount itself IS visible on-chain, because moving a
/// public ERC20 is inherently transparent at the transaction level — that is an
/// accepted tradeoff, not an oversight.
///
/// Precisely what stays hidden, stated carefully rather than overclaimed: no
/// contract in this system ever writes plaintext collateral, debt, or health
/// factor to STORAGE, and no proof verifier ever learns those numbers to check
/// solvency. What this does NOT hide: every deposit/withdraw/borrow/repay's
/// public delta (this function's own `amount` parameter, and the matching
/// Deposited/Withdrawn/Borrowed/Repaid event) is tied to a specific caller and,
/// through positionOf, a specific position. Anyone replaying full transaction
/// history can sum a position's own public deltas and reconstruct its exact
/// running collateral and debt — and, combined with already-public prices,
/// its exact health factor — continuously, not just at proof submission
/// moments. That is a direct consequence of choosing zkVerify-style proof
/// verification (this project's actual choice) over a TEE-based confidential
/// execution environment like Vela: on a transparent L3, the underlying
/// transfer amount has to be public for anyone to verify it happened at all.
/// Closing this specific gap for real needs a fundamentally different
/// transfer mechanism (a shielded pool of spendable note-commitments with
/// nullifiers, roughly Tornado/Aztec-style) rather than a change to this
/// contract — documented as known, unresolved future work, not hidden.
contract VaultManager {
    uint256 private constant WAD = 1e18;

    PositionRegistry public immutable registry;
    IProofVerifier public immutable proofVerifier;
    InterestRateModel public immutable interestRateModel;
    ZenStaking public immutable zenStaking;
    address public owner;
    address public liquidationHandler;

    mapping(address => bool) public supportedAssets;
    address[] public assetList;

    // Fixed per-asset index (0 = WETH, 1 = USDC, 2 = ZEN in this deployment's listing
    // order) — the transition circuit needs to know which of the position's three
    // collateral/debt slots a call's public delta applies to, without VaultManager
    // ever storing the position's actual per-asset balances itself.
    mapping(address => uint256) public assetIndex;

    // Aggregate, per-asset totals — these are meant to be public (Guidepost metrics).
    mapping(address => uint256) public totalSupplied;
    mapping(address => uint256) public totalBorrowed;

    // Compound-style borrow index per asset (WAD-scaled, starts at 1e18) —
    // grows over time based on InterestRateModel's rate for that asset's
    // current utilization, checkpointed on every borrow/repay. This is the
    // ONLY interest-related state VaultManager itself tracks: a public
    // reference index, never anyone's actual debt (which stays sealed inside
    // each position's private commitment, exactly as before). A client who
    // knows their own principal can compute exactly how much interest they
    // owe from the ratio between this index now and its value at their last
    // snapshot — see positionBorrowIndexSnapshot below.
    mapping(address => uint256) public borrowIndex;
    mapping(address => uint256) public lastAccrualTimestamp;
    // positionId => asset => borrowIndex[asset] at that position's last
    // borrow/repay of that asset. Public, but reveals nothing private — it's
    // just a timestamp-equivalent checkpoint into an already-public index.
    mapping(uint256 => mapping(address => uint256)) public positionBorrowIndexSnapshot;

    struct UserPosition {
        uint256 positionId;
        bool active;
    }
    mapping(address => UserPosition) public positionOf;
    // Reverse lookup, set once on a position's first-ever deposit — lets
    // seizeAndRepay() find whose `active` flag to clear on liquidation. Never
    // reused for anything privacy-sensitive: it's just "which wallet opened
    // this already-public position ID," which positionOf's own forward
    // direction already implies.
    mapping(uint256 => address) public positionOwner;

    event AssetListed(address indexed asset);
    event LiquidationHandlerSet(address indexed handler);
    event Deposited(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount);
    event Repaid(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount);
    event Seized(
        uint256 indexed positionId,
        address indexed collateralAsset,
        uint256 collateralAmount,
        address indexed debtAsset,
        uint256 debtRepaid
    );
    event PositionClosed(uint256 indexed positionId, address indexed owner);

    modifier onlyOwner() {
        require(msg.sender == owner, "VaultManager: not owner");
        _;
    }

    modifier onlyLiquidationHandler() {
        require(msg.sender == liquidationHandler, "VaultManager: not liquidation handler");
        _;
    }

    modifier onlySupported(address asset) {
        require(supportedAssets[asset], "VaultManager: unsupported asset");
        _;
    }

    constructor(address _registry, address _proofVerifier, address _interestRateModel, address _zenStaking) {
        registry = PositionRegistry(_registry);
        proofVerifier = IProofVerifier(_proofVerifier);
        interestRateModel = InterestRateModel(_interestRateModel);
        zenStaking = ZenStaking(_zenStaking);
        owner = msg.sender;
    }

    function listAsset(address asset) external onlyOwner {
        require(!supportedAssets[asset], "VaultManager: already listed");
        supportedAssets[asset] = true;
        assetIndex[asset] = assetList.length;
        assetList.push(asset);
        borrowIndex[asset] = WAD;
        lastAccrualTimestamp[asset] = block.timestamp;
        emit AssetListed(asset);
    }

    /// @notice Checkpoints borrowIndex[asset] forward using the time elapsed
    /// since its last checkpoint and the current utilization's borrow rate —
    /// standard lazy/piecewise-constant accrual (Compound's own pattern):
    /// exact between checkpoints, a linear approximation across the elapsed
    /// window since the last one, accurate as long as checkpoints happen
    /// often relative to how fast the rate itself moves.
    function _accrueInterest(address asset) private {
        uint256 elapsed = block.timestamp - lastAccrualTimestamp[asset];
        if (elapsed == 0) return;
        uint256 ratePerSecond = interestRateModel.getBorrowRatePerSecond(totalSupplied[asset], totalBorrowed[asset]);
        borrowIndex[asset] += (borrowIndex[asset] * ratePerSecond * elapsed) / WAD;
        lastAccrualTimestamp[asset] = block.timestamp;
    }

    /// @notice What borrowIndex[asset] would be checkpointed to right now,
    /// without writing state — lets a client compute its own accrued
    /// interest using the exact same formula the next real transaction would
    /// apply, rather than reimplementing it and risking drift.
    function currentBorrowIndex(address asset) external view returns (uint256) {
        uint256 elapsed = block.timestamp - lastAccrualTimestamp[asset];
        if (elapsed == 0) return borrowIndex[asset];
        uint256 ratePerSecond = interestRateModel.getBorrowRatePerSecond(totalSupplied[asset], totalBorrowed[asset]);
        return borrowIndex[asset] + (borrowIndex[asset] * ratePerSecond * elapsed) / WAD;
    }

    function setLiquidationHandler(address handler) external onlyOwner {
        liquidationHandler = handler;
        emit LiquidationHandlerSet(handler);
    }

    function getAssetList() external view returns (address[] memory) {
        return assetList;
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        require(IERC20(token).transfer(to, amount), "VaultManager: transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        require(IERC20(token).transferFrom(from, to, amount), "VaultManager: transferFrom failed");
    }

    // Factored out of deposit/withdraw/borrow/repay so each of those keeps
    // few enough simultaneously-live locals for solc's legacy codegen — with
    // the 11-argument verifyTransition call inlined into each caller
    // directly, all four push past the EVM's 16-slot stack addressing limit
    // ("stack too deep").
    function _submitTransition(
        uint256 positionId,
        bytes32 oldCommitment,
        bytes32 newCommitment,
        uint256 idx,
        uint256 collateralIncrease,
        uint256 collateralDecrease,
        uint256 principalIncrease,
        uint256 debtDecrease,
        uint256 interestAccrued,
        uint256 checkpointIndex,
        uint256 currentIndex,
        bytes calldata transitionProof
    ) private {
        require(
            proofVerifier.verifyTransition(
                positionId,
                oldCommitment,
                newCommitment,
                idx,
                collateralIncrease,
                collateralDecrease,
                principalIncrease,
                debtDecrease,
                interestAccrued,
                checkpointIndex,
                currentIndex,
                transitionProof
            ),
            "VaultManager: invalid transition proof"
        );
        registry.updateCommitment(positionId, newCommitment);
    }

    // Shared by deposit/withdraw specifically — both touch only collateral,
    // never debt, so checkpointIndex == currentIndex always (collapsing
    // transition.circom's interest constraint to "0 accrued," see that
    // circuit's own comment) and neither needs `_borrowIndexCheckpoint`'s
    // zero-checkpoint handling. Factored out purely to keep deposit/withdraw
    // themselves under solc's legacy-codegen stack-depth limit — inlining
    // this call's 12 arguments directly into either caller (on top of their
    // own locals) pushes past it ("stack too deep").
    function _submitCollateralTransition(
        uint256 positionId,
        bytes32 oldCommitment,
        bytes32 newCommitment,
        address asset,
        uint256 collateralIncrease,
        uint256 collateralDecrease,
        bytes calldata transitionProof
    ) private {
        uint256 idxSnap = positionBorrowIndexSnapshot[positionId][asset];
        _submitTransition(
            positionId,
            oldCommitment,
            newCommitment,
            assetIndex[asset],
            collateralIncrease,
            collateralDecrease,
            0,
            0,
            0,
            idxSnap,
            idxSnap,
            transitionProof
        );
    }

    // Shared by borrow/repay: accrues the asset's index forward, resolves the
    // position's checkpoint (via _borrowIndexCheckpoint below), submits the
    // transition, and re-snapshots — all four in one place so borrow/repay
    // themselves stay under solc's legacy-codegen stack-depth limit the same
    // way _submitCollateralTransition does for deposit/withdraw.
    function _submitDebtTransition(
        uint256 positionId,
        bytes32 oldCommitment,
        bytes32 newCommitment,
        address asset,
        uint256 principalIncrease,
        uint256 debtDecrease,
        uint256 interestAccrued,
        bytes calldata transitionProof
    ) private returns (uint256 currentIdx) {
        _accrueInterest(asset);
        currentIdx = borrowIndex[asset];
        uint256 checkpointIdx = _borrowIndexCheckpoint(positionId, asset, currentIdx);

        _submitTransition(
            positionId,
            oldCommitment,
            newCommitment,
            assetIndex[asset],
            0,
            0,
            principalIncrease,
            debtDecrease,
            interestAccrued,
            checkpointIdx,
            currentIdx,
            transitionProof
        );
        positionBorrowIndexSnapshot[positionId][asset] = currentIdx;
    }

    // A position's checkpoint defaults to 0 (never snapshotted) until its
    // first borrow/repay of `asset` — borrowIndex[asset] itself can never
    // legitimately be 0 once listed (it starts at WAD and only grows), so 0
    // unambiguously means "no prior checkpoint." Collapsing that case to
    // checkpointIndex == currentIndex (rather than leaving it 0) matters for
    // soundness, not just tidiness: transition.circom's interest constraint
    // is `interestAccrued * checkpointIndex === oldDebtSelected * indexDelta`
    // — with checkpointIndex left at a genuine 0, that constraint collapses
    // to `0 === oldDebtSelected * currentIndex`, which is satisfied by
    // oldDebtSelected == 0 (true on a first borrow) regardless of what
    // interestAccrued claims, defeating the whole point of gap #3's fix.
    function _borrowIndexCheckpoint(uint256 positionId, address asset, uint256 currentIndex)
        private
        view
        returns (uint256 checkpointIndex)
    {
        checkpointIndex = positionBorrowIndexSnapshot[positionId][asset];
        if (checkpointIndex == 0) checkpointIndex = currentIndex;
    }

    /// @notice First deposit for a wallet opens its position with `newCommitment` as
    /// the initial seal — there is no prior state to prove a transition against.
    /// Every deposit after that must prove the transition like any other call.
    function deposit(address asset, uint256 amount, bytes32 newCommitment, bytes calldata transitionProof)
        external
        onlySupported(asset)
    {
        require(amount > 0, "VaultManager: zero amount");

        UserPosition storage up = positionOf[msg.sender];
        uint256 positionId;
        if (!up.active) {
            positionId = registry.openPosition(newCommitment);
            up.positionId = positionId;
            up.active = true;
            positionOwner[positionId] = msg.sender;
        } else {
            positionId = up.positionId;
            (bytes32 oldCommitment,,) = registry.positions(positionId);
            _submitCollateralTransition(positionId, oldCommitment, newCommitment, asset, amount, 0, transitionProof);
        }

        _safeTransferFrom(asset, msg.sender, address(this), amount);
        totalSupplied[asset] += amount;

        emit Deposited(msg.sender, positionId, asset, amount);
    }

    /// @notice Blocked while stale — withdrawing is risk-increasing and the position
    /// has already failed to prove it can absorb that.
    function withdraw(address asset, uint256 amount, bytes32 newCommitment, bytes calldata transitionProof)
        external
        onlySupported(asset)
    {
        require(amount > 0, "VaultManager: zero amount");
        UserPosition memory up = positionOf[msg.sender];
        require(up.active, "VaultManager: no position");
        require(!registry.isStale(up.positionId), "VaultManager: position stale");

        (bytes32 oldCommitment,,) = registry.positions(up.positionId);
        _submitCollateralTransition(up.positionId, oldCommitment, newCommitment, asset, 0, amount, transitionProof);

        totalSupplied[asset] -= amount;
        _safeTransfer(asset, msg.sender, amount);

        emit Withdrawn(msg.sender, up.positionId, asset, amount);
    }

    /// @notice Blocked while stale, same reasoning as withdraw. `accruedInterest`
    /// is how much interest this position owes on `asset`'s debt since its last
    /// snapshot of borrowIndex[asset] (currentBorrowIndex(asset) lets the client
    /// compute this from its own known principal) — and, as of gap #3's fix, no
    /// longer merely self-reported: transition.circom cryptographically checks
    /// it against oldDebt (a private witness) and the checkpoint/current index
    /// ratio (public, contract-supplied here, never caller-chosen). A caller
    /// claiming the wrong amount simply cannot produce a valid proof for it.
    function borrow(
        address asset,
        uint256 amount,
        uint256 accruedInterest,
        bytes32 newCommitment,
        bytes calldata transitionProof
    ) external onlySupported(asset) {
        require(amount > 0, "VaultManager: zero amount");
        UserPosition memory up = positionOf[msg.sender];
        require(up.active, "VaultManager: no position");
        require(!registry.isStale(up.positionId), "VaultManager: position stale");

        (bytes32 oldCommitment,,) = registry.positions(up.positionId);
        _submitDebtTransition(up.positionId, oldCommitment, newCommitment, asset, amount, 0, accruedInterest, transitionProof);

        totalBorrowed[asset] += amount;
        _safeTransfer(asset, msg.sender, amount);

        emit Borrowed(msg.sender, up.positionId, asset, amount);
    }

    /// @notice Always allowed, even while stale — repaying is how a user saves
    /// themselves, and blocking it here would defeat the point of the grace
    /// period. `accruedInterest` (see borrow's comment above — cryptographically
    /// checked, not self-reported) is added to debt and `amount` is subtracted,
    /// in the SAME transition proof, which is exactly why IProofVerifier takes
    /// independent increase/decrease values instead of one signed delta.
    /// Whatever portion of `accruedInterest` this repayment actually covers
    /// (capped at `amount`) is forwarded to ZenStaking as real interest
    /// revenue — but only when someone has actually staked ZEN to receive it;
    /// otherwise it's simply left as idle vault liquidity instead of sent
    /// somewhere unclaimable.
    function repay(
        address asset,
        uint256 amount,
        uint256 accruedInterest,
        bytes32 newCommitment,
        bytes calldata transitionProof
    ) external onlySupported(asset) {
        require(amount > 0, "VaultManager: zero amount");
        UserPosition memory up = positionOf[msg.sender];
        require(up.active, "VaultManager: no position");

        (bytes32 oldCommitment,,) = registry.positions(up.positionId);
        _submitDebtTransition(up.positionId, oldCommitment, newCommitment, asset, 0, amount, accruedInterest, transitionProof);

        _safeTransferFrom(asset, msg.sender, address(this), amount);

        uint256 principalRepaid = amount > accruedInterest ? amount - accruedInterest : 0;
        if (principalRepaid > 0) {
            totalBorrowed[asset] -= principalRepaid;
        }

        uint256 interestToStake = accruedInterest > amount ? amount : accruedInterest;
        if (interestToStake > 0 && zenStaking.totalStaked() > 0) {
            _safeTransfer(asset, address(zenStaking), interestToStake);
            zenStaking.notifyRewardAmount(asset, interestToStake);
        }

        emit Repaid(msg.sender, up.positionId, asset, amount);
    }

    /// @notice Called by LiquidationHandler once it has confirmed a position is
    /// stale. No transition proof is required here — by definition the position
    /// stopped proving anything, so LiquidationHandler supplies the resulting
    /// commitment directly. The staleness check is re-verified here too, so
    /// VaultManager never trusts LiquidationHandler blindly.
    function seizeAndRepay(
        uint256 positionId,
        address collateralAsset,
        uint256 collateralAmount,
        address debtAsset,
        uint256 debtRepaid,
        bytes32 newCommitment
    ) external onlyLiquidationHandler {
        require(registry.isStale(positionId), "VaultManager: not liquidatable");

        totalSupplied[collateralAsset] -= collateralAmount;
        totalBorrowed[debtAsset] -= debtRepaid;
        registry.updateCommitment(positionId, newCommitment);

        // Frees this wallet to open a brand-new position (fresh salt, no
        // connection to the closed one) on its next deposit, instead of being
        // permanently stuck: the position's sealed commitment is now
        // `newCommitment` (a plain closed-marker hash, not a genuine Poseidon
        // commitment of any real state), so no transition proof could ever be
        // built from it again — a liquidated wallet with `active` left true
        // would be locked out of this vault forever. A real lending protocol
        // cannot ban a liquidated user from ever borrowing again; that's the
        // whole reason this reset exists, not a cosmetic cleanup.
        address closedOwner = positionOwner[positionId];
        positionOf[closedOwner].active = false;

        _safeTransfer(collateralAsset, liquidationHandler, collateralAmount);

        emit Seized(positionId, collateralAsset, collateralAmount, debtAsset, debtRepaid);
        emit PositionClosed(positionId, closedOwner);
    }
}
