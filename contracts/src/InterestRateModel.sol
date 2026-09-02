// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice A standard kinked (Compound-style) utilization-based rate curve —
/// real, live, computed only from public data (each asset's own totalSupplied
/// and totalBorrowed), so it needs no private inputs and has no interaction
/// with the privacy design at all. One shared curve is used across every
/// listed asset; assets differ only in the public utilization they each feed
/// into it, not in the curve itself.
///
/// Rates here are WAD-scaled (1e18 = 100%), the standard DeFi convention —
/// deliberately a different scale from the rest of this repo's 1e6 circuit
/// fixed-point convention, since these numbers never enter a circuit and
/// serve a different purpose (display/accrual math, not commitment hashing).
contract InterestRateModel {
    uint256 public constant WAD = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Rate at 0% utilization.
    uint256 public immutable baseRatePerYear;
    /// @notice Slope below `kink`.
    uint256 public immutable multiplierPerYear;
    /// @notice Slope above `kink` — steeper, to discourage draining a market dry.
    uint256 public immutable jumpMultiplierPerYear;
    /// @notice Utilization (WAD) at which the slope switches from `multiplierPerYear`
    /// to `jumpMultiplierPerYear`.
    uint256 public immutable kink;

    constructor(uint256 _baseRatePerYear, uint256 _multiplierPerYear, uint256 _jumpMultiplierPerYear, uint256 _kink) {
        require(_kink <= WAD, "InterestRateModel: kink > 100%");
        baseRatePerYear = _baseRatePerYear;
        multiplierPerYear = _multiplierPerYear;
        jumpMultiplierPerYear = _jumpMultiplierPerYear;
        kink = _kink;
    }

    /// @notice `borrowed / supplied`, WAD-scaled. 0 when nothing is supplied —
    /// an empty market has no utilization to price, not a divide-by-zero bug.
    function utilizationRate(uint256 supplied, uint256 borrowed) public pure returns (uint256) {
        if (supplied == 0) return 0;
        // Callers pass real on-chain totals, where borrowed can never exceed
        // supplied (VaultManager only lends out what it holds) — utilization
        // above 100% would indicate a caller error, not a rate this model
        // needs to handle gracefully.
        return (borrowed * WAD) / supplied;
    }

    function getBorrowRatePerYear(uint256 supplied, uint256 borrowed) public view returns (uint256) {
        uint256 u = utilizationRate(supplied, borrowed);
        if (u <= kink) {
            return baseRatePerYear + (u * multiplierPerYear) / WAD;
        }
        uint256 normalRate = baseRatePerYear + (kink * multiplierPerYear) / WAD;
        uint256 excessUtilization = u - kink;
        return normalRate + (excessUtilization * jumpMultiplierPerYear) / WAD;
    }

    function getBorrowRatePerSecond(uint256 supplied, uint256 borrowed) public view returns (uint256) {
        return getBorrowRatePerYear(supplied, borrowed) / SECONDS_PER_YEAR;
    }

    /// @notice What suppliers would earn if supply-side interest distribution
    /// existed: `borrowRate * utilization * (1 - reserveFactor)`. Display-only
    /// in this version — VaultManager doesn't pay depositors interest yet, so
    /// this is the curve's rate, not money currently being earned (labeled as
    /// such wherever it's shown).
    function getSupplyRatePerYear(uint256 supplied, uint256 borrowed, uint256 reserveFactor)
        public
        view
        returns (uint256)
    {
        uint256 u = utilizationRate(supplied, borrowed);
        uint256 borrowRate = getBorrowRatePerYear(supplied, borrowed);
        uint256 rateToPool = (borrowRate * u) / WAD;
        return (rateToPool * (WAD - reserveFactor)) / WAD;
    }
}
