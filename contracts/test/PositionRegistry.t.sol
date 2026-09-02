// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";

contract PositionRegistryTest is Test {
    PositionRegistry registry;
    address vault;
    address verifier;

    function setUp() public {
        vault = makeAddr("vault");
        verifier = makeAddr("verifier");
        registry = new PositionRegistry(vault, verifier);
    }

    function _openPosition() internal returns (uint256 positionId) {
        vm.prank(vault);
        positionId = registry.openPosition(keccak256("initial-commitment"));
    }

    function test_openPosition_setsCommitmentAndTimestamp() public {
        uint256 id = _openPosition();
        (bytes32 commitment, uint64 lastProof, bool exists) = registry.positions(id);
        assertEq(commitment, keccak256("initial-commitment"));
        assertEq(lastProof, uint64(block.timestamp));
        assertTrue(exists);
    }

    function test_onlyVault_canOpenPosition() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("PositionRegistry: not vault");
        registry.openPosition(keccak256("x"));
    }

    function test_onlyVerifier_canRecordProof() public {
        uint256 id = _openPosition();
        vm.prank(address(0xBAD));
        vm.expectRevert("PositionRegistry: not verifier");
        registry.recordProof(id);
    }

    function test_freshPosition_isNotStale_andNotInGrace() public {
        uint256 id = _openPosition();
        assertFalse(registry.isStale(id));
        assertFalse(registry.isInGracePeriod(id));
        assertEq(registry.graceRemaining(id), registry.GRACE_PERIOD());
    }

    function test_missedCheckIn_entersGracePeriod_notYetStale() public {
        uint256 id = _openPosition();
        // Move past the 30-minute proof interval but still inside the 15-minute grace window.
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + 5 minutes);

        assertFalse(registry.isStale(id));
        assertTrue(registry.isInGracePeriod(id));
        assertEq(registry.graceRemaining(id), 10 minutes);
    }

    function test_graceExpires_positionBecomesStale() public {
        uint256 id = _openPosition();
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);

        assertTrue(registry.isStale(id));
        assertFalse(registry.isInGracePeriod(id));
        assertEq(registry.graceRemaining(id), 0);
    }

    function test_freshProof_resetsStaleness() public {
        uint256 id = _openPosition();
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + 10 minutes); // now in grace

        vm.prank(verifier);
        registry.recordProof(id);

        assertFalse(registry.isStale(id));
        assertFalse(registry.isInGracePeriod(id));
        assertEq(registry.graceRemaining(id), registry.GRACE_PERIOD());
    }

    function test_updateCommitment_onlyVault() public {
        uint256 id = _openPosition();
        vm.prank(vault);
        registry.updateCommitment(id, keccak256("new-commitment"));
        (bytes32 commitment,,) = registry.positions(id);
        assertEq(commitment, keccak256("new-commitment"));

        vm.prank(address(0xBAD));
        vm.expectRevert("PositionRegistry: not vault");
        registry.updateCommitment(id, keccak256("hacked"));
    }

    function test_revertsOnUnknownPosition() public {
        vm.expectRevert("PositionRegistry: no position");
        registry.isStale(999);
    }
}
