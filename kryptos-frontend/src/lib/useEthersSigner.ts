// Bridges wagmi's viem-based WalletClient to an ethers.js Signer, so the
// existing ethers-based contract read/write code in AppContext.tsx doesn't
// need to be rewritten in viem just because the connection layer moved to
// wagmi/RainbowKit. Standard adapter pattern from wagmi's own ethers docs.
import { useMemo } from "react";
import { useWalletClient } from "wagmi";
import { BrowserProvider, JsonRpcSigner } from "ethers";
import type { WalletClient } from "viem";

function walletClientToSigner(walletClient: WalletClient) {
  const { account, chain, transport } = walletClient;
  if (!account || !chain) return undefined;
  const network = { chainId: chain.id, name: chain.name };
  const provider = new BrowserProvider(transport, network);
  return new JsonRpcSigner(provider, account.address);
}

export function useEthersSigner() {
  const { data: walletClient } = useWalletClient();
  return useMemo(() => (walletClient ? walletClientToSigner(walletClient) : undefined), [walletClient]);
}
