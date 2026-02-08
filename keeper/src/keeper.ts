import { ethers } from 'ethers';
import { config } from './config';
import { FundingCaptureVaultV2Abi, DeltaCoordinatorAbi, SpotLongVaultAbi } from './abis';
import { HyperliquidClient } from './hyperliquid';

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
    console.log('🚀 Starting Keeper Bot...');
    console.log(`   HyperEVM Vault: ${config.hyperEvmVault}`);
    console.log(`   Arbitrum Coordinator: ${config.arbitrumCoordinator || 'Not configured'}`);
    console.log(`   Scan Interval: ${config.scanIntervalMs / 1000}s`);
    console.log('');

    this.isRunning = true;

    // Initial status
    await this.printStatus();

    // Start monitoring loop
    while (this.isRunning) {
      try {
        await this.runCycle();
      } catch (error) {
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
    console.log('🛑 Stopping Keeper Bot...');
    this.isRunning = false;
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

      console.log('\n📊 Market Data (ETH):');
      console.log(`   Funding Rate: ${(marketData.fundingRate * 100).toFixed(6)}%`);
      console.log(`   Mark Price:   $${marketData.markPrice.toFixed(2)}`);
      console.log(`   Oracle Price: $${marketData.oraclePrice.toFixed(2)}`);
      console.log(`   Open Interest: ${marketData.openInterest.toFixed(2)} ETH`);

      // Funding Rate 체크
      const isFavorable = marketData.fundingRate > config.minFundingRate;
      console.log(`   Status: ${isFavorable ? '✅ Favorable (Short pays)' : '⚠️ Unfavorable'}`);

      // 연 환산 수익률
      const annualizedRate = marketData.fundingRate * 3 * 365 * 100; // 8시간마다 3번
      console.log(`   Annualized: ${annualizedRate.toFixed(2)}% APR`);

    } catch (error) {
      console.error('   ❌ Failed to fetch funding rate:', error);
    }
  }

  /**
   * HyperEVM Vault 상태 확인
   */
  async checkHyperEvmVault(): Promise<void> {
    try {
      const [state, spotValueUsd, perpShortSize] = await Promise.all([
        this.hyperEvmVault.state(),
        this.hyperEvmVault.spotValueUsd(),
        this.hyperEvmVault.perpShortSizeWei(),
      ]);

      const stateNames = ['IDLE', 'ACTIVE', 'EXITING'];

      console.log('\n🏦 HyperEVM Vault:');
      console.log(`   State: ${stateNames[Number(state)] || 'UNKNOWN'}`);
      console.log(`   Spot Value: $${ethers.formatUnits(spotValueUsd, 6)}`);
      console.log(`   Perp Short: ${ethers.formatEther(perpShortSize)} ETH`);

      // Delta 계산 시도
      try {
        const [deltaUsd, deltaRatioBps] = await this.hyperEvmVault.calculateDelta();
        console.log(`   Delta: $${ethers.formatUnits(deltaUsd, 6)}`);
        console.log(`   Delta Ratio: ${Number(deltaRatioBps) / 100}%`);
      } catch {
        console.log(`   Delta: N/A (precompile unavailable)`);
      }

    } catch (error) {
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

      // HyperEVM에서 포지션 조회
      const perpShortSize = await this.hyperEvmVault.perpShortSizeWei();

      // Mark Price로 USD 가치 계산
      const markPrice = await this.hyperliquidClient.getMarkPrice('ETH');
      const perpValueUsd = BigInt(Math.floor(
        Number(ethers.formatEther(perpShortSize)) * markPrice * 1e6
      ));

      console.log(`   Perp Short Size: ${ethers.formatEther(perpShortSize)} ETH`);
      console.log(`   Perp Value USD: $${ethers.formatUnits(perpValueUsd, 6)}`);

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

      console.log(`\n👛 Keeper Wallet: ${this.hyperEvmWallet.address}`);
      console.log(`   HyperEVM Balance: ${ethers.formatEther(hyperEvmBalance)} HYPE`);
      console.log(`   Arbitrum Balance: ${ethers.formatEther(arbitrumBalance)} ETH`);
    } catch (error) {
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
