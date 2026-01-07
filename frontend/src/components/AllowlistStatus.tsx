import { useAccount, useReadContract } from 'wagmi';
import { allowlistGateAbi, vaultAbi } from '../lib/abis';
import { GATE_ADDRESS, VAULT_ADDRESS, CONTACT_EMAIL } from '../lib/contracts';
import { formatUnits } from 'viem';

export function AllowlistStatus() {
  const { address, isConnected } = useAccount();

  const { data: isAllowlisted, isLoading } = useReadContract({
    address: GATE_ADDRESS,
    abi: allowlistGateAbi,
    functionName: 'allowed',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: adminAddress } = useReadContract({
    address: GATE_ADDRESS,
    abi: allowlistGateAbi,
    functionName: 'admin',
  });

  const { data: userShares } = useReadContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!isAllowlisted },
  });

  if (!isConnected) {
    return null;
  }

  const isAdmin = address && adminAddress && 
                  address.toLowerCase() === adminAddress.toLowerCase();

  if (isLoading) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
        <p className="text-gray-600">Checking allowlist status...</p>
      </div>
    );
  }

  // Admin view
  if (isAdmin) {
    return (
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div className="flex items-center gap-2 mb-2">
          <span className="text-2xl">🔑</span>
          <span className="font-semibold text-blue-900">Admin</span>
        </div>
        <p className="text-sm text-blue-700">
          Connected: {address?.slice(0, 6)}...{address?.slice(-4)}
        </p>
        {userShares && (
          <p className="text-sm text-blue-700 mt-2">
            Your balance: {formatUnits(userShares, 18)} shares
          </p>
        )}
        <button
          disabled
          className="mt-3 px-4 py-2 bg-gray-300 text-gray-600 rounded-lg cursor-not-allowed"
        >
          Manage Allowlist (Coming Soon)
        </button>
      </div>
    );
  }

  // Allowlisted user
  if (isAllowlisted) {
    return (
      <div className="bg-green-50 border border-green-200 rounded-lg p-4">
        <div className="flex items-center gap-2 mb-2">
          <span className="text-2xl">✅</span>
          <span className="font-semibold text-green-800">
            You are allowlisted
          </span>
        </div>
        <p className="text-sm text-green-700">
          Connected: {address?.slice(0, 6)}...{address?.slice(-4)}
        </p>
        {userShares && (
          <p className="text-sm text-green-700 mt-2">
            Your balance: {formatUnits(userShares, 18)} shares
          </p>
        )}
        <button
          disabled
          className="mt-3 px-4 py-2 bg-gray-300 text-gray-600 rounded-lg cursor-not-allowed"
        >
          Deposit (Coming Soon)
        </button>
      </div>
    );
  }

  // Not allowlisted
  return (
    <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-2xl">⚠️</span>
        <span className="font-semibold text-yellow-800">
          You are not allowlisted
        </span>
      </div>
      <p className="text-sm text-yellow-700">
        Contact us to request access to the vault.
      </p>
      <a
        href={`mailto:${CONTACT_EMAIL}?subject=Vault Access Request&body=Wallet: ${address}`}
        className="inline-block mt-3 px-4 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700 transition"
      >
        Get in Contact ✉️
      </a>
    </div>
  );
}
