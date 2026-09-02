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

contract LiquidationHandlerTest is Test {
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
        usdc.mint(address(vault), 1_000_000e18); // liquidity for alice to borrow against

        vm.startPrank(alice);
        weth.approve(address(vault), type(uint256).max);
        vault.deposit(address(weth), 10 ether, keccak256("seal-1"), "");
        vault.borrow(address(usdc), 1000e18, 0, keccak256("seal-2"), "proof");
        vm.stopPrank();

        (positionId,) = vault.positionOf(alice);
    }

    function _warpPastStale() internal {
        vm.warp(block.timestamp + registry.PROOF_INTERVAL() + registry.GRACE_PERIOD() + 1);
    }

    function test_liquidate_revertsIfNotStale() public {
        vm.expectRevert("LiquidationHandler: not stale");
        handler.liquidate(positionId, address(weth), address(usdc), keccak256("seal-2"), 10 ether, 1000e18, "reveal");
    }

    function test_liquidate_revertsOnCommitmentMismatch() public {
        _warpPastStale();
        vm.expectRevert("LiquidationHandler: commitment mismatch");
        handler.liquidate(
            positionId, address(weth), address(usdc), keccak256("wrong-commitment"), 10 ether, 1000e18, "reveal"
        );
    }

    function test_liquidate_revertsOnInvalidRevealProof() public {
        _warpPastStale();
        verifier.setShouldVerify(false);
        vm.expectRevert("LiquidationHandler: invalid reveal proof");
        handler.liquidate(positionId, address(weth), address(usdc), keccak256("seal-2"), 10 ether, 1000e18, "reveal");
    }

    function test_liquidate_settlesAndSeizesCollateral() public {
        _warpPastStale();
        usdc.mint(address(this), 1000e18);
        usdc.approve(address(handler), 1000e18);

        uint256 vaultUsdcBefore = usdc.balanceOf(address(vault));
        handler.liquidate(positionId, address(weth), address(usdc), keccak256("seal-2"), 10 ether, 1000e18, "reveal");

        // The fix, verified directly: collateral goes to the liquidator (not
        // stuck in the contract), and the vault's real USDC balance actually
        // grows by the repaid amount — not just the totalBorrowed number.
        assertEq(weth.balanceOf(address(this)), 10 ether);
        assertEq(weth.balanceOf(address(handler)), 0);
        assertEq(usdc.balanceOf(address(vault)), vaultUsdcBefore + 1000e18);
        assertEq(vault.totalSupplied(address(weth)), 0);
        assertEq(vault.totalBorrowed(address(usdc)), 0);

        (bytes32 finalCommitment,,) = registry.positions(positionId);
        assertTrue(finalCommitment != keccak256("seal-2"), "commitment should be re-sealed on close");
    }

    function test_liquidate_revertsWithoutDebtPayment() public {
        // No mint/approve this time — the liquidator hasn't actually
        // supplied the debt asset they're claiming to repay.
        _warpPastStale();

        vm.expectRevert("MockERC20: insufficient allowance");
        handler.liquidate(positionId, address(weth), address(usdc), keccak256("seal-2"), 10 ether, 1000e18, "reveal");
    }

    function test_liquidate_emitsNoAmounts() public {
        _warpPastStale();
        usdc.mint(address(this), 1000e18);
        usdc.approve(address(handler), 1000e18);

        vm.expectEmit(true, true, true, true);
        emit LiquidationHandler.LiquidationSettled(positionId, address(weth), address(usdc), block.timestamp);
        handler.liquidate(positionId, address(weth), address(usdc), keccak256("seal-2"), 10 ether, 1000e18, "reveal");
    }

    function test_liquidate_isPermissionless_anyoneCanSubmitAValidReveal() public {
        _warpPastStale();
        address keeper = makeAddr("keeper");
        usdc.mint(keeper, 1000e18);
        vm.prank(keeper);
        usdc.approve(address(handler), 1000e18);

        vm.prank(keeper); // not alice, not the vault owner — proves this isn't access-gated,
        // only gated by possession of a valid reveal proof (which only the secret holder can produce)
        // AND by actually paying the real debt being claimed as repaid.
        handler.liquidate(positionId, address(weth), address(usdc), keccak256("seal-2"), 10 ether, 1000e18, "reveal");

        assertEq(weth.balanceOf(keeper), 10 ether);
        assertEq(weth.balanceOf(address(handler)), 0);
    }
}
