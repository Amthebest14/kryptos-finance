import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { nodePolyfills } from 'vite-plugin-node-polyfills'

// https://vite.dev/config/
export default defineConfig({
  // snarkjs (used by lib/zkProof.ts to generate real ZK proofs in-browser)
  // pulls in ffjavascript, which assumes Node's Buffer/process globals exist
  // — this polyfills just those, nothing else in the app needs it.
  plugins: [react(), nodePolyfills({ include: ['buffer', 'process'] })],
})
