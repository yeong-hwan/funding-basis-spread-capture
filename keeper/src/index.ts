import { config, validateConfig } from './config';
import { Keeper } from './keeper';
import { HyperliquidClient } from './hyperliquid';

/**
 * Delta Neutral Strategy Keeper Bot
 *
 * Usage:
 *   npm run keeper              # Start keeper loop
 *   npm run keeper -- --status  # Print status only
 *   npm run keeper -- --funding # Check funding rate only
 */

async function main() {
  console.log('');
  console.log('╔═══════════════════════════════════════════════════════════╗');
  console.log('║      Delta Neutral Strategy - Keeper Bot v1.0.0           ║');
  console.log('║      HyperEVM (Perp Short) + Arbitrum (Spot Long)         ║');
  console.log('╚═══════════════════════════════════════════════════════════╝');
  console.log('');

  // Parse command line arguments
  const args = process.argv.slice(2);

  // Funding rate only mode
  if (args.includes('--funding')) {
    await checkFundingOnly();
    return;
  }

  // Validate configuration
  try {
    validateConfig();
  } catch (error) {
    console.error('❌ Configuration error:', error);
    console.log('\nPlease set up your .env file. See .env.example for reference.');
    process.exit(1);
  }

  // Create keeper instance
  const keeper = new Keeper();

  // Status only mode
  if (args.includes('--status')) {
    await keeper.printStatus();
    return;
  }

  // Handle shutdown gracefully
  process.on('SIGINT', () => {
    console.log('\n\n🛑 Received SIGINT, shutting down...');
    keeper.stop();
    process.exit(0);
  });

  process.on('SIGTERM', () => {
    console.log('\n\n🛑 Received SIGTERM, shutting down...');
    keeper.stop();
    process.exit(0);
  });

  // Start keeper
  await keeper.start();
}

/**
 * Funding Rate만 확인 (설정 없이 실행 가능)
 */
async function checkFundingOnly() {
  console.log('📊 Checking Hyperliquid Funding Rates...\n');

  const client = new HyperliquidClient();

  const coins = ['BTC', 'ETH', 'SOL', 'DOGE', 'ARB'];

  console.log('┌─────────┬──────────────┬──────────────┬──────────────┐');
  console.log('│  Coin   │ Funding Rate │   Mark Px    │  Oracle Px   │');
  console.log('├─────────┼──────────────┼──────────────┼──────────────┤');

  for (const coin of coins) {
    try {
      const data = await client.getMarketData(coin);
      const fundingPct = (data.fundingRate * 100).toFixed(6);
      const annualized = (data.fundingRate * 3 * 365 * 100).toFixed(1);

      console.log(
        `│ ${coin.padEnd(7)} │ ${fundingPct.padStart(10)}% │ $${data.markPrice.toFixed(2).padStart(10)} │ $${data.oraclePrice.toFixed(2).padStart(10)} │`
      );
    } catch (error) {
      console.log(`│ ${coin.padEnd(7)} │     ERROR    │     ERROR    │     ERROR    │`);
    }
  }

  console.log('└─────────┴──────────────┴──────────────┴──────────────┘');

  console.log('\n📈 ETH Annualized Funding Rate:');
  try {
    const ethData = await client.getMarketData('ETH');
    const annualized = ethData.fundingRate * 3 * 365 * 100;
    console.log(`   ${annualized.toFixed(2)}% APR`);
    console.log(`   ${ethData.fundingRate > 0 ? '✅ Positive (Short earns)' : '⚠️ Negative (Short pays)'}`);
  } catch (error) {
    console.log('   Failed to fetch');
  }
}

// Run
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
