// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Mintable ERC20 standing in for WETH/USDC/ZEN on this testnet — not
/// the real bridged/canonical asset. Moved here from test/mocks/ because it
/// now carries real, deployed, user-facing behavior (the rate-limited public
/// faucet below), not just test-fixture logic; `mint()` stays unrestricted
/// for tests and deploy-script seeding, which is why the faucet is a
/// separate function rather than a cooldown bolted onto mint() itself —
/// existing tests and the deploy script mint to the same address multiple
/// times and would otherwise trip the daily limit.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Public faucet: one claim per address per UTC+1 calendar day, resetting
    // at 00:00 UTC+1 — not a rolling 24h window from last claim. Adding
    // 1 hours before dividing by 1 days shifts the day boundary from UTC
    // midnight to UTC+1 midnight; block.timestamp is always UTC.
    //
    // lastFaucetClaimDay stores (day claimed + 1), never the raw day index —
    // day index 0 is a real, reachable value (any timestamp in
    // [-3600, 82799], which includes Foundry's low default test timestamp),
    // and 0 doubling as both "day zero" and the mapping's default "never
    // claimed" sentinel is exactly the kind of off-by-one that looks fine
    // until someone's very first claim on day 0 gets rejected as a
    // "repeat" claim. Storing +1 keeps 0 unambiguous.
    uint256 public immutable faucetAmount;
    mapping(address => uint256) public lastFaucetClaimDay;

    event FaucetClaimed(address indexed to, uint256 amount, uint256 dayIndex);

    constructor(string memory _name, string memory _symbol, uint256 _faucetAmount) {
        name = _name;
        symbol = _symbol;
        faucetAmount = _faucetAmount;
    }

    function _currentFaucetDay() internal view returns (uint256) {
        return (block.timestamp + 1 hours) / 1 days;
    }

    /// @notice True if `account` has not yet claimed the faucet for the
    /// current UTC+1 day — lets the frontend disable the button instead of
    /// letting a user hit a revert.
    function canClaimFaucet(address account) external view returns (bool) {
        return lastFaucetClaimDay[account] <= _currentFaucetDay();
    }

    /// @notice Unix timestamp (UTC) of the next moment this account can
    /// claim — always an upcoming 00:00 UTC+1 (i.e. 23:00 UTC). 0 if a claim
    /// is available right now (including "never claimed").
    function nextFaucetClaimAt(address account) external view returns (uint256) {
        uint256 stored = lastFaucetClaimDay[account];
        if (stored == 0) return 0;
        return stored * 1 days - 1 hours;
    }

    function claimFaucet() external {
        uint256 today = _currentFaucetDay();
        require(lastFaucetClaimDay[msg.sender] <= today, "MockERC20: faucet already claimed today, resets 00:00 UTC+1");
        lastFaucetClaimDay[msg.sender] = today + 1;
        balanceOf[msg.sender] += faucetAmount;
        emit FaucetClaimed(msg.sender, faucetAmount, today);
    }

    /// @notice Unrestricted — used by tests and the deploy script to seed
    /// balances directly. Not rate-limited; claimFaucet() above is the
    /// public-facing, rate-limited path real users hit from the UI.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "MockERC20: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "MockERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
