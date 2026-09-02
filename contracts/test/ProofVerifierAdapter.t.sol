// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {ProofVerifierAdapter} from "../src/ProofVerifierAdapter.sol";
import {Groth16Verifier} from "../src/HealthFactorVerifier.sol";
import {PriceOracle} from "../src/PriceOracle.sol";

/// @notice Tests the real Circuit A integration with a genuine Groth16 proof,
/// not a mock. Fixture values below are the actual output of:
///   circuits/build: node health_factor_js/generate_witness.js ... input_healthy.json
///   snarkjs groth16 prove health_factor_final.zkey witness.wtns proof.json public.json
///   snarkjs zkey export soliditycalldata public.json proof.json
/// for a position holding 5 WETH collateral / 1000 USDC debt at
/// price = [$2473.76, $1.00, $5.00] and liqThreshold = [0.83, 0.90, 0.65]
/// (all 1e6-scaled) — a genuinely solvent position, per the real formula the
/// circuit enforces.
contract ProofVerifierAdapterTest is Test {
    PositionRegistry registry;
    ProofVerifierAdapter adapter;
    Groth16Verifier verifier;
    PriceOracle oracle;

    bytes32 constant COMMITMENT = 0x089dd6d3a09114927baa1ea89c313ceeb8db52d81e7e6075d0a12b8edc409e4e;
    uint256 positionId;

    // Real proof for the healthy fixture above — values below are the exact,
    // programmatically-extracted output of
    // `snarkjs zkey export soliditycalldata public.json proof.json`, not
    // hand-transcribed (an earlier hand-copy of these dropped a trailing hex
    // digit off every single value, which produced "invalid proof" for a
    // proof that is, in fact, genuinely valid — this fixture regeneration is
    // what caught that). Regenerated again for gap #4: this circuit's trusted
    // setup is now anchored to the real, public, multi-party Hermez Perpetual
    // Powers of Tau ceremony instead of a single-party one — a Groth16 proof
    // is bound to the specific setup it was proven under, so every old proof
    // stopped verifying the moment the setup changed, unrelated to whether
    // health_factor.circom's own source changed (it didn't).
    uint256[2] pA = [
        0x0ef028eac32599fbf22d983fd771d3b73e1a61c98c5bd42f650266f7bbcd794a,
        0x22c3678e3d6cc90959be14b50755722ed59237ba1400068844523a066f3b4961
    ];
    uint256[2][2] pB = [
        [
            0x02d3a310347072613ff468f032f9ea1357db0700e24efc4033368c6f9deef6ba,
            0x105bf45abe386c35eb8489695d16ca6d5b5ca698d3b3e2ebfc2822eafccd080a
        ],
        [
            0x0e5be02937745fbacff584a6714643815483ac2315868edc82838823a97cce5c,
            0x25182f594236efcf92c6ad9ad33d693a86b7b95016b2b4e94ac8f062fd7363c5
        ]
    ];
    uint256[2] pC = [
        0x241c9cc8fafba62177066cdbd26c3dd0160f386b3bebf2a46d12887992562553,
        0x052a4fa5f75ac06fd369780f5eded32d049d03933205b9ae3f8d1dac31c92a9b
    ];
    uint256[3] price = [2473760000, 1000000, 5000000];
    uint256[3] liqThreshold = [830000, 900000, 650000];
    uint256 commitmentField = 3897380457012946661588706298891070113539283798511502099189739910203302780494;

    function setUp() public {
        verifier = new Groth16Verifier();
        // Seeded with the exact price/liqThreshold the fixture proof below
        // was actually generated for — the proof cryptographically binds to
        // these as public inputs, so the oracle must report the same values
        // or a genuinely valid proof would be (correctly) rejected.
        oracle = new PriceOracle(price, liqThreshold);

        address predictedAdapter = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        registry = new PositionRegistry(address(this), predictedAdapter);
        adapter = new ProofVerifierAdapter(address(registry), address(verifier), address(oracle));
        require(address(adapter) == predictedAdapter, "address prediction drifted");

        vm.prank(address(this));
        positionId = registry.openPosition(COMMITMENT);
    }

    function test_recordProof_acceptsRealValidProof() public {
        uint64 before = uint64(block.timestamp);
        vm.warp(before + 1000);

        adapter.recordProof(positionId, pA, pB, pC, commitmentField);

        (, uint64 lastProof,) = registry.positions(positionId);
        assertEq(lastProof, uint64(block.timestamp));
    }

    function test_recordProof_revertsOnCommitmentMismatch() public {
        vm.prank(address(this));
        uint256 otherPosition = registry.openPosition(bytes32(uint256(0xdead)));

        vm.expectRevert("ProofVerifierAdapter: commitment mismatch");
        adapter.recordProof(otherPosition, pA, pB, pC, commitmentField);
    }

    function test_recordProof_revertsWhenOraclePriceDiffersFromWhatTheProofWasGeneratedFor() public {
        // Same proof, but the oracle now reports a different price than what
        // it actually was when the proof was generated — the proof
        // cryptographically binds to the exact public inputs, so this must
        // be rejected by the verifier itself, not just by the earlier
        // commitment check (commitment is unchanged and still matches the
        // registered position). This is exactly the scenario the oracle
        // fix closes: nobody, including the oracle owner after an update,
        // can make a stale proof pass for a new price.
        vm.prank(address(this));
        uint256[3] memory tamperedPrice = [uint256(999999999), 1000000, 5000000];
        oracle.setPrices(tamperedPrice);

        vm.expectRevert("ProofVerifierAdapter: invalid proof");
        adapter.recordProof(positionId, pA, pB, pC, commitmentField);
    }

    function test_recordProof_revertsWhenOraclePriceIsStale() public {
        // New finding, closed alongside gaps #1-#4: nothing previously
        // stopped the oracle from simply going quiet — every proof would
        // keep validating against an arbitrarily old price forever, with no
        // on-chain signal anything was wrong, even with a fully honest owner
        // who just forgot to refresh it.
        vm.warp(block.timestamp + oracle.MAX_STALENESS() + 1);

        vm.expectRevert("PriceOracle: price too stale");
        adapter.recordProof(positionId, pA, pB, pC, commitmentField);
    }

    function test_recordProof_revertsOnGarbageProof() public {
        uint256[2] memory badA = [uint256(1), 2];
        uint256[2][2] memory badB = [[uint256(1), 2], [uint256(3), 4]];
        uint256[2] memory badC = [uint256(1), 2];

        vm.expectRevert();
        adapter.recordProof(positionId, badA, badB, badC, commitmentField);
    }
}
