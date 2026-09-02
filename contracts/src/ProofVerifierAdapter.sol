// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PositionRegistry} from "./PositionRegistry.sol";
import {Groth16Verifier} from "./HealthFactorVerifier.sol";
import {PriceOracle} from "./PriceOracle.sol";

/// @notice The real Phase 5 zkVerify-style adapter Phase 3's MockProofVerifier
/// was always a documented stand-in for. Verifies an actual Circuit A proof
/// (circuits/src/health_factor.circom) — a position's health-factor proof —
/// and only then records a liveness check-in. A "Refresh proof" call that
/// reaches this contract with an invalid or mismatched proof reverts; there
/// is no path to mark a position fresh without a genuine proof.
///
/// `price`/`liqThreshold` used to be caller-supplied calldata here — a real,
/// exploitable gap, since nothing checked them against reality: any caller
/// bypassing the honest frontend could submit a proof valid for fabricated,
/// favorable prices and stay "proven healthy" forever. Both now come from
/// PriceOracle instead, so every position proves against the same real,
/// on-chain number — see PriceOracle.sol for why that's a lighter fix than a
/// live oracle read, and what it does and doesn't close.
contract ProofVerifierAdapter {
    PositionRegistry public immutable registry;
    Groth16Verifier public immutable verifier;
    PriceOracle public immutable oracle;

    event HealthProofVerified(uint256 indexed positionId, bytes32 commitment);

    constructor(address _registry, address _verifier, address _oracle) {
        registry = PositionRegistry(_registry);
        verifier = Groth16Verifier(_verifier);
        oracle = PriceOracle(_oracle);
    }

    /// @notice Assembles the exact public-signal array the verifier expects,
    /// in the exact order `component main {public [...]}` declared them:
    /// price[0..2], liqThreshold[0..2], commitment — price and liqThreshold
    /// read live from `oracle`, not supplied by the caller.
    function recordProof(
        uint256 positionId,
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256 commitment
    ) external {
        (bytes32 currentCommitment,,) = registry.positions(positionId);
        require(bytes32(commitment) == currentCommitment, "ProofVerifierAdapter: commitment mismatch");

        uint256[3] memory price = oracle.getPrices();
        uint256[3] memory liqThreshold = oracle.getLiqThresholds();
        uint256[7] memory pubSignals =
            [price[0], price[1], price[2], liqThreshold[0], liqThreshold[1], liqThreshold[2], commitment];
        require(verifier.verifyProof(pA, pB, pC, pubSignals), "ProofVerifierAdapter: invalid proof");

        registry.recordProof(positionId);
        emit HealthProofVerified(positionId, bytes32(commitment));
    }
}
