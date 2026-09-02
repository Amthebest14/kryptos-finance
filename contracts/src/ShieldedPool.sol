// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";
import {IPoseidonT3} from "./interfaces/IPoseidonT3.sol";
import {Groth16Verifier as ShieldedSpendVerifier} from "./ShieldedSpendVerifier.sol";

/// @notice Proof-of-concept for gap #2 — event-log balance reconstruction.
/// VaultManager's deposit/withdraw events
/// tie an exact public amount to a specific position/wallet, so anyone
/// replaying full transaction history can reconstruct a position's exact
/// running balance. Fixing that for real needs a fundamentally different
/// transfer mechanism — this contract, not a patch to VaultManager.
///
/// Deliberately, explicitly scoped as a standalone demonstration, not a
/// finished feature: this proves the core shielded-pool mechanism works —
/// depositing an arbitrary amount into a POOLED (not per-position) set of
/// notes, and later spending a note by proving membership without revealing
/// which note, for an arbitrary withdrawal amount. It is NOT wired into
/// VaultManager, borrow/repay, interest accrual, or liquidation. Doing that
/// is real, separate future work: every one of those flows currently assumes
/// "one mutable position with a running balance," and would need rebuilding
/// around "spend a note, create new notes" instead — a different data model,
/// not an incremental change.
///
/// What this genuinely fixes, and what it doesn't:
///   - A deposit's amount is still visible in that transaction (a real ERC20
///     transfer has to be) — same as VaultManager. What's different is that
///     the deposit only proves "a note commitment for some amount was added
///     to the shared pool," not "this specific position now has this exact
///     running balance." The link from a deposit to a later withdrawal is
///     what's hidden, via the Merkle-membership + nullifier design below.
///   - How much that link is actually hidden in practice depends on how many
///     other deposits/withdrawals share the pool at the same time (the
///     "anonymity set") — on a young testnet with few users, that's small
///     regardless of how correct the cryptography is. Documented honestly,
///     not overclaimed.
///
/// Merkle tree: a standard incremental append-only tree (the same pattern
/// Tornado Cash and Semaphore use), fixed at TREE_DEPTH = 8 (256 notes) —
/// enough to demonstrate the mechanism, far too small for real capacity.
/// Every historical root is remembered forever (via `knownRoot`, never
/// pruned) rather than a bounded ring buffer: a withdrawal proof generated
/// against an older root is just as valid as one against the latest root
/// (the tree only grows), so there is no correctness reason to forget one —
/// only a POC-acceptable unbounded-storage tradeoff.
contract ShieldedPool {
    uint256 public constant TREE_DEPTH = 8;

    IERC20 public immutable token;
    IPoseidonT3 public immutable poseidonT3;
    ShieldedSpendVerifier public immutable verifier;

    mapping(uint256 => uint256) public filledSubtrees;
    uint256[TREE_DEPTH] public zeros;
    uint256 public nextLeafIndex;

    mapping(uint256 => bool) public knownRoot;
    mapping(uint256 => bool) public nullifierUsed;

    event NoteDeposited(uint256 indexed leafIndex, uint256 commitment, uint256 amount, uint256 root);
    event NoteSpent(uint256 nullifier, address indexed recipient, uint256 amount, uint256 newLeafIndex, uint256 root);

    constructor(address _token, address _poseidonT3, address _verifier) {
        token = IERC20(_token);
        poseidonT3 = IPoseidonT3(_poseidonT3);
        verifier = ShieldedSpendVerifier(_verifier);

        // zeros[0] is the "empty leaf" sentinel — plain 0 rather than a
        // "nothing up my sleeve" hash constant (real deployments typically
        // use one to pre-empt any suspicion a backdoored value was chosen;
        // not needed for a documented testnet POC). A genuine note
        // commitment is Poseidon([amount, secret, 0]) and would only equal
        // 0 by an astronomically unlikely hash collision.
        uint256 z = 0;
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            zeros[i] = z;
            z = poseidonT3.poseidon([z, z]);
        }
        knownRoot[z] = true;
    }

    /// @notice Opens a new note for `amount`, sealed under `commitment`
    /// (computed off-chain as Poseidon([amount, secret, 0]) for a secret only
    /// the depositor knows). `amount` is real, moved via a real transferFrom
    /// — visible in this transaction, same tradeoff VaultManager already
    /// documents. What's new is that this note now sits in a shared pool
    /// indistinguishable from every other depositor's note of any amount.
    function deposit(uint256 commitment, uint256 amount) external {
        require(amount > 0, "ShieldedPool: zero amount");
        require(commitment != 0, "ShieldedPool: zero commitment");
        require(token.transferFrom(msg.sender, address(this), amount), "ShieldedPool: transfer failed");

        (uint256 leafIndex, uint256 root) = _insert(commitment);
        emit NoteDeposited(leafIndex, commitment, amount, root);
    }

    /// @notice Spends one note: proves knowledge of a genuine note in the
    /// tree at `root` without revealing which one, publishes its unique
    /// `nullifier` (rejecting any second attempt to spend the same note),
    /// withdraws `withdrawAmount` to `recipient`, and seals the remainder
    /// into a fresh `newCommitment` note. `recipient` is bound into the
    /// proof's own public inputs (see shielded_spend.circom) — a proof
    /// resubmitted with a different recipient is cryptographically a
    /// different, invalid proof, not merely a policy check here.
    function withdraw(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256 root,
        uint256 nullifier,
        uint256 withdrawAmount,
        uint256 newCommitment,
        address recipient
    ) external {
        require(knownRoot[root], "ShieldedPool: unknown root");
        require(!nullifierUsed[nullifier], "ShieldedPool: note already spent");

        uint256[5] memory pubSignals =
            [root, nullifier, withdrawAmount, newCommitment, uint256(uint160(recipient))];
        require(verifier.verifyProof(pA, pB, pC, pubSignals), "ShieldedPool: invalid proof");

        nullifierUsed[nullifier] = true;
        (uint256 leafIndex, uint256 newRoot) = _insert(newCommitment);

        require(token.transfer(recipient, withdrawAmount), "ShieldedPool: transfer failed");
        emit NoteSpent(nullifier, recipient, withdrawAmount, leafIndex, newRoot);
    }

    function _insert(uint256 leaf) private returns (uint256 index, uint256 root) {
        index = nextLeafIndex;
        require(index < (1 << TREE_DEPTH), "ShieldedPool: tree full");

        uint256 currentHash = leaf;
        uint256 currentIndex = index;
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                filledSubtrees[i] = currentHash;
                currentHash = poseidonT3.poseidon([currentHash, zeros[i]]);
            } else {
                currentHash = poseidonT3.poseidon([filledSubtrees[i], currentHash]);
            }
            currentIndex /= 2;
        }

        nextLeafIndex = index + 1;
        root = currentHash;
        knownRoot[root] = true;
    }
}
