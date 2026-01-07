# StayLiquid Frontend

Simple read-only interface for the StayLiquid Allowlisted Vault.

## Features

- ✅ Wallet connection (RainbowKit)
- ✅ Check allowlist status
- ✅ View vault TVL
- ✅ View your vault balance (if allowlisted)
- ✅ Admin badge for vault admin
- ⏳ Deposit (coming in STEP 4B.1)
- ⏳ Admin management (coming in STEP 4B.2)

## Setup

### 1. Install Dependencies
```bash
cd frontend
npm install
```

### 2. Configure Environment
```bash
cp .env.example .env
```

Edit `.env` with your deployed contract addresses.

### 3. Get WalletConnect Project ID

1. Go to https://cloud.walletconnect.com
2. Create account and new project
3. Copy Project ID to `.env`

### 4. Start Local Fork
```bash
cd ../contracts
anvil --fork-url $MAINNET_RPC_URL
```

### 5. Deploy Contracts
```bash
forge script script/DeployVault.s.sol:DeployVault \
    --fork-url http://127.0.0.1:8545 \
    --broadcast
```

Copy addresses to `frontend/.env`.

### 6. Run Frontend
```bash
cd frontend
npm run dev
```

Open http://localhost:5173

## Tech Stack

- React 19 + Vite 7 (with Rolldown)
- TypeScript
- wagmi v3 + viem
- RainbowKit
- TailwindCSS v4

## Development

### Build for Production
```bash
npm run build
```

### Preview Production Build
```bash
npm run preview
```

### Lint Code
```bash
npm run lint
```

