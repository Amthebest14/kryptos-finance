// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Stake ZEN, earn a share of protocol interest revenue. Revenue can
/// arrive in any listed asset — WETH, USDC, or ZEN — since VaultManager
/// forwards accrued interest in whatever asset was actually repaid, not a
/// single fixed reward token. This tracks a separate Synthetix-style
/// reward-per-share accumulator per reward asset, all keyed off the same
/// staked ZEN balance, rather than assuming one reward token like the
/// textbook version of this pattern does.
///
/// Where this revenue comes from: VaultManager.repay's `accruedInterest`
/// argument used to be purely self-reported — debt is sealed inside a
/// private commitment the contract can never read, so it had no way to check
/// the claim. Gap #3's fix closed that: transition.circom now checks
/// `accruedInterest` in-circuit against the position's own (private) old
/// debt and VaultManager's own (public) borrowIndex ratio, so a caller
/// touching debt via borrow/repay can no longer claim a wrong amount and
/// still produce a valid proof — not even claiming zero when something is
/// genuinely owed. What's still true, and worth stating precisely rather
/// than overclaiming: this reconciliation only happens AT a borrow/repay —
/// a position that only deposits/withdraws collateral, or simply never
/// touches its debt again, can go a long time without its committed debt
/// reflecting interest that has accrued in the background. Circuit A's own
/// health check does not yet account for that unclaimed, real-time accrual
/// either — a related but distinct limitation from what gap #3 fixed, left
/// as known future work rather than folded into this fix silently.
contract ZenStaking {
    uint256 public constant WAD = 1e18;

    IERC20 public immutable zen;
    // Mutable, not immutable — deliberately. An earlier version fixed this at
    // deploy time, which meant any future VaultManager fix (a new vault
    // address) required redeploying ZenStaking too, orphaning every existing
    // stake and unclaimed reward. owner-gated setVault() lets a vault swap
    // happen in place instead, preserving real state that isn't this
    // contract's to throw away.
    address public vault;
    address public owner;

    uint256 public totalStaked;
    mapping(address => uint256) public stakedOf;

    mapping(address => uint256) public rewardPerShareStored;
    mapping(address => mapping(address => uint256)) public userRewardPerSharePaid;
    mapping(address => mapping(address => uint256)) public claimableReward;
    address[] public rewardAssets;
    mapping(address => bool) public isKnownRewardAsset;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardNotified(address indexed asset, uint256 amount);
    event RewardClaimed(address indexed user, address indexed asset, uint256 amount);
    event VaultChanged(address indexed newVault);
    event OwnerChanged(address indexed newOwner);

    modifier onlyVault() {
        require(msg.sender == vault, "ZenStaking: not vault");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "ZenStaking: not owner");
        _;
    }

    constructor(address _zen, address _vault) {
        zen = IERC20(_zen);
        vault = _vault;
        owner = msg.sender;
    }

    function setVault(address newVault) external onlyOwner {
        require(newVault != address(0), "ZenStaking: zero address");
        vault = newVault;
        emit VaultChanged(newVault);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZenStaking: zero address");
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    function getRewardAssets() external view returns (address[] memory) {
        return rewardAssets;
    }

    function earned(address user, address asset) public view returns (uint256) {
        uint256 delta = rewardPerShareStored[asset] - userRewardPerSharePaid[user][asset];
        return claimableReward[user][asset] + (stakedOf[user] * delta) / WAD;
    }

    // Freezes every reward asset's earned-so-far amount into claimableReward
    // and resets each checkpoint to the current accumulator, using whatever
    // stakedOf[user] was BEFORE this call's own stake/unstake changes it —
    // called first thing in every function that changes stakedOf or pays out.
    function _settle(address user) private {
        uint256 n = rewardAssets.length;
        for (uint256 i = 0; i < n; i++) {
            address asset = rewardAssets[i];
            claimableReward[user][asset] = earned(user, asset);
            userRewardPerSharePaid[user][asset] = rewardPerShareStored[asset];
        }
    }

    function stake(uint256 amount) external {
        require(amount > 0, "ZenStaking: zero amount");
        _settle(msg.sender);
        stakedOf[msg.sender] += amount;
        totalStaked += amount;
        require(zen.transferFrom(msg.sender, address(this), amount), "ZenStaking: transferFrom failed");
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0 && amount <= stakedOf[msg.sender], "ZenStaking: bad amount");
        _settle(msg.sender);
        stakedOf[msg.sender] -= amount;
        totalStaked -= amount;
        require(zen.transfer(msg.sender, amount), "ZenStaking: transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    function claim(address asset) external {
        _settle(msg.sender);
        uint256 amount = claimableReward[msg.sender][asset];
        require(amount > 0, "ZenStaking: nothing to claim");
        claimableReward[msg.sender][asset] = 0;
        require(IERC20(asset).transfer(msg.sender, amount), "ZenStaking: transfer failed");
        emit RewardClaimed(msg.sender, asset, amount);
    }

    /// @notice Called by VaultManager immediately after it has already
    /// transferred `amount` of `asset` to this contract. Reverts if nobody has
    /// staked yet, rather than silently distributing rewards nobody can claim
    /// a share of — VaultManager checks `totalStaked() > 0` before even
    /// transferring, so interest just stays as idle vault liquidity until
    /// staking begins, instead of arriving here and getting stuck.
    function notifyRewardAmount(address asset, uint256 amount) external onlyVault {
        require(totalStaked > 0, "ZenStaking: no stakers");
        if (!isKnownRewardAsset[asset]) {
            isKnownRewardAsset[asset] = true;
            rewardAssets.push(asset);
        }
        rewardPerShareStored[asset] += (amount * WAD) / totalStaked;
        emit RewardNotified(asset, amount);
    }
}
