// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SimpleMultiSig} from "../src/SimpleMultiSig.sol";
import {PriceOracle} from "../src/PriceOracle.sol";

contract SimpleMultiSigTest is Test {
    SimpleMultiSig multisig;
    address owner1 = address(0x1111);
    address owner2 = address(0x2222);
    address owner3 = address(0x3333);
    address nonOwner = address(0x9999);

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        multisig = new SimpleMultiSig(owners, 2); // 2-of-3
    }

    function test_constructor_rejectsZeroThreshold() public {
        address[] memory owners = new address[](1);
        owners[0] = owner1;
        vm.expectRevert("SimpleMultiSig: bad threshold");
        new SimpleMultiSig(owners, 0);
    }

    function test_constructor_rejectsThresholdAboveOwnerCount() public {
        address[] memory owners = new address[](1);
        owners[0] = owner1;
        vm.expectRevert("SimpleMultiSig: bad threshold");
        new SimpleMultiSig(owners, 2);
    }

    function test_constructor_rejectsDuplicateOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner1;
        vm.expectRevert("SimpleMultiSig: duplicate owner");
        new SimpleMultiSig(owners, 1);
    }

    function test_propose_countsAsProposersOwnApproval() public {
        vm.prank(owner1);
        uint256 txId = multisig.propose(address(0xBEEF), 0, "");
        assertTrue(multisig.approved(txId, owner1));
        (,,,, uint256 approvalCount) = multisig.transactions(txId);
        assertEq(approvalCount, 1);
    }

    function test_nonOwner_cannotPropose() public {
        vm.prank(nonOwner);
        vm.expectRevert("SimpleMultiSig: not owner");
        multisig.propose(address(0xBEEF), 0, "");
    }

    function test_execute_revertsBelowThreshold() public {
        vm.prank(owner1);
        uint256 txId = multisig.propose(address(0xBEEF), 0, "");

        vm.expectRevert("SimpleMultiSig: not enough approvals");
        multisig.execute(txId);
    }

    function test_execute_succeedsOnceThresholdReached_callableByAnyone() public {
        // Real end-to-end use case: 2-of-3 owners approve a call to
        // PriceOracle.setPrices, and the actual on-chain price changes only
        // once both have signed off — this is the exact mechanism that
        // replaces PriceOracle's single trusted EOA.
        uint256[3] memory initialPrices = [uint256(1), 2, 3];
        uint256[3] memory liq = [uint256(830000), 900000, 650000];
        PriceOracle oracle = new PriceOracle(initialPrices, liq);
        oracle.setOwner(address(multisig));

        uint256[3] memory newPrices = [uint256(100), 200, 300];
        bytes memory data = abi.encodeCall(PriceOracle.setPrices, (newPrices));

        vm.prank(owner1);
        uint256 txId = multisig.propose(address(oracle), 0, data);

        vm.prank(owner2);
        multisig.approve(txId);

        // Executable by a random address once approvals are in — the
        // authorization already happened via the approvals themselves.
        vm.prank(nonOwner);
        multisig.execute(txId);

        uint256[3] memory result = oracle.getPrices();
        assertEq(result[0], 100);
        assertEq(result[1], 200);
        assertEq(result[2], 300);
    }

    function test_execute_revertsOnDoubleExecution() public {
        vm.prank(owner1);
        uint256 txId = multisig.propose(address(0xBEEF), 0, "");
        vm.prank(owner2);
        multisig.approve(txId);

        // target has no code, so a zero-value call with empty data still
        // succeeds (a plain ETH transfer to an EOA-like address) — enough to
        // prove first execution works before testing rejection of a second.
        multisig.execute(txId);

        vm.expectRevert("SimpleMultiSig: already executed");
        multisig.execute(txId);
    }

    function test_approve_revertsOnDoubleApproval() public {
        vm.prank(owner1);
        uint256 txId = multisig.propose(address(0xBEEF), 0, "");

        vm.prank(owner1);
        vm.expectRevert("SimpleMultiSig: already approved");
        multisig.approve(txId);
    }

    function test_revokeApproval_removesApprovalAndDropsCount() public {
        vm.prank(owner1);
        uint256 txId = multisig.propose(address(0xBEEF), 0, "");
        vm.prank(owner2);
        multisig.approve(txId);

        vm.prank(owner2);
        multisig.revokeApproval(txId);

        vm.expectRevert("SimpleMultiSig: not enough approvals");
        multisig.execute(txId);
    }
}
