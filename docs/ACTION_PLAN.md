# Funding/Basis Spread Capture - Solidity 액션플랜

> **구현 방식**: HyperEVM 컨트랙트 (CoreWriter 직접 호출)
> **타겟 자산**: ETH
> **환경**: 테스트넷

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                        HyperEVM (Hyperliquid L1)                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  FundingCaptureVault                     │    │
│  │  - deposit(USDC)                                        │    │
│  │  - openPosition() → CoreWriter.placeOrder(SHORT)        │    │
│  │  - rebalance() → CoreWriter.modifyOrder()               │    │
│  │  - closePosition() → CoreWriter.closeOrder()            │    │
│  │  - withdraw()                                           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  CoreWriter (0x333...333)                               │    │
│  │  - sendRawAction(bytes) → HyperCore                     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Precompiles (0x800~0x807)                              │    │
│  │  - Oracle Price                                         │    │
│  │  - Position Info                                        │    │
│  │  - Funding Rate                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘

Note: Spot Long은 별도 체인(Arbitrum)이므로
      이 Vault는 Perp Short만 담당.
      Spot은 수동 또는 별도 컨트랙트로 관리.
```

---

## Phase 1: HyperEVM 인터페이스 구현 (Day 1-2)

### 1.1 CoreWriter 인터페이스

```solidity
// src/interfaces/ICoreWriter.sol
interface ICoreWriter {
    function sendRawAction(bytes calldata data) external;
}
```

### 1.2 Precompile 인터페이스

```solidity
// src/interfaces/IHyperLiquidPrecompiles.sol
- getOraclePrice(uint32 assetId) → uint64
- getPosition(address account, uint32 assetId) → Position
- getFundingRate(uint32 assetId) → int64
```

### 1.3 Action Encoding 라이브러리

```solidity
// src/libraries/HyperLiquidActions.sol
- encodeLimitOrder(asset, isBuy, price, size, reduceOnly, tif)
- encodeMarketOrder(asset, isBuy, size, reduceOnly)
- encodeCancelOrder(asset, orderId)
- encodeUsdTransfer(amount, toPerp)
```

---

## Phase 2: Vault 컨트랙트 리팩토링 (Day 2-3)

### 2.1 FundingCaptureVault 핵심 기능

| 함수 | 설명 |
|------|------|
| `deposit(uint256 amount)` | USDC 예치 |
| `withdraw(uint256 shares)` | 출금 요청 |
| `openShort(uint256 size)` | ETH Perp Short 진입 |
| `closeShort()` | Short 포지션 청산 |
| `rebalance()` | Delta 조정 |
| `getPosition()` | 현재 포지션 조회 |
| `getDelta()` | Delta 계산 |

### 2.2 상태 관리

```solidity
enum VaultState { IDLE, ACTIVE, EXITING }

struct Position {
    int256 perpQty;      // Perp Short 수량 (음수)
    uint256 entryPrice;  // 진입가
    uint256 timestamp;   // 진입 시각
}
```

---

## Phase 3: 테스트넷 배포 (Day 3-4)

### 3.1 HyperEVM 테스트넷 정보

| 항목 | 값 |
|------|-----|
| Chain ID | 998 |
| RPC | https://rpc.hyperliquid-testnet.xyz/evm |
| Faucet | Hyperliquid Discord #testnet-faucet |
| Explorer | https://explorer.hyperliquid-testnet.xyz |

**메인넷 정보 (참고용):**
| 항목 | 값 |
|------|-----|
| Chain ID | 999 |
| RPC | https://rpc.hyperliquid.xyz/evm |

### 3.2 배포 스크립트

```bash
# script/Deploy.s.sol
forge script script/Deploy.s.sol --rpc-url $HYPEREVM_RPC --broadcast
```

---

## Phase 4: 테스트 (Day 4-5)

### 4.1 Unit Tests

- [ ] CoreWriter action encoding
- [ ] Precompile data parsing
- [ ] Vault state transitions
- [ ] Delta calculation

### 4.2 Integration Tests (테스트넷)

- [ ] Deposit → Open Short → Close → Withdraw 플로우
- [ ] Rebalance 트리거
- [ ] Funding Rate 조회

---

## 핵심 컨트랙트 주소

| 컨트랙트 | 주소 | 네트워크 |
|----------|------|----------|
| CoreWriter | `0x3333333333333333333333333333333333333333` | HyperEVM |
| Oracle Precompile | `0x0000000000000000000000000000000000000807` | HyperEVM |
| Precompile Base | `0x0000000000000000000000000000000000000800` | HyperEVM |

---

## 파일 구조

```
src/
├── FundingCaptureVault.sol      # 메인 Vault
├── interfaces/
│   ├── ICoreWriter.sol          # CoreWriter 인터페이스
│   └── IHyperLiquidPrecompiles.sol
├── libraries/
│   ├── HyperLiquidActions.sol   # Action encoding
│   └── HyperLiquidDecoder.sol   # Precompile decoding
└── foundry/
    └── Vm.sol                   # Foundry helpers

script/
├── Deploy.s.sol                 # 배포 스크립트
└── Interactions.s.sol           # 테스트 인터랙션

test/
├── FundingCaptureVault.t.sol    # Vault 테스트
└── HyperLiquidActions.t.sol     # 인코딩 테스트
```

---

## 제약 사항 & 고려 사항

1. **CoreWriter 딜레이**: 주문 실행 몇 초 지연 (프론트러닝 방지)
2. **크로스체인 미지원**: Arbitrum Spot은 별도 관리 필요
3. **테스트넷 한정**: 메인넷 배포 전 충분한 테스트 필수
4. **가스 최적화**: Action encoding 효율화 필요

---

## 다음 단계

1. ✅ CLAUDE.md 업데이트
2. ✅ HyperEVM 인터페이스 구현 (ICoreWriter, IHyperLiquidPrecompiles)
3. ✅ HyperLiquidActions 라이브러리 구현
4. ✅ FundingCaptureVault 구현
5. ✅ Unit 테스트 (6개 통과)
6. ✅ 테스트넷 설정 및 배포 스크립트
7. 🔄 테스트넷 배포 및 통합 테스트
8. ⏳ Arbitrum Spot Long 컨트랙트
9. ⏳ 크로스체인 통합
