// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal N-of-M multi-signature wallet, purpose-built to replace a
/// single trusted EOA as PriceOracle's owner (gap #2) — not a general-purpose
/// treasury contract. Real Gnosis Safe infrastructure isn't deployed on
/// Horizen or Horizen Testnet (checked directly: neither the canonical proxy
/// factory nor the singleton factory has any code there), so this is a
/// small, self-contained alternative rather than importing and deploying an
/// entire unfamiliar contract suite for what is fundamentally gating two
/// admin functions.
///
/// Standard propose -> approve -> execute pattern: any owner proposes an
/// arbitrary call (target, value, calldata), owners approve it individually,
/// and once approvals reach `threshold`, anyone can trigger execution (the
/// authorization already happened via approvals — execution itself doesn't
/// need to be owner-gated, matching how real multi-sigs work).
///
/// Deliberately narrow: no owner add/remove, no threshold changes after
/// deployment. If the owner set needs to change, deploy a new instance and
/// call PriceOracle.setOwner() to point at it — adding that mutability here
/// would be scope creep for what this exists to do.
contract SimpleMultiSig {
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public immutable threshold;

    struct Transaction {
        address target;
        uint256 value;
        bytes data;
        bool executed;
        uint256 approvalCount;
    }

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approved;

    event TransactionProposed(uint256 indexed txId, address indexed proposer, address target, uint256 value, bytes data);
    event TransactionApproved(uint256 indexed txId, address indexed owner);
    event ApprovalRevoked(uint256 indexed txId, address indexed owner);
    event TransactionExecuted(uint256 indexed txId);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "SimpleMultiSig: not owner");
        _;
    }

    constructor(address[] memory _owners, uint256 _threshold) {
        require(_owners.length > 0, "SimpleMultiSig: no owners");
        require(_threshold > 0 && _threshold <= _owners.length, "SimpleMultiSig: bad threshold");
        for (uint256 i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            require(o != address(0), "SimpleMultiSig: zero owner");
            require(!isOwner[o], "SimpleMultiSig: duplicate owner");
            isOwner[o] = true;
            owners.push(o);
        }
        threshold = _threshold;
    }

    /// @notice Proposes a new call and immediately counts as the proposer's
    /// own approval — matching how a real multi-sig proposal implicitly
    /// signals the proposer's intent to approve it.
    function propose(address target, uint256 value, bytes calldata data) external onlyOwner returns (uint256 txId) {
        txId = transactions.length;
        transactions.push(Transaction({target: target, value: value, data: data, executed: false, approvalCount: 0}));
        emit TransactionProposed(txId, msg.sender, target, value, data);
        _approve(txId);
    }

    function approve(uint256 txId) external onlyOwner {
        require(txId < transactions.length, "SimpleMultiSig: no such tx");
        require(!transactions[txId].executed, "SimpleMultiSig: already executed");
        require(!approved[txId][msg.sender], "SimpleMultiSig: already approved");
        _approve(txId);
    }

    function _approve(uint256 txId) private {
        approved[txId][msg.sender] = true;
        transactions[txId].approvalCount += 1;
        emit TransactionApproved(txId, msg.sender);
    }

    function revokeApproval(uint256 txId) external onlyOwner {
        require(txId < transactions.length, "SimpleMultiSig: no such tx");
        require(!transactions[txId].executed, "SimpleMultiSig: already executed");
        require(approved[txId][msg.sender], "SimpleMultiSig: not approved");
        approved[txId][msg.sender] = false;
        transactions[txId].approvalCount -= 1;
        emit ApprovalRevoked(txId, msg.sender);
    }

    function execute(uint256 txId) external {
        require(txId < transactions.length, "SimpleMultiSig: no such tx");
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "SimpleMultiSig: already executed");
        require(txn.approvalCount >= threshold, "SimpleMultiSig: not enough approvals");
        txn.executed = true;
        (bool success,) = txn.target.call{value: txn.value}(txn.data);
        require(success, "SimpleMultiSig: execution failed");
        emit TransactionExecuted(txId);
    }

    function transactionCount() external view returns (uint256) {
        return transactions.length;
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    receive() external payable {}
}
