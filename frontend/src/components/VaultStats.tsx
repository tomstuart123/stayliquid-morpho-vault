import { useReadContract } from 'wagmi';
import { vaultAbi } from '../lib/abis';
import { VAULT_ADDRESS } from '../lib/contracts';
import { formatUnits } from 'viem';

export function VaultStats() {
  const { data: totalAssets, isLoading } = useReadContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: 'totalAssets',
  });

  if (isLoading) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <p className="text-gray-500">Loading vault stats...</p>
      </div>
    );
  }

  const tvl = totalAssets ? formatUnits(totalAssets, 6) : '0';
  const tvlFormatted = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(Number(tvl));

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <h2 className="text-xl font-semibold text-gray-900 mb-4">
        📊 Vault Stats
      </h2>
      <div className="space-y-3">
        <div>
          <p className="text-sm text-gray-600">Total Value Locked</p>
          <p className="text-3xl font-bold text-gray-900">{tvlFormatted}</p>
        </div>
        <div>
          <p className="text-sm text-gray-600">Access Control</p>
          <p className="text-base text-gray-900">Managed by allowlist</p>
        </div>
      </div>
    </div>
  );
}
