// Real deployment addresses on Horizen Testnet (chain id 2651420), deployed via
// `forge script script/Deploy.s.sol --rpc-url horizen_testnet --broadcast`.
// Redeploy and update these if the contracts are ever redeployed — see
// contracts/broadcast/Deploy.s.sol/2651420/run-latest.json for the deployment
// record. WETH/USDC/ZEN are freshly-deployed mock tokens, not the real
// bridged/canonical assets.
export const CHAIN_ID = 2651420;
export const RPC_URL = "https://horizen-testnet.rpc.caldera.xyz/http";

// Block these contracts were deployed at (see broadcast/Deploy.s.sol/2651420/
// run-latest.json). Event queries must start here, not block 0 — Horizen
// Testnet's RPC caps eth_getLogs to a 100,000-block window, and the chain is
// already millions of blocks deep. This never mattered on Anvil, which always
// starts fresh at block 0. Adequate for now (deployment just happened), but
// once the chain advances >100k blocks past DEPLOY_BLOCK this single-range
// query will need to be split into 100k-block chunks — not needed yet.
export const DEPLOY_BLOCK = 0x197cd58;

// Redeployed an eighth time (2026-09-02): fixes a real bug found live, not a
// docs-only change. seizeAndRepay() used to leave a liquidated wallet's
// positionOf[owner].active permanently true, sealed against a plain
// keccak256 "closed" marker instead of a genuine Poseidon commitment — no
// transition proof could ever be built from that again, so the wallet was
// locked out of depositing, withdrawing, borrowing, or repaying forever.
// Fixed by resetting `active` on seizure (see VaultManager.sol's own
// seizeAndRepay comment) so a fresh deposit opens a brand-new position
// instead of dead-ending.
//
// Reused as-is (untouched by this fix, so existing wallet balances and
// faucet cooldowns carry over): both Groth16 verifier sets, the health
// verifier, TransitionRevealAdapter, PriceOracle, InterestRateModel, and the
// WETH/USDC/ZEN mock tokens themselves.
//
// ZenStaking is the one real cost of this redeploy: its `vault` reference
// used to be immutable, so it had to be redeployed too, orphaning existing
// stakes and unclaimed rewards. It just gained an owner-gated setVault(), so
// this is the last time a VaultManager fix costs staking state — a future
// fix can point this SAME ZenStaking at a new vault in place.
export const ADDRESSES = {
  proofVerifier: "0x0DB69497D9E1d485758Ef9c5925F383Dc52aFCcb", // ProofVerifierAdapter (real, Circuit A)
  healthVerifier: "0x2DF316eC6fbFED3a336871d7c0b11d1B64938E34", // generated Groth16 verifier (Circuit A) — reused
  transitionVerifier: "0xDe7c8f1C1135A6790F25316ca42B37354196a216", // generated Groth16 verifier (Circuit T) — reused
  revealVerifier: "0xf17904Cdbe9E60F1B210B6f4CBa22da6D0ac40cB", // generated Groth16 verifier (Circuit R) — reused
  transitionRevealAdapter: "0xbaC53287eCf23ac461742B2BC08AC5754664b14d", // reused, gates deposit/withdraw/borrow/repay + liquidate
  priceOracle: "0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5", // reused
  interestRateModel: "0x4049f156BCF0FD86eC93A7100c9006E3e49B2d63", // reused
  zenStaking: "0x0b56986F8Ec05ba0b6da5956269cDA0c5BB9226E", // fresh — see redeploy note above
  registry: "0x4f226Ce0A8b2232562Fc5982a8027903FC2A9Da6",
  vault: "0x6b2cFE744D93AC7734281756CB4f3De0071bE8cA",
  handler: "0x925AF37De2142a6cF4c76D5546D55a90981b57Bd",
  weth: "0x239Ac78cAb8d5553BDC6737593824b06fd88CE47", // reused
  usdc: "0xe026E73C3aD539b6566d2A1A29A5d778e7AB7C9a", // reused
  zen: "0xe015F8ccacC72545b9CF457a610bfC75fFAB4ADd", // reused
} as const;

// Every LiquidationHandler this exact VaultManager/PositionRegistry pair has
// ever pointed to, oldest first, NOT including the current ADDRESSES.handler.
// Found by live testing: a position liquidated through a since-replaced
// handler has its LiquidationSettled event sitting on THAT old contract's own
// address, not the current one — a plain `handler.queryFilter(...)` against
// only ADDRESSES.handler misses it entirely, silently mistreating a genuinely
// closed position as still open. Fresh registry/vault this redeploy means no
// history yet on THIS pair — cleared, not carried forward from the old one.
export const HISTORICAL_HANDLERS: readonly string[] = [];

// Fixed per-asset index matching VaultManager's on-chain assetIndex mapping
// (set by listAsset() in deploy order) — the transition circuit needs this to
// know which of the position's three collateral/debt slots a call touches.
export const ASSET_INDEX: Record<string, number> = { WETH: 0, USDC: 1, ZEN: 2 };

// Only the three assets actually deployed on this devnet. wstETH, cbBTC, USDT
// exist in the design's mock asset table but have no real deployed token yet —
// they're excluded here rather than pointed at a fake address.
export const ASSET_ADDRESS: Record<string, string> = {
  WETH: ADDRESSES.weth,
  USDC: ADDRESSES.usdc,
  ZEN: ADDRESSES.zen,
};

export const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
  // Real rate-limited public faucet — one claim per address per UTC+1
  // calendar day. The drip amount itself is fixed on-chain (immutable
  // faucetAmount), not caller-specified, so FAUCET_AMOUNTS below is a
  // display label that must match the contract, not a parameter.
  "function claimFaucet()",
  "function canClaimFaucet(address) view returns (bool)",
  "function nextFaucetClaimAt(address) view returns (uint256)",
  "function faucetAmount() view returns (uint256)",
];

// Matches each MockERC20's on-chain immutable faucetAmount exactly (see
// contracts/script/Deploy.s.sol) — kept here only as a display label.
export const FAUCET_AMOUNTS: Record<string, number> = { WETH: 10, USDC: 10000, ZEN: 10000 };

export const VAULT_ABI = [
  "function deposit(address asset, uint256 amount, bytes32 newCommitment, bytes transitionProof)",
  "function borrow(address asset, uint256 amount, uint256 accruedInterest, bytes32 newCommitment, bytes transitionProof)",
  "function repay(address asset, uint256 amount, uint256 accruedInterest, bytes32 newCommitment, bytes transitionProof)",
  "function withdraw(address asset, uint256 amount, bytes32 newCommitment, bytes transitionProof)",
  "function positionOf(address) view returns (uint256 positionId, bool active)",
  "function totalSupplied(address) view returns (uint256)",
  "function totalBorrowed(address) view returns (uint256)",
  // Interest accrual reference data — public, but reveals nothing private
  // (it's the same shared index every position's interest is computed
  // against, not any individual position's actual debt).
  "function currentBorrowIndex(address asset) view returns (uint256)",
  "function positionBorrowIndexSnapshot(uint256 positionId, address asset) view returns (uint256)",
  "event Deposited(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount)",
  "event Withdrawn(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount)",
  "event Borrowed(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount)",
  "event Repaid(address indexed user, uint256 indexed positionId, address indexed asset, uint256 amount)",
  "event Seized(uint256 indexed positionId, address indexed collateralAsset, uint256 collateralAmount, address indexed debtAsset, uint256 debtRepaid)",
];

// Real utilization-based rate curve (InterestRateModel.sol) — WAD-scaled
// (1e18 = 100%), a different fixed-point convention from the 1e6 the ZK
// circuits use, since these numbers never enter a circuit.
export const INTEREST_RATE_MODEL_ABI = [
  "function getBorrowRatePerYear(uint256 supplied, uint256 borrowed) view returns (uint256)",
  "function getSupplyRatePerYear(uint256 supplied, uint256 borrowed, uint256 reserveFactor) view returns (uint256)",
  "function utilizationRate(uint256 supplied, uint256 borrowed) view returns (uint256)",
];

// Stake ZEN, earn a share of self-reported accrued interest revenue —
// arriving in whatever asset was actually repaid (WETH, USDC, or ZEN), not a
// single fixed reward token.
export const ZEN_STAKING_ABI = [
  "function stake(uint256 amount)",
  "function unstake(uint256 amount)",
  "function claim(address asset)",
  "function stakedOf(address) view returns (uint256)",
  "function totalStaked() view returns (uint256)",
  "function earned(address user, address asset) view returns (uint256)",
  "function getRewardAssets() view returns (address[])",
  "event Staked(address indexed user, uint256 amount)",
  "event Unstaked(address indexed user, uint256 amount)",
  "event RewardNotified(address indexed asset, uint256 amount)",
  "event RewardClaimed(address indexed user, address indexed asset, uint256 amount)",
];

export const REGISTRY_ABI = [
  "function positions(uint256) view returns (bytes32 commitment, uint64 lastProofTimestamp, bool exists)",
  "function isStale(uint256) view returns (bool)",
  "function isInGracePeriod(uint256) view returns (bool)",
  "function graceRemaining(uint256) view returns (uint256)",
  "function PROOF_INTERVAL() view returns (uint256)",
  "function GRACE_PERIOD() view returns (uint256)",
  "function nextPositionId() view returns (uint256)",
];

// ProofVerifierAdapter's real signature — takes an actual Circuit A Groth16
// proof, not just a bare positionId. See lib/zkProof.ts for how the proof
// itself gets generated client-side.
export const PROOF_VERIFIER_ABI = [
  "function recordProof(uint256 positionId, uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256 commitment)",
];

// price/liqThreshold used to be caller-supplied arguments to recordProof
// above — a real exploit, since nothing checked them against reality. They
// now come from this oracle instead, read on-chain by ProofVerifierAdapter
// itself; the frontend reads the same values here purely so proof generation
// uses the exact numbers the contract will independently supply (a proof
// built against different public inputs would just fail to verify).
export const PRICE_ORACLE_ABI = [
  "function getPrices() view returns (uint256[3])",
  "function getLiqThresholds() view returns (uint256[3])",
];

export const HANDLER_ABI = [
  "function liquidate(uint256 positionId, address collateralAsset, address debtAsset, bytes32 commitment, uint256 collateralAmount, uint256 debtAmount, bytes revealProof)",
  "event LiquidationSettled(uint256 indexed positionId, address indexed collateralAsset, address indexed debtAsset, uint256 timestamp)",
];
