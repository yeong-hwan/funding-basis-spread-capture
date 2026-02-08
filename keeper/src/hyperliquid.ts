import { config } from './config';

/**
 * Hyperliquid API 클라이언트
 * Funding Rate 및 포지션 정보 조회
 */

interface FundingData {
  coin: string;
  fundingRate: string;
  premium: string;
  time: number;
}

interface AssetCtx {
  funding: string;
  openInterest: string;
  prevDayPx: string;
  dayNtlVlm: string;
  premium: string;
  oraclePx: string;
  markPx: string;
}

interface MetaAndAssetCtx {
  universe: Array<{ name: string; szDecimals: number }>;
  assetCtxs: AssetCtx[];
}

export class HyperliquidClient {
  private baseUrl: string;

  constructor() {
    this.baseUrl = config.hyperliquidApiUrl;
  }

  /**
   * 현재 Funding Rate 조회
   */
  async getFundingRate(coin: string = 'ETH'): Promise<number> {
    try {
      const response = await fetch(`${this.baseUrl}/info`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'metaAndAssetCtxs' }),
      });

      const data = (await response.json()) as MetaAndAssetCtx[];

      if (!data || data.length < 2) {
        throw new Error('Invalid response from Hyperliquid API');
      }

      const meta = data[0];
      const assetCtxs = data[1] as unknown as AssetCtx[];

      // Find ETH index
      const coinIndex = meta.universe.findIndex(
        (asset) => asset.name.toUpperCase() === coin.toUpperCase()
      );

      if (coinIndex === -1) {
        throw new Error(`Coin ${coin} not found`);
      }

      const assetCtx = assetCtxs[coinIndex];
      return parseFloat(assetCtx.funding);
    } catch (error) {
      console.error('Error fetching funding rate:', error);
      throw error;
    }
  }

  /**
   * Mark Price 조회
   */
  async getMarkPrice(coin: string = 'ETH'): Promise<number> {
    try {
      const response = await fetch(`${this.baseUrl}/info`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'metaAndAssetCtxs' }),
      });

      const data = (await response.json()) as MetaAndAssetCtx[];

      if (!data || data.length < 2) {
        throw new Error('Invalid response from Hyperliquid API');
      }

      const meta = data[0];
      const assetCtxs = data[1] as unknown as AssetCtx[];

      const coinIndex = meta.universe.findIndex(
        (asset) => asset.name.toUpperCase() === coin.toUpperCase()
      );

      if (coinIndex === -1) {
        throw new Error(`Coin ${coin} not found`);
      }

      return parseFloat(assetCtxs[coinIndex].markPx);
    } catch (error) {
      console.error('Error fetching mark price:', error);
      throw error;
    }
  }

  /**
   * Oracle Price 조회
   */
  async getOraclePrice(coin: string = 'ETH'): Promise<number> {
    try {
      const response = await fetch(`${this.baseUrl}/info`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'metaAndAssetCtxs' }),
      });

      const data = (await response.json()) as MetaAndAssetCtx[];

      if (!data || data.length < 2) {
        throw new Error('Invalid response from Hyperliquid API');
      }

      const meta = data[0];
      const assetCtxs = data[1] as unknown as AssetCtx[];

      const coinIndex = meta.universe.findIndex(
        (asset) => asset.name.toUpperCase() === coin.toUpperCase()
      );

      if (coinIndex === -1) {
        throw new Error(`Coin ${coin} not found`);
      }

      return parseFloat(assetCtxs[coinIndex].oraclePx);
    } catch (error) {
      console.error('Error fetching oracle price:', error);
      throw error;
    }
  }

  /**
   * Funding Rate이 양수인지 확인 (Short에 유리)
   */
  async isFundingFavorable(coin: string = 'ETH'): Promise<boolean> {
    const fundingRate = await this.getFundingRate(coin);
    return fundingRate > config.minFundingRate;
  }

  /**
   * 전체 시장 데이터 조회
   */
  async getMarketData(coin: string = 'ETH'): Promise<{
    fundingRate: number;
    markPrice: number;
    oraclePrice: number;
    openInterest: number;
  }> {
    const response = await fetch(`${this.baseUrl}/info`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'metaAndAssetCtxs' }),
    });

    const data = (await response.json()) as MetaAndAssetCtx[];

    if (!data || data.length < 2) {
      throw new Error('Invalid response from Hyperliquid API');
    }

    const meta = data[0];
    const assetCtxs = data[1] as unknown as AssetCtx[];

    const coinIndex = meta.universe.findIndex(
      (asset) => asset.name.toUpperCase() === coin.toUpperCase()
    );

    if (coinIndex === -1) {
      throw new Error(`Coin ${coin} not found`);
    }

    const ctx = assetCtxs[coinIndex];

    return {
      fundingRate: parseFloat(ctx.funding),
      markPrice: parseFloat(ctx.markPx),
      oraclePrice: parseFloat(ctx.oraclePx),
      openInterest: parseFloat(ctx.openInterest),
    };
  }
}
