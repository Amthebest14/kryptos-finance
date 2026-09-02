// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ShieldedPool} from "../src/ShieldedPool.sol";
import {Groth16Verifier as ShieldedSpendVerifier} from "../src/ShieldedSpendVerifier.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Tests the gap #2 shielded-pool proof-of-concept end to end with a
/// genuine Groth16 proof, not a mock — same discipline as every other
/// circuit in this repo. Fixture values are the exact, programmatically
/// extracted output of circuits/build/make_shielded_spend_fixture.js
/// (witness generation -> proving -> `snarkjs zkey export soliditycalldata`),
/// never hand-transcribed.
///
/// The fixture computes a single-leaf tree (leaf index 0, TREE_DEPTH 8): a
/// note of amount 3,000,000 is deposited, then partially spent — 1,000,000
/// withdrawn to address(0xBEEF) (bound into the proof's own public inputs),
/// 2,000,000 sealed into a fresh change note. Because it's the very first
/// leaf in an otherwise-empty tree, its Merkle path is exactly `zeros[0..7]`
/// at every level — this test's `deposit()` call must therefore produce
/// on-chain a root that matches the fixture's `root` exactly, which is
/// itself a real end-to-end check that the on-chain incremental tree
/// (Solidity + the generated PoseidonT3 contract) computes hashes
/// identically to the off-chain circomlibjs computation the circuit's
/// witness was built from.
contract ShieldedPoolTest is Test {
    ShieldedPool pool;
    MockERC20 token;

    uint256 constant COMMITMENT = 21634620244865894608558883133246927962978109710360175162153465983643133708588;
    uint256 constant ROOT = 12045574520454418293720399885402206626346778588266355121566647611892303696537;
    uint256 constant NULLIFIER = 11397744923490416216884412692685806505980614390096677404559975880232658932054;
    uint256 constant NEW_COMMITMENT = 5031833341825913018345545494205071861512799619802524481568040565093730559049;
    uint256 constant AMOUNT = 3_000_000;
    uint256 constant WITHDRAW_AMOUNT = 1_000_000;
    address constant RECIPIENT = address(0xBEEF);

    // Regenerated for gap #4: this circuit's trusted setup is now anchored to
    // the real, public, multi-party Hermez Perpetual Powers of Tau ceremony
    // instead of a single-party one — shielded_spend.circom's own source
    // didn't change, but a Groth16 proof is bound to the specific setup it
    // was proven under, so the old proof stopped verifying regardless.
    uint256[2] pA = [
        0x1ab085f7bb321234af337b34a3f8b8e3e2f193b244ad9f8101d805d42dfb3d5d,
        0x27903ac64cf7be9d655b9242d96d817b0a80b307516048c974b549950dbfa9c2
    ];
    uint256[2][2] pB = [
        [
            0x1f39d35b3a5cb81a8e1a2020f919e096d48e4364040785e373dbfaf1e7d4a34e,
            0x16e7a5e2579699f02809572fc2024f057f73bd064a819f249ffeb705b56f78d6
        ],
        [
            0x07bfa5c8e6ef9fa2a1f7156496df57ac998b71af5f3039993ac9a32ac9457f9b,
            0x0454880be328bf78c3ded8850e743181af9123d50c8d0934757c2ee010ea8a62
        ]
    ];
    uint256[2] pC = [
        0x1500b79f6d61eb1abdb4b2fe1f2c305a0620987aa172156669b024e705946c31,
        0x2372565afab5f75c5bd38d72d53f8e47357a9de9d08215eabb6c6f0fa02b6588
    ];

    function setUp() public {
        bytes memory poseidonBytecode = vm.parseBytes(vm.readFile("script/artifacts/PoseidonT3.bytecode.txt"));
        address poseidonT3Addr;
        assembly {
            poseidonT3Addr := create(0, add(poseidonBytecode, 0x20), mload(poseidonBytecode))
        }
        require(poseidonT3Addr != address(0), "PoseidonT3 deploy failed");

        ShieldedSpendVerifier verifier = new ShieldedSpendVerifier();
        token = new MockERC20("Shielded Test Token", "STT", 0);
        pool = new ShieldedPool(address(token), poseidonT3Addr, address(verifier));

        token.mint(address(this), 10_000_000);
        token.approve(address(pool), type(uint256).max);
    }

    function test_deposit_producesTheExactRootTheProofWasGeneratedFor() public {
        pool.deposit(COMMITMENT, AMOUNT);
        assertTrue(pool.knownRoot(ROOT), "on-chain root doesn't match the off-chain fixture's root");
    }

    function test_withdraw_acceptsRealValidProof() public {
        pool.deposit(COMMITMENT, AMOUNT);

        uint256 poolBalanceBefore = token.balanceOf(address(pool));
        pool.withdraw(pA, pB, pC, ROOT, NULLIFIER, WITHDRAW_AMOUNT, NEW_COMMITMENT, RECIPIENT);

        assertEq(token.balanceOf(RECIPIENT), WITHDRAW_AMOUNT);
        assertEq(token.balanceOf(address(pool)), poolBalanceBefore - WITHDRAW_AMOUNT);
        assertTrue(pool.nullifierUsed(NULLIFIER));
    }

    function test_withdraw_rejectsReusedNullifier() public {
        pool.deposit(COMMITMENT, AMOUNT);
        pool.withdraw(pA, pB, pC, ROOT, NULLIFIER, WITHDRAW_AMOUNT, NEW_COMMITMENT, RECIPIENT);

        vm.expectRevert("ShieldedPool: note already spent");
        pool.withdraw(pA, pB, pC, ROOT, NULLIFIER, WITHDRAW_AMOUNT, NEW_COMMITMENT, RECIPIENT);
    }

    function test_withdraw_rejectsUnknownRoot() public {
        pool.deposit(COMMITMENT, AMOUNT);

        vm.expectRevert("ShieldedPool: unknown root");
        pool.withdraw(pA, pB, pC, ROOT + 1, NULLIFIER, WITHDRAW_AMOUNT, NEW_COMMITMENT, RECIPIENT);
    }

    function test_withdraw_rejectsWrongRecipient() public {
        // Same proof, different recipient than it was actually generated
        // for — this is exactly the front-running/theft scenario `recipient`
        // being a public circuit input defends against: the proof
        // cryptographically binds to address(0xBEEF), so redirecting funds
        // to a different address makes it a different, invalid proof.
        pool.deposit(COMMITMENT, AMOUNT);

        vm.expectRevert("ShieldedPool: invalid proof");
        pool.withdraw(pA, pB, pC, ROOT, NULLIFIER, WITHDRAW_AMOUNT, NEW_COMMITMENT, address(0xC0FFEE));
    }

    function test_withdraw_rejectsTamperedWithdrawAmount() public {
        pool.deposit(COMMITMENT, AMOUNT);

        vm.expectRevert("ShieldedPool: invalid proof");
        pool.withdraw(pA, pB, pC, ROOT, NULLIFIER, WITHDRAW_AMOUNT + 1, NEW_COMMITMENT, RECIPIENT);
    }
}
