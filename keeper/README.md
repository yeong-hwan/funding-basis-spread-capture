# Keeper 운영 가이드

Delta Neutral 전략의 자동화를 위한 Keeper 시스템 가이드입니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                        Keeper Bot                           │
│  (Off-chain: TypeScript/Python)                            │
│                                                             │
│  1. HyperEVM에서 Perp Position 조회                         │
│  2. Arbitrum에서 Spot Position 조회                         │
│  3. Delta 계산                                              │
│  4. 리밸런싱 필요시 트랜잭션 실행                            │
└─────────────────────────────────────────────────────────────┘
        │                                    │
        ▼                                    ▼
┌───────────────────┐              ┌───────────────────┐
│    HyperEVM       │              │    Arbitrum       │
│ FundingCapture    │              │  SpotLongVault    │
│    VaultV2        │              │  DeltaCoordinator │
│ - Perp Short      │              │  - Spot Long      │
│ - openShort()     │              │  - buyEth()       │
│ - closeShort()    │              │  - sellEth()      │
│ - rebalance()     │              │  - rebalance()    │
└───────────────────┘              └───────────────────┘
```

## Keeper 주요 기능

### 1. Position Sync (5분마다)

HyperEVM의 Perp Position을 Arbitrum의 DeltaCoordinator에 동기화:

```javascript
// Pseudo-code
const perpPosition = await hyperEvmVault.getPerpPosition();
const perpValue = calculatePerpValueUsd(perpPosition);

await deltaCoordinator.syncPerpPosition(
  perpPosition.szi,
  perpValue
);
```

### 2. Delta Check & Rebalance (5분마다)

```javascript
const needsRebalance = await deltaCoordinator.needsRebalance();

if (needsRebalance) {
  // Calculate optimal swap amount
  const { deltaUsd, deltaRatioBps } = await deltaCoordinator.calculateDelta();

  // Execute rebalance on appropriate chain
  if (deltaUsd > 0) {
    // Spot > Perp: Sell ETH on Arbitrum OR Add Short on HyperEVM
  } else {
    // Spot < Perp: Buy ETH on Arbitrum OR Reduce Short on HyperEVM
  }
}
```

### 3. Funding Rate Monitor (1시간마다)

```javascript
// Check if funding rate is favorable
const fundingRate = await getFundingRate('ETH');

if (fundingRate < MIN_FUNDING_THRESHOLD) {
  // Consider closing position
  alert('Funding rate below threshold');
}
```

## 환경 변수

```env
# Keeper Wallet
KEEPER_PRIVATE_KEY=0x...

# RPC Endpoints
HYPEREVM_RPC=https://rpc.hyperliquid.xyz/evm
ARBITRUM_RPC=https://arb1.arbitrum.io/rpc

# Contract Addresses
HYPEREVM_VAULT=0x...
ARBITRUM_SPOT_VAULT=0x...
ARBITRUM_COORDINATOR=0x...

# Thresholds
DELTA_THRESHOLD_BPS=500
MIN_FUNDING_RATE=0.0001
MIN_REBALANCE_INTERVAL=300

# Alerts (optional)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

## 실행

```bash
# TypeScript Keeper
npm install
npm run keeper

# 또는 Docker
docker-compose up keeper
```

## 모니터링

### 주요 지표

1. **Delta Ratio** - 5% 이하 유지
2. **Funding Rate** - 양수 유지 (Short에 유리)
3. **Position Size** - Spot ≈ Perp
4. **Gas Cost** - 리밸런싱 비용 추적

### 알림 조건

- Delta > 5%
- Funding Rate < 0
- 트랜잭션 실패
- 가격 급변 (>10% in 1h)

## 리스크 관리

1. **Slippage**: 0.5% 이하로 제한
2. **Gas Spike**: 가스 가격 상한선 설정
3. **Oracle Lag**: 가격 staleness 체크 (1시간)
4. **Position Limit**: 최대 포지션 크기 제한

## 수동 개입 필요 상황

1. 급격한 시장 변동
2. 체인 장애
3. 스마트 컨트랙트 업그레이드
4. 전략 파라미터 조정
