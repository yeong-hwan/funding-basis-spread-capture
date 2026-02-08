import { ethers } from 'ethers';
import { config } from './config';
import { FundingCaptureVaultV2Abi, DeltaCoordinatorAbi, SpotLongVaultAbi } from './abis';
import { HyperliquidClient } from './hyperliquid';
import { logger } from './logger';
import { adminServer } from './admin';

/**
 * Delta Neutral Strategy Keeper
 *
 * 주요 기능:
 * 1. Position Sync: HyperEVM Perp 포지션 → Arbitrum DeltaCoordinator 동기화
 * 2. Delta Monitor: Delta 비율 모니터링 및 리밸런싱 트리거
 * 3. Funding Monitor: Funding Rate 모니터링 및 전략 활성화/비활성화
 */
export class Keeper {
  private hyperEvmProvider: ethers.JsonRpcProvider;
  private arbitrumProvider: ethers.JsonRpcProvider;
  private hyperEvmWallet: ethers.Wallet;
  private arbitrumWallet: ethers.Wallet;

  private hyperEvmVault: ethers.Contract;
  private arbitrumCoordinator: ethers.Contract | null = null;
  private arbitrumSpotVault: ethers.Contract | null = null;

  private hyperliquidClient: HyperliquidClient;

  private isRunning: boolean = false;
  private latestMetrics: {
    market?: { ethFundingRate: number; ethMarkPrice: number; ethOraclePrice: number; annualizedApr: number };
    vault?: { state: string; spotValueUsd: number; deltaRatioBps: number };
    wallet?: { hyperEvmBalance: string; arbitrumBalance: string };
  } = {};

  constructor() {
    // Providers
    this.hyperEvmProvider = new ethers.JsonRpcProvider(config.hyperEvmRpc);
    this.arbitrumProvider = new ethers.JsonRpcProvider(config.arbitrumRpc);

    // Wallets
    this.hyperEvmWallet = new ethers.Wallet(config.keeperPrivateKey, this.hyperEvmProvider);
    this.arbitrumWallet = new ethers.Wallet(config.keeperPrivateKey, this.arbitrumProvider);

    // Contracts
    this.hyperEvmVault = new ethers.Contract(
      config.hyperEvmVault,
      FundingCaptureVaultV2Abi,
      this.hyperEvmWallet
    );

    if (config.arbitrumCoordinator) {
      this.arbitrumCoordinator = new ethers.Contract(
        config.arbitrumCoordinator,
        DeltaCoordinatorAbi,
        this.arbitrumWallet
      );
    }

    if (config.arbitrumSpotVault) {
      this.arbitrumSpotVault = new ethers.Contract(
        config.arbitrumSpotVault,
        SpotLongVaultAbi,
        this.arbitrumWallet
      );
    }

    // Hyperliquid API Client
    this.hyperliquidClient = new HyperliquidClient();
  }

  /**
   * Keeper 시작
   */
  async start(): Promise<void> {
    logger.info('Keeper', '🚀 Starting Keeper Bot...', {
      vault: config.hyperEvmVault,
      coordinator: config.arbitrumCoordinator || 'Not configured',
      interval: config.scanIntervalMs,
    });

    console.log('🚀 Starting Keeper Bot...');
    console.log(`   HyperEVM Vault: ${config.hyperEvmVault}`);
    console.log(`   Arbitrum Coordinator: ${config.arbitrumCoordinator || 'Not configured'}`);
    console.log(`   Scan Interval: ${config.scanIntervalMs / 1000}s`);
    console.log('');

    this.isRunning = true;

    // Admin 서버 시작
    adminServer.start();

    // Initial status
    await this.printStatus();

    // Start monitoring loop
    while (this.isRunning) {
      try {
        await this.runCycle();
        // Admin 서버에 메트릭 업데이트
        adminServer.updateMetrics({
          market: this.latestMetrics.market,
          vault: this.latestMetrics.vault,
          wallet: this.latestMetrics.wallet,
        });
      } catch (error) {
        logger.error('Keeper', 'Error in keeper cycle', { error: String(error) });
        console.error('❌ Error in keeper cycle:', error);
      }

      // Wait for next cycle
      await this.sleep(config.scanIntervalMs);
    }
  }

  /**
   * Keeper 중지
   */
  stop(): void {
    logger.info('Keeper', '🛑 Stopping Keeper Bot...');
    console.log('🛑 Stopping Keeper Bot...');
    this.isRunning = false;
    adminServer.stop();
  }

  /**
   * 단일 사이클 실행
   */
  async runCycle(): Promise<void> {
    const timestamp = new Date().toISOString();
    console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    console.log(`📍 Keeper Cycle @ ${timestamp}`);
    console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);

    // 1. Funding Rate 확인
    await this.checkFundingRate();

    // 2. HyperEVM Vault 상태 확인
    await this.checkHyperEvmVault();

    // 3. Position Sync (Arbitrum이 설정된 경우)
    if (this.arbitrumCoordinator) {
      await this.syncPositions();
      await this.checkDelta();
    }
  }

  /**
   * Funding Rate 확인
   */
  async checkFundingRate(): Promise<void> {
    try {
      const marketData = await this.hyperliquidClient.getMarketData('ETH');
      const annualizedRate = marketData.fundingRate * 3 * 365 * 100;
      const isFavorable = marketData.fundingRate > config.minFundingRate;

      // 메트릭 저장
      this.latestMetrics.market = {
        ethFundingRate: marketData.fundingRate,
        ethMarkPrice: marketData.markPrice,
        ethOraclePrice: marketData.oraclePrice,
        annualizedApr: annualizedRate,
      };

      // 로깅
      logger.info('Market', 'ETH market data fetched', {
        fundingRate: marketData.fundingRate,
        markPrice: marketData.markPrice,
        apr: annualizedRate,
      });
      logger.metric('eth_funding_rate', marketData.fundingRate);
      logger.metric('eth_mark_price', marketData.markPrice);
      logger.metric('eth_apr', annualizedRate);

      console.log('\n📊 Market Data (ETH):');
      console.log(`   Funding Rate: ${(marketData.fundingRate * 100).toFixed(6)}%`);
      console.log(`   Mark Price:   $${marketData.markPrice.toFixed(2)}`);
      console.log(`   Oracle Price: $${marketData.oraclePrice.toFixed(2)}`);
      console.log(`   Open Interest: ${marketData.openInterest.toFixed(2)} ETH`);
      console.log(`   Status: ${isFavorable ? '✅ Favorable (Short pays)' : '⚠️ Unfavorable'}`);
      console.log(`   Annualized: ${annualizedRate.toFixed(2)}% APR`);

      // Funding Rate 경고
      if (!isFavorable) {
        logger.warn('Market', 'Funding rate unfavorable for short position', {
          rate: marketData.fundingRate,
          threshold: config.minFundingRate,
        });
      }

    } catch (error) {
      logger.error('Market', 'Failed to fetch funding rate', { error: String(error) });
      console.error('   ❌ Failed to fetch funding rate:', error);
    }
  }

  /**
   * HyperEVM Vault 상태 확인
   */
  async checkHyperEvmVault(): Promise<void> {
    try {
      const [state, spotValueUsd] = await Promise.all([
        this.hyperEvmVault.state(),
        this.hyperEvmVault.spotValueUsd(),
      ]);

      const stateNames = ['IDLE', 'ACTIVE', 'EXITING'];
      const stateName = stateNames[Number(state)] || 'UNKNOWN';
      const spotValue = Number(ethers.formatUnits(spotValueUsd, 6));

      let deltaRatioBps = 0;

      // Delta 계산 시도 (Precompile 필요)
      try {
        const [deltaUsd, ratio] = await this.hyperEvmVault.calculateDelta();
        deltaRatioBps = Number(ratio);
        console.log('\n🏦 HyperEVM Vault:');
        console.log(`   State: ${stateName}`);
        console.log(`   Spot Value: $${spotValue}`);
        console.log(`   Delta: $${ethers.formatUnits(deltaUsd, 6)}`);
        console.log(`   Delta Ratio: ${deltaRatioBps / 100}%`);
      } catch {
        console.log('\n🏦 HyperEVM Vault:');
        console.log(`   State: ${stateName}`);
        console.log(`   Spot Value: $${spotValue}`);
        console.log(`   Delta: N/A (precompile unavailable in fork)`);
      }

      // 메트릭 저장
      this.latestMetrics.vault = {
        state: stateName,
        spotValueUsd: spotValue,
        deltaRatioBps,
      };

      // 로깅
      logger.info('Vault', 'Vault state checked', {
        state: stateName,
        spotValue,
        deltaRatioBps,
      });
      logger.metric('vault_spot_value', spotValue);
      logger.metric('vault_delta_ratio', deltaRatioBps);

      // Delta 경고
      if (deltaRatioBps > config.deltaThresholdBps) {
        logger.warn('Vault', 'Delta exceeds threshold', {
          current: deltaRatioBps,
          threshold: config.deltaThresholdBps,
        });
      }

    } catch (error) {
      logger.error('Vault', 'Failed to fetch vault state', { error: String(error) });
      console.error('   ❌ Failed to fetch vault state:', error);
    }
  }

  /**
   * Position Sync: HyperEVM → Arbitrum
   */
  async syncPositions(): Promise<void> {
    if (!this.arbitrumCoordinator) {
      console.log('\n⏭️ Skipping position sync (Arbitrum not configured)');
      return;
    }

    try {
      console.log('\n🔄 Syncing positions to Arbitrum...');

      // Spot Value 조회
      const spotValueUsd = await this.hyperEvmVault.spotValueUsd();

      // Mark Price로 예상 Perp 수량 계산
      const markPrice = await this.hyperliquidClient.getMarkPrice('ETH');
      const perpShortSize = BigInt(Math.floor(
        Number(ethers.formatUnits(spotValueUsd, 6)) / markPrice * 1e18
      ));
      const perpValueUsd = spotValueUsd; // Delta neutral이므로 Spot = Perp

      console.log(`   Spot Value: $${ethers.formatUnits(spotValueUsd, 6)}`);
      console.log(`   Est. Perp Size: ${ethers.formatEther(perpShortSize)} ETH`);

      // Arbitrum에 동기화
      const tx = await this.arbitrumCoordinator.syncPerpPosition(
        perpShortSize,
        perpValueUsd
      );

      console.log(`   TX Hash: ${tx.hash}`);
      await tx.wait();
      console.log('   ✅ Position synced successfully');

    } catch (error) {
      console.error('   ❌ Failed to sync positions:', error);
    }
  }

  /**
   * Delta 확인 및 리밸런싱
   */
  async checkDelta(): Promise<void> {
    if (!this.arbitrumCoordinator) return;

    try {
      const needsRebalance = await this.arbitrumCoordinator.needsRebalance();

      if (needsRebalance) {
        console.log('\n⚠️ Delta exceeds threshold - Rebalancing needed!');

        const [deltaUsd, deltaRatioBps] = await this.arbitrumCoordinator.calculateDelta();
        console.log(`   Delta: $${ethers.formatUnits(deltaUsd, 6)}`);
        console.log(`   Delta Ratio: ${Number(deltaRatioBps) / 100}%`);

        // 자동 리밸런싱은 위험하므로 알림만
        console.log('   ℹ️ Manual rebalancing recommended');

        // TODO: 텔레그램 알림 전송
      } else {
        console.log('\n✅ Delta within acceptable range');
      }

    } catch (error) {
      console.error('   ❌ Failed to check delta:', error);
    }
  }

  /**
   * 현재 상태 출력
   */
  async printStatus(): Promise<void> {
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📋 KEEPER STATUS');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Wallet balances
    try {
      const hyperEvmBalance = await this.hyperEvmProvider.getBalance(this.hyperEvmWallet.address);
      const arbitrumBalance = await this.arbitrumProvider.getBalance(this.arbitrumWallet.address);

      const hypeBalance = ethers.formatEther(hyperEvmBalance);
      const ethBalance = ethers.formatEther(arbitrumBalance);

      // 메트릭 저장
      this.latestMetrics.wallet = {
        hyperEvmBalance: hypeBalance,
        arbitrumBalance: ethBalance,
      };

      logger.info('Wallet', 'Balances fetched', {
        address: this.hyperEvmWallet.address,
        hype: hypeBalance,
        eth: ethBalance,
      });

      console.log(`\n👛 Keeper Wallet: ${this.hyperEvmWallet.address}`);
      console.log(`   HyperEVM Balance: ${hypeBalance} HYPE`);
      console.log(`   Arbitrum Balance: ${ethBalance} ETH`);
    } catch (error) {
      logger.error('Wallet', 'Failed to fetch balances', { error: String(error) });
      console.error('Failed to fetch balances:', error);
    }

    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  /**
   * 수동 리밸런싱 실행
   */
  async executeRebalance(minAmountOut: bigint = 0n): Promise<void> {
    if (!this.arbitrumCoordinator) {
      throw new Error('Arbitrum coordinator not configured');
    }

    console.log('🔧 Executing rebalance...');

    const tx = await this.arbitrumCoordinator.executeRebalance(minAmountOut);
    console.log(`   TX Hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`   ✅ Rebalance completed in block ${receipt.blockNumber}`);
  }

  /**
   * HyperEVM에서 Short 포지션 오픈
   */
  async openShort(sizeWei: bigint, maxSlippageBps: number = 50): Promise<void> {
    console.log('📈 Opening short position...');
    console.log(`   Size: ${ethers.formatEther(sizeWei)} ETH`);
    console.log(`   Max Slippage: ${maxSlippageBps / 100}%`);

    const tx = await this.hyperEvmVault.openShort(sizeWei, maxSlippageBps);
    console.log(`   TX Hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`   ✅ Short opened in block ${receipt.blockNumber}`);
  }

  /**
   * HyperEVM에서 Short 포지션 클로즈
   */
  async closeShort(): Promise<void> {
    console.log('📉 Closing short position...');

    const tx = await this.hyperEvmVault.closeShort();
    console.log(`   TX Hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`   ✅ Short closed in block ${receipt.blockNumber}`);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
