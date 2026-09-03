// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProofVerifier} from "../../src/interfaces/IProofVerifier.sol";
import {PositionRegistry} from "../../src/PositionRegistry.sol";

/// @notice Test-only stand-in for the real zkVerify-backed verifier (Phase 5).
/// Defaults to accepting every proof; flip `shouldVerify` to false to exercise
/// the rejection path without needing a real circuit.
contract MockProofVerifier is IProofVerifier {
    bool public shouldVerify = true;

    // Records the checkpointIndex/currentIndex of the most recent
    // verifyTransition call — lets a test assert on what VaultManager
    // actually passed through without needing a real circuit. A real
    // Groth16 verifier can't be spied on like this; a mock that only
    // returns true/false can't have caught the real bug this exists to
    // regression-test (VaultManager passing a genuine 0 for a
    // never-borrowed asset, which the real circuit's floor-division check
    // rejects but this mock would have happily accepted either way).
    uint256 public lastCheckpointIndex;
    uint256 public lastCurrentIndex;

    function setShouldVerify(bool value) external {
        shouldVerify = value;
    }

    /// @notice Stands in for what a real health-factor proof submission does:
    /// verify, then refresh the position's liveness clock. Anyone can call this
    /// (matching the mock's "everything verifies" stance) — the real Phase 5
    /// version gates this behind an actual zkVerify-checked proof.
    function recordProof(address registry, uint256 positionId) external {
        PositionRegistry(registry).recordProof(positionId);
    }

    function verifyTransition(
        uint256,
        bytes32,
        bytes32,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256 checkpointIndex,
        uint256 currentIndex,
        bytes calldata
    ) external override returns (bool) {
        lastCheckpointIndex = checkpointIndex;
        lastCurrentIndex = currentIndex;
        return shouldVerify;
    }

    function verifyReveal(uint256, bytes32, uint256, uint256, uint256, uint256, bytes calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}
