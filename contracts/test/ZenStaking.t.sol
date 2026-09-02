// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZenStaking} from "../src/ZenStaking.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract ZenStakingTest is Test {
    ZenStaking staking;
    MockERC20 zen;
    MockERC20 usdc;
    MockERC20 weth;

    address vault = makeAddr("vault"); // stands in for VaultManager as the only notifyRewardAmount caller
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        zen = new MockERC20("Horizen", "ZEN", 10_000 ether);
        usdc = new MockERC20("USD Coin", "USDC", 10_000 ether);
        weth = new MockERC20("Wrapped Ether", "WETH", 10 ether);
        staking = new ZenStaking(address(zen), vault);

        zen.mint(alice, 1_000e18);
        zen.mint(bob, 1_000e18);
        usdc.mint(vault, 10_000e18);
        weth.mint(vault, 100 ether);

        vm.prank(alice);
        zen.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        zen.approve(address(staking), type(uint256).max);
        vm.prank(vault);
        usdc.approve(address(staking), type(uint256).max);
    }

    function _notify(MockERC20 asset, uint256 amount) internal {
        vm.startPrank(vault);
        asset.transfer(address(staking), amount);
        staking.notifyRewardAmount(address(asset), amount);
        vm.stopPrank();
    }

    function test_stake_movesTokensAndTracksBalance() public {
        vm.prank(alice);
        staking.stake(100e18);

        assertEq(staking.stakedOf(alice), 100e18);
        assertEq(staking.totalStaked(), 100e18);
        assertEq(zen.balanceOf(address(staking)), 100e18);
    }

    function test_unstake_returnsTokens() public {
        vm.startPrank(alice);
        staking.stake(100e18);
        staking.unstake(40e18);
        vm.stopPrank();

        assertEq(staking.stakedOf(alice), 60e18);
        assertEq(zen.balanceOf(alice), 1_000e18 - 60e18);
    }

    function test_unstake_revertsOnMoreThanStaked() public {
        vm.startPrank(alice);
        staking.stake(50e18);
        vm.expectRevert("ZenStaking: bad amount");
        staking.unstake(51e18);
        vm.stopPrank();
    }

    function test_notifyRewardAmount_onlyVault() public {
        usdc.mint(address(this), 100e18);
        usdc.approve(address(staking), 100e18);
        vm.expectRevert("ZenStaking: not vault");
        staking.notifyRewardAmount(address(usdc), 100e18);
    }

    function test_notifyRewardAmount_revertsWithNoStakers() public {
        vm.startPrank(vault);
        usdc.transfer(address(staking), 100e18);
        vm.expectRevert("ZenStaking: no stakers");
        staking.notifyRewardAmount(address(usdc), 100e18);
        vm.stopPrank();
    }

    function test_singleStaker_earnsFullReward() public {
        vm.prank(alice);
        staking.stake(100e18);

        _notify(usdc, 10e18);

        assertEq(staking.earned(alice, address(usdc)), 10e18);
    }

    function test_twoStakers_splitRewardProportionally() public {
        vm.prank(alice);
        staking.stake(300e18); // 75% of pool
        vm.prank(bob);
        staking.stake(100e18); // 25% of pool

        _notify(usdc, 100e18);

        assertEq(staking.earned(alice, address(usdc)), 75e18);
        assertEq(staking.earned(bob, address(usdc)), 25e18);
    }

    function test_multipleRewardAssets_trackedIndependently() public {
        vm.prank(alice);
        staking.stake(100e18);

        _notify(usdc, 10e18);
        _notify(weth, 1 ether);

        assertEq(staking.earned(alice, address(usdc)), 10e18);
        assertEq(staking.earned(alice, address(weth)), 1 ether);
    }

    function test_claim_paysOutAndZeroesClaimable() public {
        vm.prank(alice);
        staking.stake(100e18);
        _notify(usdc, 10e18);

        vm.prank(alice);
        staking.claim(address(usdc));

        assertEq(usdc.balanceOf(alice), 10e18);
        assertEq(staking.earned(alice, address(usdc)), 0);
    }

    function test_claim_revertsWhenNothingToClaim() public {
        vm.prank(alice);
        staking.stake(100e18);
        vm.prank(alice);
        vm.expectRevert("ZenStaking: nothing to claim");
        staking.claim(address(usdc));
    }

    function test_lateStaker_doesNotEarnPastRewards() public {
        vm.prank(alice);
        staking.stake(100e18);
        _notify(usdc, 10e18);

        // Bob joins after the reward was already distributed — should earn
        // nothing from it, only from rewards notified after he staked.
        vm.prank(bob);
        staking.stake(100e18);
        assertEq(staking.earned(bob, address(usdc)), 0);

        _notify(usdc, 20e18);
        assertEq(staking.earned(alice, address(usdc)), 10e18 + 10e18);
        assertEq(staking.earned(bob, address(usdc)), 10e18);
    }

    function test_unstake_settlesEarnedRewardsFirst() public {
        vm.prank(alice);
        staking.stake(100e18);
        _notify(usdc, 10e18);

        vm.prank(alice);
        staking.unstake(100e18);

        // Fully unstaked, but the reward earned while staked must still be claimable.
        assertEq(staking.earned(alice, address(usdc)), 10e18);
        vm.prank(alice);
        staking.claim(address(usdc));
        assertEq(usdc.balanceOf(alice), 10e18);
    }
}
