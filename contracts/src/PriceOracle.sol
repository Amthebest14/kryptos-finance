// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Owner-updated, 1e6-scaled prices and liquidation thresholds for
/// [WETH, USDC, ZEN] — the same fixed order used everywhere else in this repo.
///
/// Exists to close a real exploit: before this contract, ProofVerifierAdapter
/// took `price`/`liqThreshold` as plain caller-supplied calldata and never
/// checked them against anything real. Any caller bypassing the honest
/// frontend could submit a health-factor proof valid for fabricated,
/// self-serving prices and stay "proven healthy" forever regardless of real
/// collateral value — a solvency exploit, not just a privacy gap. Every
/// position now proves against the same on-chain number instead.
///
/// Why not read Pyth directly on-chain, the way the frontend does for
/// display: checked against Pyth's own published contract-address list —
/// Pyth has no deployment on Horizen or Horizen Testnet at all, only Base
/// mainnet and Base Sepolia. A contract on Horizen cannot read another
/// chain's state directly. A real Pyth pull-oracle receiver could be
/// self-deployed here later (Pyth's model is chain-agnostic by design), but
/// that's a substantially larger undertaking, made harder still by Hermes
/// (Pyth's off-chain update source) now requiring a paid API key.
///
/// Honestly labeled, not hidden: this is a single trusted updater, not a
/// decentralized oracle. Whoever holds `owner` can push a wrong price and
/// every subsequent proof relies on it — a real, different trust assumption
/// than a live on-chain oracle would carry. Values are seeded from, and
/// meant to be periodically refreshed from, the same real Base-mainnet Pyth
/// reads (WETH/USDC) and CoinGecko read (ZEN) the frontend already displays
/// (see kryptos-frontend/src/lib/prices.ts) — acceptable for a
/// testnet/prototype, not a substitute for real value at stake.
///
/// `getPrices()` reverts once a price is older than MAX_STALENESS — not
/// originally here, added after noticing nothing stopped the updater from
/// simply going quiet: with no staleness check, every health proof would
/// keep validating against an arbitrarily old price forever, with no
/// on-chain signal anything was wrong, even with a fully honest owner who
/// just forgot to refresh it. liqThreshold isn't gated the same way — it's a
/// risk parameter that changes rarely by design, not a live price that goes
/// stale on its own.
contract PriceOracle {
    uint256 public constant MAX_STALENESS = 24 hours;

    address public owner;
    uint256[3] private _prices; // 1e6-scaled, [WETH, USDC, ZEN]
    uint256[3] private _liqThresholds; // 1e6-scaled, same order
    uint256 public lastUpdated;

    event PricesUpdated(uint256[3] prices, uint256 timestamp);
    event LiqThresholdsUpdated(uint256[3] liqThresholds);
    event OwnerChanged(address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "PriceOracle: not owner");
        _;
    }

    constructor(uint256[3] memory initialPrices, uint256[3] memory initialLiqThresholds) {
        owner = msg.sender;
        _prices = initialPrices;
        _liqThresholds = initialLiqThresholds;
        lastUpdated = block.timestamp;
    }

    function setPrices(uint256[3] calldata newPrices) external onlyOwner {
        _prices = newPrices;
        lastUpdated = block.timestamp;
        emit PricesUpdated(newPrices, block.timestamp);
    }

    function setLiqThresholds(uint256[3] calldata newLiqThresholds) external onlyOwner {
        _liqThresholds = newLiqThresholds;
        emit LiqThresholdsUpdated(newLiqThresholds);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PriceOracle: zero address");
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    function getPrices() external view returns (uint256[3] memory) {
        require(block.timestamp - lastUpdated <= MAX_STALENESS, "PriceOracle: price too stale");
        return _prices;
    }

    function getLiqThresholds() external view returns (uint256[3] memory) {
        return _liqThresholds;
    }
}
