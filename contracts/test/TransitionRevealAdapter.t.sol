// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TransitionRevealAdapter} from "../src/TransitionRevealAdapter.sol";
import {Groth16Verifier as TransitionGroth16Verifier} from "../src/TransitionVerifier.sol";
import {Groth16Verifier as RevealGroth16Verifier} from "../src/RevealVerifier.sol";

/// @notice Tests the real Circuit T / Circuit R integration with genuine Groth16
/// proofs, not mocks. Fixture values are the exact, programmatically extracted
/// output of circuits/build/regenerate_all_fixtures.js — witness generation,
/// proving, and `snarkjs zkey export soliditycalldata`, never hand-transcribed
/// (an earlier hand-copy on a different fixture silently dropped a trailing
/// hex digit off every value and made a genuinely valid proof look invalid).
///
/// Regenerated for two reasons at once: gap #3 changed transition.circom's
/// own public inputs (principalIncrease/interestAccrued split apart, plus
/// checkpointIndex/currentIndex added, to cryptographically enforce accrued
/// interest instead of trusting a self-reported number), and gap #4 anchored
/// every circuit's trusted setup to the real, public, multi-party Hermez
/// Perpetual Powers of Tau ceremony instead of a single-party one — the
/// latter alone would have invalidated every old proof even for reveal.circom,
/// whose own source didn't change, since a Groth16 proof is bound to the
/// specific setup it was proven under.
///
/// Deposit fixture: second deposit, 5 WETH -> 7 WETH collateral (asset index
/// 0), no debt, salt 12345, checkpointIndex == currentIndex == 1e18 (no
/// interest claimed, so the constraint collapses to interestAccrued === 0
/// regardless of debt). Repay+interest fixture: 5 WETH collateral / 1000 USDC
/// debt -> 950 USDC (asset index 1) via debtDecrease=100 USDC (real
/// repayment) and interestAccrued=50 USDC, checkpointIndex=1e18,
/// currentIndex=1.05e18 (a 5% index move — 1000 USDC * 5% = 50 USDC,
/// exactly the interest claimed). Reveal fixture: 5 WETH collateral (index 0)
/// / 1000 USDC debt (index 1), salt 12345 — the same position numbers
/// Circuit A's own fixture uses.
///
/// The circuits work in "token units * 1e6" (matching the Poseidon commitment
/// scheme), but every amount value this adapter actually receives from
/// VaultManager is raw 18-decimal wei — so every amount below is written as
/// the circuit-scale fixture value times CIRCUIT_UNIT (1e12), exercising the
/// adapter's real wei -> circuit-unit conversion rather than bypassing it.
/// checkpointIndex/currentIndex are the one exception: they're WAD-scaled
/// (1e18) borrowIndex ratios, not token amounts, and the adapter passes them
/// through unconverted (see TransitionRevealAdapter.sol's own comment).
contract TransitionRevealAdapterTest is Test {
    uint256 constant CIRCUIT_UNIT = 1e12;

    TransitionRevealAdapter adapter;

    bytes32 constant OLD_COMMITMENT = 0x2b1515145cdbdbb66c0dcc73b06c473f6d414d969e1c57c4929b6b4e42b69027;
    bytes32 constant NEW_COMMITMENT = 0x0e5da363ce542f802dd3e28ff91b2ff091c0da3f63569f45aab3734d5c98d85b;
    bytes32 constant REPAY_OLD_COMMITMENT = 0x089dd6d3a09114927baa1ea89c313ceeb8db52d81e7e6075d0a12b8edc409e4e;
    bytes32 constant REPAY_NEW_COMMITMENT = 0x04d1cca685bd6a7509c52c3dff4b869fc20af4f4d278147d81922eb25b33e627;
    bytes32 constant REVEAL_COMMITMENT = 0x089dd6d3a09114927baa1ea89c313ceeb8db52d81e7e6075d0a12b8edc409e4e;

    uint256 constant CHECKPOINT_INDEX = 1_000_000_000_000_000_000; // 1e18 WAD
    uint256 constant CURRENT_INDEX_NO_INTEREST = 1_000_000_000_000_000_000; // equal, no interest claimed
    uint256 constant CURRENT_INDEX_WITH_5PCT = 1_050_000_000_000_000_000; // 1.05e18

    uint256[2] transitionPA = [
        0x2447305d42048fc949e034623ece7b3cfc63a2050ff7eefbefcdffc484aaf7e4,
        0x0130f8768892f5c900a13f1654d4a0abbbea19ec0f96325f84310b3b8d4d32e9
    ];
    uint256[2][2] transitionPB = [
        [
            0x137a394ca0f41aee93e7008f26e8ac36961471da41ffd7f45a6a05afa9f80c09,
            0x1c9209a5e749eb69fe5d077bf41ef8bca6acad99c1f15a8a774b07aa03dca5cd
        ],
        [
            0x1d0c9e542a327a22934d55b625a5f4d50fa42ab0724aee4ff45afaecf51aac55,
            0x02403d34d282d1681808266ee1ee5724315c8e9e53e58f66f3477b1484823e5b
        ]
    ];
    uint256[2] transitionPC = [
        0x0af029c56e043b5dcdf60a53561202b6313175de259c4e35104b44b3d494117b,
        0x0036604ef7fb19ff9c85611ceff9d02748b7d8f4912eeb193f3a915f904cc911
    ];

    uint256[2] repayPA = [
        0x15740687bc778f6d778ac13c5ff1446d95d42803ec480c1c86604177f2f919f6,
        0x041dcd67b2ae5b69439e57d78dae590e32c5a3fd9e79633df7bf726ade44f9d9
    ];
    uint256[2][2] repayPB = [
        [
            0x052073e30b36c206a9248513c9d81e1593a5cf0c71bbb8a4f33a01e2a34af4e1,
            0x183188b05d844b8a57a4c4c53acf7425bc083d7383c7d8479cf7b50d52619f46
        ],
        [
            0x0985277b5fc9ab99db21018cba477ebe1dfbb9b42edab45ea22d95e2e209a1ba,
            0x2dec1e17cbd89f6f2119c6a688fe286289e2ffd017fe29b68b9fa7690475e974
        ]
    ];
    uint256[2] repayPC = [
        0x1189fae6db91cf9f561b2ab0857de2164ed4205534d436a3cc5b43671cebaaff,
        0x12b3bce465e6bbee5325e6da67fe401b0ca41e8338c650e91193cbf520995450
    ];

    uint256[2] revealPA = [
        0x2cedd8f275fc0742f45ae38fb3aed2802d6cfcd800a64fd1d7e41d1b8fa47d18,
        0x0fbf748974ac18b06aae3508daf33234bc9e61b1feb7f4ccec2aa914809ac0e0
    ];
    uint256[2][2] revealPB = [
        [
            0x05453f8c5659ad7a21268fb86e333964abed5ba79ea9c0cf597726b4e4e4f5ad,
            0x290e7430cf555f92b917bcbc67c2109f78c29180e51dffe73cd26fa3d9c8ce07
        ],
        [
            0x1bf7d3d0b34dc5aa29146194acaee51909a52ccb677032c95a663dd129868e9e,
            0x094585b49fc77e9cda6a1ccfb4620ba6a1835fbb380e3eb332c6804bc32ad1a1
        ]
    ];
    uint256[2] revealPC = [
        0x213007dca3dd2274ea00d93ea1035d65e22c5448120c3f75cc93a2a97938b32b,
        0x1a8f21b82b747b316b11542b9d795def1e73d83f76a73d548d1419be1b91aab8
    ];

    function setUp() public {
        TransitionGroth16Verifier tv = new TransitionGroth16Verifier();
        RevealGroth16Verifier rv = new RevealGroth16Verifier();
        adapter = new TransitionRevealAdapter(address(tv), address(rv));
    }

    function _transitionProof() internal view returns (bytes memory) {
        return abi.encode(transitionPA, transitionPB, transitionPC);
    }

    function _repayProof() internal view returns (bytes memory) {
        return abi.encode(repayPA, repayPB, repayPC);
    }

    function _revealProof() internal view returns (bytes memory) {
        return abi.encode(revealPA, revealPB, revealPC);
    }

    function test_verifyTransition_acceptsRealValidProof() public {
        bool ok = adapter.verifyTransition(
            0,
            OLD_COMMITMENT,
            NEW_COMMITMENT,
            0,
            2_000_000 * CIRCUIT_UNIT,
            0,
            0,
            0,
            0,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_NO_INTEREST,
            _transitionProof()
        );
        assertTrue(ok);
    }

    function test_verifyTransition_rejectsWrongAssetIndex() public {
        // Same proof, same commitments and delta — but claiming the deposit
        // touched asset index 1 (USDC) instead of the 0 (WETH) it was actually
        // proven for. The proof cryptographically binds to assetIndex, so this
        // must fail even though every other public input is unchanged.
        bool ok = adapter.verifyTransition(
            0,
            OLD_COMMITMENT,
            NEW_COMMITMENT,
            1,
            2_000_000 * CIRCUIT_UNIT,
            0,
            0,
            0,
            0,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_NO_INTEREST,
            _transitionProof()
        );
        assertFalse(ok);
    }

    function test_verifyTransition_rejectsWrongDelta() public {
        bool ok = adapter.verifyTransition(
            0,
            OLD_COMMITMENT,
            NEW_COMMITMENT,
            0,
            3_000_000 * CIRCUIT_UNIT,
            0,
            0,
            0,
            0,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_NO_INTEREST,
            _transitionProof()
        );
        assertFalse(ok);
    }

    function test_verifyTransition_revertsOnSubCircuitPrecisionAmount() public {
        // Not a whole multiple of 1e12 wei — cannot be represented at the
        // circuit's 1e6 fixed-point precision, so this must revert rather than
        // silently floor (see the contract's top-level comment for why
        // flooring here would be a real dust-leak, not just an inconvenience).
        vm.expectRevert("TransitionRevealAdapter: sub-circuit-precision amount");
        adapter.verifyTransition(
            0,
            OLD_COMMITMENT,
            NEW_COMMITMENT,
            0,
            2_000_000 * CIRCUIT_UNIT + 1,
            0,
            0,
            0,
            0,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_NO_INTEREST,
            _transitionProof()
        );
    }

    function test_verifyTransition_acceptsRealAccruedInterestAlongsideRepayment() public {
        // gap #3's actual fix, exercised end to end: debtDecrease (100 USDC
        // repayment) and interestAccrued (50 USDC) both nonzero in the same
        // proof, with interestAccrued cryptographically tied to the position's
        // own old debt (1000 USDC, private) and the checkpoint/current index
        // ratio (1e18 -> 1.05e18, a public 5% move) — 1000 * 5% = 50, exactly
        // what's claimed. Before this fix, interestAccrued was an arbitrary
        // self-reported number nothing checked.
        bool ok = adapter.verifyTransition(
            0,
            REPAY_OLD_COMMITMENT,
            REPAY_NEW_COMMITMENT,
            1,
            0,
            0,
            0,
            100_000_000 * CIRCUIT_UNIT,
            50_000_000 * CIRCUIT_UNIT,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_WITH_5PCT,
            _repayProof()
        );
        assertTrue(ok);
    }

    function test_verifyTransition_rejectsFabricatedInterestAmount() public {
        // Same proof, same real index move — but claiming MORE interest than
        // the index ratio actually justifies (60 USDC instead of the real 50).
        // This is exactly the exploit gap #3 closed: before it, a caller could
        // simply claim whatever interestAccrued they liked.
        bool ok = adapter.verifyTransition(
            0,
            REPAY_OLD_COMMITMENT,
            REPAY_NEW_COMMITMENT,
            1,
            0,
            0,
            0,
            100_000_000 * CIRCUIT_UNIT,
            60_000_000 * CIRCUIT_UNIT,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_WITH_5PCT,
            _repayProof()
        );
        assertFalse(ok);
    }

    function test_verifyTransition_rejectsInterestClaimedAgainstAStaleIndex() public {
        // Same proof, but claiming NO index movement happened (checkpoint ==
        // current) while still claiming 50 USDC of interest — the constraint
        // forces interestAccrued to 0 whenever the index hasn't moved,
        // regardless of what the caller wants to claim.
        bool ok = adapter.verifyTransition(
            0,
            REPAY_OLD_COMMITMENT,
            REPAY_NEW_COMMITMENT,
            1,
            0,
            0,
            0,
            100_000_000 * CIRCUIT_UNIT,
            50_000_000 * CIRCUIT_UNIT,
            CHECKPOINT_INDEX,
            CHECKPOINT_INDEX,
            _repayProof()
        );
        assertFalse(ok);
    }

    function test_verifyReveal_acceptsRealValidProof() public {
        bool ok = adapter.verifyReveal(
            0, REVEAL_COMMITMENT, 0, 5_000_000 * CIRCUIT_UNIT, 1, 1_000_000_000 * CIRCUIT_UNIT, _revealProof()
        );
        assertTrue(ok);
    }

    function test_verifyReveal_rejectsTamperedAmount() public {
        bool ok = adapter.verifyReveal(
            0, REVEAL_COMMITMENT, 0, 4_999_999 * CIRCUIT_UNIT, 1, 1_000_000_000 * CIRCUIT_UNIT, _revealProof()
        );
        assertFalse(ok);
    }

    function test_verifyReveal_rejectsWrongDebtAssetIndex() public {
        bool ok = adapter.verifyReveal(
            0, REVEAL_COMMITMENT, 0, 5_000_000 * CIRCUIT_UNIT, 2, 1_000_000_000 * CIRCUIT_UNIT, _revealProof()
        );
        assertFalse(ok);
    }

    function test_verifyReveal_revertsOnSubCircuitPrecisionAmount() public {
        vm.expectRevert("TransitionRevealAdapter: sub-circuit-precision amount");
        adapter.verifyReveal(
            0, REVEAL_COMMITMENT, 0, 5_000_000 * CIRCUIT_UNIT + 1, 1, 1_000_000_000 * CIRCUIT_UNIT, _revealProof()
        );
    }
}
