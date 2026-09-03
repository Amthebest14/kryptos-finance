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
export const DEPLOY_BLOCK = 0x199c9ec;

// Redeployed an eleventh time (2026-09-03): the tenth redeploy fixed a real
// bug (checkpointIndex/currentIndex genuinely 0 for a never-borrowed asset,
// unsatisfiable against the ninth redeploy's floor-division remainder check
// — see VaultManager._submitCollateralTransition's own comment) but shipped
// broken: its own deploy script reused a stale TRANSITION_REVEAL_ADAPTER
// constant, copied from the EIGHTH redeploy (gap #9's fix) rather than the
// ninth (the interest-proof fix) — wiring the new VaultManager to an old
// adapter that itself still pointed at the pre-interest-fix
// TransitionVerifier. Every transition proof this project's own current
// circuit files generate was therefore being checked against a
// verification key from a different, older circuit — cryptographically
// guaranteed to fail, independent of anything about checkpointIndex.
// Caught live via a controlled reproduction script before this ever
// reached testnet.kryptos.finance: calling TransitionRevealAdapter's
// verifyTransition directly returned false even though the exact same
// proof verified true against the raw Groth16 verifier it should have
// held — its own transitionVerifier() read back the OLD address, not
// 0x674D241d662DD538f9Ae693463362977E6D7DC8D.
//
// Only the wiring constant changed — same five fresh contracts as the
// tenth redeploy, this time pointed at the correct (ninth-redeploy)
// TransitionRevealAdapter. Everything else reused as-is; ZenStaking
// repointed via setVault() again, not redeployed.
export const ADDRESSES = {
  proofVerifier: "0x8c1441f3A63dc03375AfeDd6DBeAEbc0a40c57f8", // ProofVerifierAdapter (real, Circuit A)
  healthVerifier: "0x2DF316eC6fbFED3a336871d7c0b11d1B64938E34", // generated Groth16 verifier (Circuit A) — reused
  transitionVerifier: "0x674D241d662DD538f9Ae693463362977E6D7DC8D", // generated Groth16 verifier (Circuit T) — reused, circuit itself unchanged since the ninth redeploy
  revealVerifier: "0xf17904Cdbe9E60F1B210B6f4CBa22da6D0ac40cB", // generated Groth16 verifier (Circuit R) — reused
  transitionRevealAdapter: "0x7E9cA610f84A2971E0D0576d7018196726fC3612", // reused — the CORRECT one, verified to point at the right TransitionVerifier
  priceOracle: "0xD746bD3B09ce0D4Ba708BA85479471A93792b1E5", // reused
  interestRateModel: "0x4049f156BCF0FD86eC93A7100c9006E3e49B2d63", // reused
  zenStaking: "0x0b56986F8Ec05ba0b6da5956269cDA0c5BB9226E", // reused, repointed via setVault()
  registry: "0x9b9Aaa9D52f3C4d386fEA2FFBa659251f734badf",
  vault: "0x9F009aa7080605C7685a6283a2068735FD0EC8A5",
  handler: "0xf17FB2cD76B320d2a08DaD842b8B2c840689e384",
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
  "function borrowIndex(address asset) view returns (uint256)",
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
