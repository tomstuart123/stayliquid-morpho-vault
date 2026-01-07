import { ConnectButton } from '@rainbow-me/rainbowkit';
import { VaultStats } from './components/VaultStats';
import { AllowlistStatus } from './components/AllowlistStatus';

function App() {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex justify-between items-center">
          <h1 className="text-2xl font-bold text-gray-900">
            StayLiquid Vault
          </h1>
          <ConnectButton />
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="space-y-6">
          <AllowlistStatus />
          <VaultStats />
        </div>
      </main>
    </div>
  );
}

export default App;
