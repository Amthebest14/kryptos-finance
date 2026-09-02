// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";

contract InterestRateModelTest is Test {
    // 0% base, 10%/year up to 80% utilization, 100%/year jump slope beyond it
    // — same parameters Deploy.s.sol actually uses, not arbitrary test values.
    InterestRateModel model;

    function setUp() public {
        model = new InterestRateModel(0, 0.1e18, 1e18, 0.8e18);
    }

    function test_utilizationRate_isZeroWhenNothingSupplied() public view {
        assertEq(model.utilizationRate(0, 0), 0);
    }

    function test_utilizationRate_computesRatio() public view {
        // 500 borrowed / 1000 supplied = 50%
        assertEq(model.utilizationRate(1000e18, 500e18), 0.5e18);
    }

    function test_borrowRate_atZeroUtilization_isBaseRate() public view {
        assertEq(model.getBorrowRatePerYear(1000e18, 0), 0);
    }

    function test_borrowRate_belowKink_isLinear() public view {
        // 50% utilization: base(0) + 0.5 * 10%/year = 5%/year
        uint256 rate = model.getBorrowRatePerYear(1000e18, 500e18);
        assertEq(rate, 0.05e18);
    }

    function test_borrowRate_atKink_isMultiplierAtKink() public view {
        // 80% utilization: 0 + 0.8 * 10% = 8%/year, exactly at the kink —
        // must match whichever branch is evaluated, no discontinuity.
        uint256 rate = model.getBorrowRatePerYear(1000e18, 800e18);
        assertEq(rate, 0.08e18);
    }

    function test_borrowRate_aboveKink_jumpsSteeper() public view {
        // 90% utilization: 8% (rate at kink) + 0.10 excess * 100%/year jump = 18%/year
        uint256 rate = model.getBorrowRatePerYear(1000e18, 900e18);
        assertEq(rate, 0.18e18);
    }

    function test_borrowRate_isMonotonicallyIncreasingInUtilization() public view {
        uint256 r50 = model.getBorrowRatePerYear(1000e18, 500e18);
        uint256 r80 = model.getBorrowRatePerYear(1000e18, 800e18);
        uint256 r90 = model.getBorrowRatePerYear(1000e18, 900e18);
        assertTrue(r80 > r50);
        assertTrue(r90 > r80);
    }

    function test_borrowRatePerSecond_dividesEvenlyIntoPerYear() public view {
        uint256 perYear = model.getBorrowRatePerYear(1000e18, 500e18);
        uint256 perSecond = model.getBorrowRatePerSecond(1000e18, 500e18);
        assertEq(perSecond, perYear / model.SECONDS_PER_YEAR());
    }

    function test_supplyRate_isBorrowRateTimesUtilizationTimesOneMinusReserveFactor() public view {
        // 50% utilization, 5%/year borrow rate, 10% reserve factor:
        // supply rate = 5% * 50% * (1 - 10%) = 2.25%/year
        uint256 rate = model.getSupplyRatePerYear(1000e18, 500e18, 0.1e18);
        assertEq(rate, 0.0225e18);
    }

    function test_supplyRate_isZeroAtZeroUtilization() public view {
        assertEq(model.getSupplyRatePerYear(1000e18, 0, 0.1e18), 0);
    }

    function test_constructor_rejectsKinkAboveOneHundredPercent() public {
        vm.expectRevert("InterestRateModel: kink > 100%");
        new InterestRateModel(0, 0.1e18, 1e18, 1.1e18);
    }
}
