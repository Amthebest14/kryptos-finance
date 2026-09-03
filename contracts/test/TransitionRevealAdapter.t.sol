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
/// Circuit A's own fixture uses. Non-round-interest fixture: 5 WETH
/// collateral / 900 ZEN debt (asset index 2), the exact checkpointIndex/
/// currentIndex pair captured from a real failed repay live — see
/// transition.circom's own comment for why the old exact-equality interest
/// constraint rejected this and the new floor-division one accepts it.
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
    bytes32 constant NONROUND_OLD_COMMITMENT = 0x2b3ce38975a41f432093f650b6d611c09a81cde0e84b312b06a38ac77edfa610;
    bytes32 constant NONROUND_NEW_COMMITMENT = 0x0bc7f7e7097611977dd20a9405d418f3489ab06f29cd793c4b4e5b8f582e746c;

    uint256 constant CHECKPOINT_INDEX = 1_000_000_000_000_000_000; // 1e18 WAD
    uint256 constant CURRENT_INDEX_NO_INTEREST = 1_000_000_000_000_000_000; // equal, no interest claimed
    uint256 constant CURRENT_INDEX_WITH_5PCT = 1_050_000_000_000_000_000; // 1.05e18
    // The exact currentIndex captured live from a real failed repay — this is
    // the whole point of this fixture: 900e6 * 9886986254466 / 1e18 does NOT
    // divide evenly (floor = 8898, real nonzero remainder), unlike the clean
    // 5% fixture above. The old exact-equality constraint rejected this;
    // the floor-division fix accepts it.
    uint256 constant CURRENT_INDEX_NONROUND = 1_000_009_886_986_254_466;

    uint256[2] transitionPA = [
        0x17680bc551e7a3076620bf05631f9f0799279a6d5ef8fc5d47ba536553693578,
        0x20933bbb225882afc1cefc2e4721af5b8681e12188e4a42d4883bb9fa6bf5d8c
    ];
    uint256[2][2] transitionPB = [
        [
            0x12062038f1b0ef8b1badaa0fc449e9e04f0c08b74fb156e4e3fa0b6ebf684424,
            0x075d74ad7d685365acea30c65e2c16e4a8f5570c2cc32aabc0fa93dc0c536c62
        ],
        [
            0x25f56e22037b3c43b1423d7098bc31188af42e78565a85e27420abf4acff7d85,
            0x24969fa35a1c1181e40fb3525daedbb98824ef4dff0ffe0bb39b54de9ebc4f17
        ]
    ];
    uint256[2] transitionPC = [
        0x18379869de581178093c7f42d8c6b5af2cbc7029206aa73874e7a889af64b86d,
        0x2aef50809f63a5870cf74c63a652e9de41bfcbf5be66b57428bb21112a8d7716
    ];

    uint256[2] repayPA = [
        0x21d6f1da55d9b5a3b1d80cf3b7a8a478d3a07a7856b7915de8b9ceaf38583f78,
        0x0febec71d7fdd53a95005f6497f878481431c1ab6d4958029c8dabdc76fbf06f
    ];
    uint256[2][2] repayPB = [
        [
            0x197517e563eb15ccc2e4c629ba77ce0d65004fe7edc072f64888b02ddf9eb50c,
            0x1d23fb04030604f53ecbf4452a272ae15d36e122ca803c400954491bd388608e
        ],
        [
            0x26573ee9a4d3bbebb4bfceaa37735e4bbd9d7ec70288cba6a78e7a6c0df1d765,
            0x191b63264479b372d258329122ef26a14690f597e8cda809bcc7cf0fc51a284d
        ]
    ];
    uint256[2] repayPC = [
        0x0284c280fceca68de371ad4c07aa37ef7724cd2ae7b18dfbdc0086bcdc488d48,
        0x0b34f404b1ab535e20d839ee1a06db9271f4e7ec91edd93e9a2923d80d2292f2
    ];

    uint256[2] revealPA = [
        0x114fa2b2d5686e18fe424c0af406aeaa62222f3cc4020c04cc49a1d7aed6bad6,
        0x1ce3c3b3a7db24d594e433412db1312ffe5e40ad7d9b1b059d7cecde04266323
    ];
    uint256[2][2] revealPB = [
        [
            0x276949ee3cf6d0a12a7232b319c07f49a528a70dd34f311f25934a529fdb689f,
            0x2467f0f32bed23b92a78daa7cacda894bf21c96955a20d0a3966c83bd0be0825
        ],
        [
            0x0c2c54a3f315e94a17e94f0329d6e9d2d6b7e6275cfee2694f61c784636f9e13,
            0x0fd73c63e0f36788d22cb1127ade1a24f07f7b74054cc08998c50fc311fecce5
        ]
    ];
    uint256[2] revealPC = [
        0x227a2d2aacb4cd50cd15a896cac13f7ccdb35c724a7991018684429b8148ef6d,
        0x2e54e2c3756b2744d6abced4b0f9874181d0b82b1e339298deb426892eef91c6
    ];

    uint256[2] nonroundPA = [
        0x0493eafd434fbcb6a00c8f51b5fe7c40379d83599554358bc7f80e2867ad78d9,
        0x2a4c4656c61abb9a5f74ee5d1964dbf80488d98493e02bdfc853a8cddfb8d54f
    ];
    uint256[2][2] nonroundPB = [
        [
            0x09875a37205a1bd641694903658ec1252871969263fe415f94b3908d7381959a,
            0x06311404331264705fd2fb431d0c8d6550b485e27f2879a6cb5eb0ae6866d0cc
        ],
        [
            0x2241500d98c23940f5cf640640e4ddcdb094b287eb5bf9cf92f5ac15a8dde2c7,
            0x2893ff3553e01d4bce11ac51d6608cd05e0d10f3bc92379b135d946d4d388c0d
        ]
    ];
    uint256[2] nonroundPC = [
        0x27e5860cacd5477220deb543e331e9237a675c0e4862e110a97409a640c317f9,
        0x2777a1dd8723ef5f35de7cfd8e71c05c1f8ba9818132fa93222b4365b6ec56e5
    ];

    function setUp() public {
        TransitionGroth16Verifier tv = new TransitionGroth16Verifier();
        RevealGroth16Verifier rv = new RevealGroth16Verifier();
        adapter = new TransitionRevealAdapter(address(tv), address(rv));
    }

    function _transitionProof() internal view returns (bytes memory) {
        return abi.encode(transitionPA, transitionPB, transitionPC);
    }

    function _nonroundProof() internal view returns (bytes memory) {
        return abi.encode(nonroundPA, nonroundPB, nonroundPC);
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

    function test_verifyTransition_acceptsNonRoundAccruedInterest() public {
        // Regression test for a real bug found live, on a real repay: the
        // circuit used to demand interestAccrued divide out of
        // debt*indexDelta/checkpointIndex EXACTLY. The 5% fixture above
        // happens to divide out evenly (1000 * 5% = 50 exactly), which is
        // exactly why it never caught this — every prior test's numbers
        // happened to be clean. This fixture uses the real currentIndex
        // captured from the actual failed transaction, which does not divide
        // evenly (floor(900e6 * 9886986254466 / 1e18) = 8898, real nonzero
        // remainder) — the old constraint rejected this outright; the fix
        // (transition.circom's bounded-remainder floor-division check)
        // accepts it.
        bool ok = adapter.verifyTransition(
            0,
            NONROUND_OLD_COMMITMENT,
            NONROUND_NEW_COMMITMENT,
            2,
            0,
            0,
            0,
            500_000_000 * CIRCUIT_UNIT,
            8898 * CIRCUIT_UNIT,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_NONROUND,
            _nonroundProof()
        );
        assertTrue(ok);
    }

    function test_verifyTransition_rejectsFlooredInterestRoundedUp() public {
        // Same proof and same real index move as the non-round fixture above
        // — but claiming interestAccrued=8899 (rounded up) instead of the
        // true floor value 8898. The remainder for 8899 would be negative in
        // real terms, which the fix's Num2Bits(100) range check on the
        // remainder rejects (it wraps to a field element nowhere near
        // representable in 100 bits) — confirming the fix enforces floor
        // division precisely, not just "close enough."
        bool ok = adapter.verifyTransition(
            0,
            NONROUND_OLD_COMMITMENT,
            NONROUND_NEW_COMMITMENT,
            2,
            0,
            0,
            0,
            500_000_000 * CIRCUIT_UNIT,
            8899 * CIRCUIT_UNIT,
            CHECKPOINT_INDEX,
            CURRENT_INDEX_NONROUND,
            _nonroundProof()
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
