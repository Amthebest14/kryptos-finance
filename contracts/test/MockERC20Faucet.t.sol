// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract MockERC20FaucetTest is Test {
    MockERC20 token;
    address alice = makeAddr("alice");

    function setUp() public {
        token = new MockERC20("Wrapped Ether", "WETH", 10 ether);
    }

    function test_claimFaucet_firstClaimSucceeds() public {
        assertTrue(token.canClaimFaucet(alice));

        vm.prank(alice);
        token.claimFaucet();

        assertEq(token.balanceOf(alice), 10 ether);
        assertFalse(token.canClaimFaucet(alice));
    }

    function test_claimFaucet_secondClaimSameDayReverts() public {
        vm.startPrank(alice);
        token.claimFaucet();

        vm.expectRevert("MockERC20: faucet already claimed today, resets 00:00 UTC+1");
        token.claimFaucet();
        vm.stopPrank();
    }

    function test_claimFaucet_succeedsAgainAfterUtcPlusOneMidnight() public {
        // Anchor to a known UTC+1 midnight boundary: timestamp 82800 is
        // 23:00 UTC on day 0, i.e. exactly 00:00 UTC+1 on "day 1".
        vm.warp(82800);
        vm.startPrank(alice);
        token.claimFaucet();
        assertEq(token.balanceOf(alice), 10 ether);

        // One second before the next UTC+1 midnight — still the same day, must revert.
        vm.warp(82800 + 1 days - 1);
        vm.expectRevert("MockERC20: faucet already claimed today, resets 00:00 UTC+1");
        token.claimFaucet();

        // Exactly the next UTC+1 midnight — a new day, must succeed.
        vm.warp(82800 + 1 days);
        token.claimFaucet();
        assertEq(token.balanceOf(alice), 20 ether);
        vm.stopPrank();
    }

    function test_faucet_isIndependentPerAsset() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 10_000 ether);

        vm.startPrank(alice);
        token.claimFaucet();
        usdc.claimFaucet(); // different contract instance — must not be blocked by weth's claim
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(usdc.balanceOf(alice), 10_000 ether);
    }

    function test_faucet_isIndependentPerUser() public {
        address bob = makeAddr("bob");

        vm.prank(alice);
        token.claimFaucet();

        vm.prank(bob); // a different claim already having happened today must not block bob
        token.claimFaucet();

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_mint_isNotRateLimited() public {
        // mint() is the unrestricted path tests/deploy seeding use — must
        // remain callable any number of times, unlike claimFaucet().
        token.mint(alice, 1 ether);
        token.mint(alice, 1 ether);
        token.mint(alice, 1 ether);
        assertEq(token.balanceOf(alice), 3 ether);
    }

    function test_nextFaucetClaimAt_reflectsTheUpcomingUtcPlusOneMidnight() public {
        vm.warp(82800); // 00:00 UTC+1
        vm.prank(alice);
        token.claimFaucet();

        assertEq(token.nextFaucetClaimAt(alice), 82800 + 1 days);
    }
}
