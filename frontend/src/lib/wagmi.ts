import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { mainnet } from 'wagmi/chains';
import { http } from 'wagmi';

export const config = getDefaultConfig({
  appName: 'StayLiquid Vault',
  projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID!,
  chains: [mainnet],
  transports: {
    [mainnet.id]: http(import.meta.env.VITE_RPC_URL),
  },
  ssr: false,
});
