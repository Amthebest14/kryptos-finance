// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultManager} from "../src/VaultManager.sol";
import {PositionRegistry} from "../src/PositionRegistry.sol";
import {LiquidationHandler} from "../src/LiquidationHandler.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockProofVerifier} from "./mocks/MockProofVerifier.sol";

/// @notice Tests gap #5's backstop for abandoned positions — proposal, bond,
/// challenge, and both finalize paths. Uses MockProofVerifier the same way
/// LiquidationHandler.t.sol already does for `liquidate()` itself: real
/// Circuit R proof correctness is already exhaustively tested elsewhere
/// (TransitionRevealAdapter.t.sol); what's under test here is the backstop's
/// own logic (timing windows, bond accounting, dispute-accuracy comparison,
/// void-on-recovery) which is orthogonal to whether a given proof is real.
contract LiquidationHandlerBackstopTest is Test {
    VaultManager vault;
    PositionRegistry registry;
    LiquidationHandler handler;
    InterestRateModel interestRateModel;
    ZenStaking zenStaking;
    MockProofVerifier verifier;
    MockERC20 weth;
    MockERC20 usdc;
    MockERC20 zen;

    address alice = makeAddr("alice");
    address keeper = makeAddr("keeper");
    address rival = makeAddr("rival");
    uint256 positionId;

    function setUp() public {
        verifier = new MockProofVerifier();
        interestRateModel = new InterestRateModel(0, 0.1e18, 1e18, 0.8e18);
        weth = new MockERC20("Wrapped Ether", "WETH", 10 ether);
        usdc = new MockERC20("USD Coin", "USDC", 10_000 ether);
        zen = new MockERC20("Horizen", "ZEN", 10_000 ether);

        uint256 nonceNow = vm.getNonce(address(this));
        address predictedVault = vm.computeCreateAddress(address(this), nonceNow + 1);
        address predictedZenStaking = vm.computeCreateAddress(address(this), nonceNow + 2);
        registry = new PositionRegistry(predictedVault, address(0xBEEF));
        vault = new VaultManager(address(registry), address(verifier), address(interestRateModel), predictedZenStaking);
        require(address(vault) == predictedVault, "vault address prediction drifted");
        zenStaking = new ZenStaking(address(zen), address(vault));
        require(address(zenStaking) == predictedZenStaking, "zenStaking address prediction drifted");

        handler = new LiquidationHandler(address(registry), address(vault), address(verifier));
        vault.setLiquidationHandler(address(handler));

        vault.listAsset(address(weth));
        vault.listAsset(address(usdc));

        weth.mint(alice, 100 ether);
        usdc.mint(address(vault), 1_000_000e18);

        vm.startPrank(alice);
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        (positionId,) = vault.positionOf(alice);

        usdc.mint(keeper, 10_000e18);
        vm.prank(keeper);
        usdc.approve(address(handler), type(uint256).max);
        usdc.mint(rival, 10_000e18);
        vm.prank(rival);
        usdc.approve(address(handler), type(uint256).max);
    }

    function _warpPastAbandonment() internal {
        vm.warp(
            block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + handler.ABANDONMENT_WINDOW() + 1
        );
    }

    function test_propose_revertsBeforeAbandonmentWindow() public {
        // Merely stale isn't enough — that happens to healthy automation
        // missing one check-in all the time.
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);

        vm.prank(keeper);
        vm.expectRevert("LiquidationHandler: not abandoned long enough");
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);
    }

    function test_propose_revertsOnImplausibleAmount() public {
        _warpPastAbandonment();

        vm.prank(keeper);
        vm.expectRevert("LiquidationHandler: implausible collateral");
        handler.proposeAbandonedClose(positionId, address(weth), 999_999 ether, address(usdc), 1000e18);
    }

    function test_propose_pullsBondAndStoresProposal() public {
        _warpPastAbandonment();
        uint256 expectedBond = (1000e18 * handler.BOND_BPS()) / 10_000;

        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);

        assertEq(usdc.balanceOf(address(handler)), expectedBond);
        (address proposer,,,,, uint256 bond,, bool active) = handler.proposedCloses(positionId);
        assertEq(proposer, keeper);
        assertEq(bond, expectedBond);
        assertTrue(active);
    }

    function test_propose_revertsIfAlreadyActive() public {
        _warpPastAbandonment();
        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);

        vm.prank(rival);
        vm.expectRevert("LiquidationHandler: proposal already active");
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);
    }

    function test_finalizeByTimeout_revertsBeforeChallengePeriod() public {
        _warpPastAbandonment();
        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);

        vm.prank(rival);
        vm.expectRevert("LiquidationHandler: challenge period not over");
        handler.finalizeByTimeout(positionId);
    }

    function test_finalizeByTimeout_settlesAndRefundsBondAfterChallengePeriod() public {
        _warpPastAbandonment();
        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);
        uint256 keeperUsdcAfterBond = usdc.balanceOf(keeper);

        vm.warp(block.timestamp + handler.CHALLENGE_PERIOD() + 1);

        uint256 vaultUsdcBefore = usdc.balanceOf(address(vault));
        vm.prank(rival); // anyone can finalize an unchallenged proposal, not just the proposer
        handler.finalizeByTimeout(positionId);

        // Rival paid the real debt and got the real collateral.
        assertEq(weth.balanceOf(rival), 10 ether);
        assertEq(usdc.balanceOf(address(vault)), vaultUsdcBefore + 1000e18);
        // Keeper's bond came back — nobody disputed them.
        assertEq(usdc.balanceOf(keeper), keeperUsdcAfterBond + (1000e18 * handler.BOND_BPS()) / 10_000);
        (,,,,,,, bool active) = handler.proposedCloses(positionId);
        assertFalse(active);
    }

    function test_finalizeWithProof_accurateProposal_refundsBondToProposer() public {
        _warpPastAbandonment();
        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);
        uint256 keeperUsdcAfterBond = usdc.balanceOf(keeper);

        vm.prank(rival);
        handler.finalizeWithProof(
            positionId, keccak256("seal-2"), address(weth), 10 ether, address(usdc), 1000e18, "reveal"
        );

        assertEq(weth.balanceOf(rival), 10 ether);
        // Accurate proposal — bond simply returns to the proposer, no penalty.
        assertEq(usdc.balanceOf(keeper), keeperUsdcAfterBond + (1000e18 * handler.BOND_BPS()) / 10_000);
    }

    function test_finalizeWithProof_wrongProposal_slashesBondToWhoeverProvedTheTruth() public {
        _warpPastAbandonment();
        // Keeper lowballs the debt claim — real debt is 1000 USDC, they
        // claim only 900, hoping nobody checks before the challenge window
        // closes.
        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 900e18);
        uint256 bond = (900e18 * handler.BOND_BPS()) / 10_000;
        uint256 rivalUsdcBefore = usdc.balanceOf(rival);

        // Rival proves the real numbers (1000 USDC, not 900).
        vm.prank(rival);
        handler.finalizeWithProof(
            positionId, keccak256("seal-2"), address(weth), 10 ether, address(usdc), 1000e18, "reveal"
        );

        assertEq(weth.balanceOf(rival), 10 ether);
        // Rival paid the REAL 1000 USDC to settle, but also collected
        // keeper's bond as the reward for catching the lowball — net cost
        // to rival is 1000 - bond, exactly the intended penalty on keeper.
        assertEq(usdc.balanceOf(rival), rivalUsdcBefore - 1000e18 + bond);
        // Keeper's bond is gone, kept nothing back.
        (,,,,, uint256 storedBond,, bool active) = handler.proposedCloses(positionId);
        assertFalse(active);
        storedBond; // silence unused-var warning; already asserted via balances above
    }

    function test_finalizeByTimeout_voidsAndRefundsIfPositionRecovered() public {
        _warpPastAbandonment();
        vm.prank(keeper);
        handler.proposeAbandonedClose(positionId, address(weth), 10 ether, address(usdc), 1000e18);
        uint256 keeperUsdcAfterBond = usdc.balanceOf(keeper);
        uint256 proposedAt = block.timestamp;

        // Warp right up to (but not past) the challenge-period boundary,
        // THEN have Alice resurface and prove she's still healthy — a fresh
        // proof only keeps a position fresh for another 45 minutes, so this
        // has to land close to finalizeByTimeout's own call, not any time
        // earlier, or the position would just go stale again on its own by
        // the time the challenge period is actually over (registry's
        // onlyVerifier gate is address(0xBEEF) in this test setup, matching
        // LiquidationHandler.t.sol's own setUp, not the mock verifier
        // itself).
        vm.warp(proposedAt + handler.CHALLENGE_PERIOD());
        vm.prank(address(0xBEEF));
        registry.recordProof(positionId);

        vm.warp(proposedAt + handler.CHALLENGE_PERIOD() + 1);
        handler.finalizeByTimeout(positionId);

        // Bond refunded, nothing seized — the position genuinely recovered.
        assertEq(usdc.balanceOf(keeper), keeperUsdcAfterBond + (1000e18 * handler.BOND_BPS()) / 10_000);
        assertEq(weth.balanceOf(address(handler)), 0);
        (,,,,,,, bool active) = handler.proposedCloses(positionId);
        assertFalse(active);
    }
}
