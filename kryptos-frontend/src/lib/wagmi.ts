import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { defineChain } from "viem";
import { RPC_URL, CHAIN_ID } from "./contracts";

// Horizen Testnet — a real public network (its own chain ID/RPC, built on top
// of Base Sepolia), verified directly against docs.horizen.io rather than
// assumed. WalletConnect/mobile wallets can reach this fine, unlike the local
// Anvil devnet this project started on.
export const horizenTestnet = defineChain({
  id: CHAIN_ID,
  name: "Horizen Testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: {
    default: { name: "Horizen Testnet Explorer", url: "https://horizen-testnet.explorer.caldera.xyz" },
  },
});

export const wagmiConfig = getDefaultConfig({
  appName: "Kryptos Finance",
  projectId: "90f7c21eef9af7a0b4ae6f05eb8e9f88",
  chains: [horizenTestnet],
  ssr: false,
});
