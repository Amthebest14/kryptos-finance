// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockProofVerifier} from "./mocks/MockProofVerifier.sol";

contract VaultManagerTest is Test {
    VaultManager vault;
    PositionRegistry registry;
    InterestRateModel interestRateModel;
    ZenStaking zenStaking;
    MockProofVerifier verifier;
    MockERC20 weth;
    MockERC20 usdc;
    MockERC20 zen;

    address owner = address(this);
    address alice = makeAddr("alice");
    address liquidator = makeAddr("liquidator");

    function setUp() public {
        verifier = new MockProofVerifier();
        interestRateModel = new InterestRateModel(0, 0.1e18, 1e18, 0.8e18);
        weth = new MockERC20("Wrapped Ether", "WETH", 10 ether);
        usdc = new MockERC20("USD Coin", "USDC", 10_000 ether);
        zen = new MockERC20("Horizen", "ZEN", 10_000 ether);

        // VaultManager needs the registry's address up front, but the registry needs
        // VaultManager's address too, and VaultManager needs ZenStaking's address up
        // front while ZenStaking needs VaultManager's real address — deploy registry
        // and vault against computed future addresses, then ZenStaking against the
        // (by then real) vault address.
        uint256 nonceNow = vm.getNonce(address(this));
        address predictedVault = vm.computeCreateAddress(address(this), nonceNow + 1);
        address predictedZenStaking = vm.computeCreateAddress(address(this), nonceNow + 2);
        registry = new PositionRegistry(predictedVault, address(0xBEEF)); // proof recorder unused in these tests
        vault = new VaultManager(address(registry), address(verifier), address(interestRateModel), predictedZenStaking);
        require(address(vault) == predictedVault, "vault address prediction drifted");
        zenStaking = new ZenStaking(address(zen), address(vault));
        require(address(zenStaking) == predictedZenStaking, "zenStaking address prediction drifted");

        vault.listAsset(address(weth));
        vault.listAsset(address(usdc));
        vault.setLiquidationHandler(liquidator);

        weth.mint(alice, 100 ether);
        usdc.mint(alice, 1_000_000e18);
        usdc.mint(address(vault), 1_000_000e18); // liquidity for alice to borrow against

        vm.startPrank(alice);
        weth.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_firstDeposit_opensPosition_noProofRequired() public {
        verifier.setShouldVerify(false); // proves the first deposit truly skips verification

        vm.prank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");

        (uint256 positionId, bool active) = vault.positionOf(alice);
        assertTrue(active);
        assertEq(vault.totalSupplied(address(weth)), 10 ether);
        assertEq(weth.balanceOf(address(vault)), 10 ether);

        (bytes32 commitment,,) = registry.positions(positionId);
        assertEq(commitment, keccak256("seal-1"));
    }

    function test_secondDeposit_requiresValidTransitionProof() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");

        verifier.setShouldVerify(false);
        vm.expectRevert("VaultManager: invalid transition proof");
        vault.deposit(address(weth), 5 ether, keccak256("seal-2"), "bad-proof");
        vm.stopPrank();
    }

    // Real bug, found live: depositing a second, DIFFERENT asset (one this
    // position had never borrowed/repaid) passed positionBorrowIndexSnapshot's
    // raw default of 0 as both checkpointIndex and currentIndex. VaultManager
    // itself doesn't care what these equal — MockProofVerifier accepts
    // anything — but the real circuit's floor-division interest check needs
    // checkpointIndex > 0 to be satisfiable at all, so every such deposit
    // failed to prove against the real deployed verifier. This wouldn't have
    // caught that with the mock alone (it just returns true/false, blind to
    // the actual values) — MockProofVerifier now records what it was called
    // with specifically so this can assert on it.
    function test_deposit_secondAsset_usesNonZeroCheckpointIndex() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.deposit(address(usdc), 100e18, keccak256("seal-2"), "proof");
        vm.stopPrank();

        assertEq(verifier.lastCheckpointIndex(), 1e18, "must substitute borrowIndex[asset], not pass a raw 0");
        assertEq(verifier.lastCurrentIndex(), 1e18);
    }

    function test_deposit_revertsOnUnsupportedAsset() public {
        MockERC20 rando = new MockERC20("Rando", "RND", 1 ether);
        vm.prank(alice);
        vm.expectRevert("VaultManager: unsupported asset");
        vault.deposit(address(rando), 1, keccak256("x"), "");
    }

    function test_borrow_movesTokensAndUpdatesAggregate() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 1_000_000e18 + 1000e18);
        assertEq(vault.totalBorrowed(address(usdc)), 1000e18);
    }

    function test_borrow_blockedWhenStale() public {
        vm.prank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");

        (uint256 positionId,) = vault.positionOf(alice);
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);
        assertTrue(registry.isStale(positionId));

        vm.prank(alice);
        vm.expectRevert("VaultManager: position stale");
        vault.borrow(address(usdc), 100e18, 0, keccak256("seal-2"), "proof");
    }

    function test_withdraw_blockedWhenStale() public {
        vm.prank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");

        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);

        vm.prank(alice);
        vm.expectRevert("VaultManager: position stale");
        vault.withdraw(address(weth), 1 ether, keccak256("seal-2"), "proof");
    }

    function test_repay_allowedEvenWhenStale() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);

        vm.prank(alice);
        vault.repay(address(usdc), 500e18, 0, keccak256("seal-3"), "proof");

        assertEq(vault.totalBorrowed(address(usdc)), 500e18);
    }

    function test_seizeAndRepay_onlyLiquidationHandler() public {
        vm.prank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        (uint256 positionId,) = vault.positionOf(alice);
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);

        vm.prank(alice); // not the liquidation handler
        vm.expectRevert("VaultManager: not liquidation handler");
        vault.seizeAndRepay(positionId, address(weth), 10 ether, address(usdc), 0, bytes32(0));
    }

    function test_seizeAndRepay_requiresStalePosition() public {
        vm.prank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        (uint256 positionId,) = vault.positionOf(alice);

        vm.prank(liquidator);
        vm.expectRevert("VaultManager: not liquidatable");
        vault.seizeAndRepay(positionId, address(weth), 10 ether, address(usdc), 0, bytes32(0));
    }

    function test_seizeAndRepay_movesCollateralToHandler() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);
        (uint256 positionId,) = vault.positionOf(alice);

        vm.prank(liquidator);
        vault.seizeAndRepay(positionId, address(weth), 10 ether, address(usdc), 1000e18, bytes32(0));

        assertEq(weth.balanceOf(liquidator), 10 ether);
        assertEq(vault.totalSupplied(address(weth)), 0);
        assertEq(vault.totalBorrowed(address(usdc)), 0);
    }

    // The actual bug this session found live: seizeAndRepay used to leave
    // positionOf[owner].active permanently true, and the closed position's
    // commitment became a plain keccak256 marker — not a real Poseidon
    // commitment of any state a circuit could ever prove a transition from.
    // Every future deposit/withdraw/borrow/repay from that wallet was
    // permanently unprovable, locking it out of the vault forever. Fixed by
    // resetting `active` on seizure so the next deposit opens a genuinely
    // fresh position instead.
    function test_seizeAndRepay_freesTheOwnerToOpenAFreshPositionAfterwards() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);
        (uint256 closedPositionId,) = vault.positionOf(alice);

        vm.prank(liquidator);
        vault.seizeAndRepay(closedPositionId, address(weth), 10 ether, address(usdc), 1000e18, bytes32(0));

        (, bool activeAfterSeizure) = vault.positionOf(alice);
        assertFalse(activeAfterSeizure, "wallet should be freed, not permanently locked");

        // The real proof: a genuinely fresh deposit succeeds afterwards, no
        // transition proof required, exactly like a first-ever deposit.
        weth.mint(alice, 5 ether);
        verifier.setShouldVerify(false); // proves this really took the "open fresh position" branch
        vm.prank(alice);
        vault.deposit(address(weth), 5 ether, keccak256("seal-reopened"), "");

        (uint256 newPositionId, bool activeNow) = vault.positionOf(alice);
        assertTrue(activeNow);
        assertTrue(newPositionId != closedPositionId, "should be a brand new position, not the closed one");
        assertEq(vault.positionOwner(newPositionId), alice);
    }

    function test_borrow_accruedInterest_addsToDeltaButNotToTotalBorrowed() public {
        // totalBorrowed tracks principal only — accruedInterest inflates the
        // debt delta proven to the circuit (checked indirectly here: since
        // MockProofVerifier accepts anything, the only way to see the split
        // took effect is totalBorrowed reflecting `amount`, not `amount +
        // accruedInterest`) but never the public aggregate, since no extra
        // tokens actually moved for the interest portion of a borrow.
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 50e18, keccak256("seal-2"), "proof");
        vm.stopPrank();

        assertEq(vault.totalBorrowed(address(usdc)), 1000e18);
        assertEq(usdc.balanceOf(alice), 1_000_000e18 + 1000e18);
    }

    function test_repay_accruedInterest_reducesTotalBorrowedByPrincipalOnly() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        // Repaying 110 USDC where 10 USDC of it is self-reported interest —
        // only the 100 USDC principal portion should reduce totalBorrowed.
        vault.repay(address(usdc), 110e18, 10e18, keccak256("seal-3"), "proof");
        vm.stopPrank();

        assertEq(vault.totalBorrowed(address(usdc)), 1000e18 - 100e18);
    }

    function test_repay_accruedInterest_withNoStakers_leavesFundsInVault() public {
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vault.repay(address(usdc), 110e18, 10e18, keccak256("seal-3"), "proof");
        vm.stopPrank();

        // Nobody has staked ZEN, so the 10 USDC "interest" is never forwarded
        // — it just stays as idle vault liquidity, not sent anywhere unclaimable.
        assertEq(usdc.balanceOf(address(zenStaking)), 0);
        assertEq(zenStaking.totalStaked(), 0);
    }

    function test_repay_accruedInterest_withStakers_fundsRealStakingRevenue() public {
        address staker = makeAddr("staker");
        zen.mint(staker, 100e18);
        vm.startPrank(staker);
        zen.approve(address(zenStaking), type(uint256).max);
        zenStaking.stake(100e18);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vault.repay(address(usdc), 110e18, 10e18, keccak256("seal-3"), "proof");
        vm.stopPrank();

        // Real tokens, not just accounting: the 10 USDC interest portion
        // actually arrived in ZenStaking and the sole staker is entitled to
        // all of it.
        assertEq(usdc.balanceOf(address(zenStaking)), 10e18);
        assertEq(zenStaking.earned(staker, address(usdc)), 10e18);

        vm.prank(staker);
        zenStaking.claim(address(usdc));
        assertEq(usdc.balanceOf(staker), 10e18);
    }

    function test_currentBorrowIndex_growsOverTimeUnderUtilization() public {
        // totalSupplied[usdc] is otherwise 0 in this fixture (the vault's USDC
        // liquidity in setUp is seeded by a raw mint, not a real deposit(), so
        // it never touches totalSupplied) — deposit some real USDC collateral
        // too so utilization is genuinely nonzero and there's a real rate to
        // accrue at, not the 0% base rate at 0% utilization.
        vm.startPrank(alice);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.deposit(address(usdc), 2000e18, keccak256("seal-1b"), "proof");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        uint256 indexBefore = vault.currentBorrowIndex(address(usdc));
        vm.warp(block.timestamp + 365 days);
        uint256 indexAfter = vault.currentBorrowIndex(address(usdc));

        assertTrue(indexAfter > indexBefore, "index should grow while debt is outstanding");
    }

    function test_onlyOwner_canListAssetOrSetHandler() public {
        vm.startPrank(alice);
        vm.expectRevert("VaultManager: not owner");
        vault.listAsset(address(0x1234));

        vm.expectRevert("VaultManager: not owner");
        vault.setLiquidationHandler(alice);
        vm.stopPrank();
    }
}
