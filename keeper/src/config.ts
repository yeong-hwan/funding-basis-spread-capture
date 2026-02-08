import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

export const config = {
  // Private Key
  keeperPrivateKey: process.env.KEEPER_PRIVATE_KEY || '',

  // RPC Endpoints
  hyperEvmRpc: process.env.HYPEREVM_RPC || 'https://rpc.hyperliquid-testnet.xyz/evm',
  arbitrumRpc: process.env.ARBITRUM_RPC || 'https://arb1.arbitrum.io/rpc',

  // Contract Addresses
  hyperEvmVault: process.env.HYPEREVM_VAULT || '',
  arbitrumSpotVault: process.env.ARBITRUM_SPOT_VAULT || '',
  arbitrumCoordinator: process.env.ARBITRUM_COORDINATOR || '',

  // Strategy Parameters
  deltaThresholdBps: parseInt(process.env.DELTA_THRESHOLD_BPS || '500'),
  minFundingRate: parseFloat(process.env.MIN_FUNDING_RATE || '0.0001'),
  scanIntervalMs: parseInt(process.env.SCAN_INTERVAL_MS || '300000'), // 5 minutes

  // Hyperliquid API
  hyperliquidApiUrl: 'https://api.hyperliquid-testnet.xyz',

  // Alerts (optional)
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || '',
  telegramChatId: process.env.TELEGRAM_CHAT_ID || '',
};

export function validateConfig(): void {
  if (!config.keeperPrivateKey) {
    throw new Error('KEEPER_PRIVATE_KEY is required');
  }
  if (!config.hyperEvmVault) {
    throw new Error('HYPEREVM_VAULT is required');
  }
}
