// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Holds sealed position commitments and the liveness timestamp that
/// drives liquidation — never a plaintext balance. Staleness is checkable by
/// anyone using only public timestamps; no secret ever has to be read to
/// know a position is at risk.
contract PositionRegistry {
    uint256 public constant PROOF_INTERVAL = 30 minutes;
    uint256 public constant GRACE_PERIOD = 15 minutes;

    struct Position {
        bytes32 commitment; // hash(collateral, debt, salt) — sealed, not readable on its own
        uint64 lastProofTimestamp;
        bool exists;
    }

    mapping(uint256 => Position) public positions;
    uint256 public nextPositionId = 1;

    address public immutable vaultManager;
    address public immutable proofVerifier;

    event PositionOpened(uint256 indexed positionId, bytes32 commitment);
    event CommitmentUpdated(uint256 indexed positionId, bytes32 newCommitment);
    event ProofRefreshed(uint256 indexed positionId, uint64 timestamp);

    modifier onlyVault() {
        require(msg.sender == vaultManager, "PositionRegistry: not vault");
        _;
    }

    modifier onlyVerifier() {
        require(msg.sender == proofVerifier, "PositionRegistry: not verifier");
        _;
    }

    modifier positionExists(uint256 positionId) {
        require(positions[positionId].exists, "PositionRegistry: no position");
        _;
    }

    constructor(address _vaultManager, address _proofVerifier) {
        vaultManager = _vaultManager;
        proofVerifier = _proofVerifier;
    }

    /// @notice Opens a new sealed position. Called by VaultManager on first deposit.
    function openPosition(bytes32 commitment) external onlyVault returns (uint256 positionId) {
        positionId = nextPositionId++;
        positions[positionId] =
            Position({commitment: commitment, lastProofTimestamp: uint64(block.timestamp), exists: true});
        emit PositionOpened(positionId, commitment);
    }

    /// @notice Called by VaultManager whenever collateral/debt changes, re-sealing the position.
    function updateCommitment(uint256 positionId, bytes32 newCommitment) external onlyVault positionExists(positionId) {
        positions[positionId].commitment = newCommitment;
        emit CommitmentUpdated(positionId, newCommitment);
    }

    /// @notice Called by the zkVerify adapter once a health-factor proof has been verified.
    function recordProof(uint256 positionId) external onlyVerifier positionExists(positionId) {
        positions[positionId].lastProofTimestamp = uint64(block.timestamp);
        emit ProofRefreshed(positionId, uint64(block.timestamp));
    }

    /// @notice True once a position has missed its check-in AND used up its grace window.
    /// Pure function of public timestamps — anyone can call this, no secrets involved.
    function isStale(uint256 positionId) public view positionExists(positionId) returns (bool) {
        return block.timestamp > positions[positionId].lastProofTimestamp + PROOF_INTERVAL + GRACE_PERIOD;
    }

    /// @notice True during the window after a missed check-in but before the position goes stale.
    function isInGracePeriod(uint256 positionId) public view positionExists(positionId) returns (bool) {
        uint256 dueAt = positions[positionId].lastProofTimestamp + PROOF_INTERVAL;
        return block.timestamp > dueAt && block.timestamp <= dueAt + GRACE_PERIOD;
    }

    /// @notice Seconds of grace remaining before the position goes stale. 0 once expired.
    function graceRemaining(uint256 positionId) external view positionExists(positionId) returns (uint256) {
        uint256 dueAt = positions[positionId].lastProofTimestamp + PROOF_INTERVAL;
        uint256 graceEnd = dueAt + GRACE_PERIOD;
        if (block.timestamp >= graceEnd) return 0;
        if (block.timestamp <= dueAt) return GRACE_PERIOD;
        return graceEnd - block.timestamp;
    }
}
