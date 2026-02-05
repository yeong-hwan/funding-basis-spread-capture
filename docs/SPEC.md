# Funding/Basis Spread Capture - 기능 명세서

## 1. 전략 개요

### 1.1 핵심 컨셉

**Funding/Basis Spread Capture**는 델타 뉴트럴 전략으로:
- 같은 자산을 **현물로 보유 (Spot Long)**
- 같은 자산을 **Perpetual 선물로 동일 가치만큼 숏 (Perp Short, 1x, Cross)**
- 가격 변동은 상쇄되고 **Funding Fee만 수익으로 획득**

### 1.2 포지션 구성

| 구분 | 플랫폼 | 설명 |
|------|--------|------|
| **Spot Long** | Arbitrum DEX (Uniswap 등) | 현물 자산 보유 |
| **Perp Short** | Hyperliquid | 1x 레버리지, Cross 마진 |

### 1.3 왜 Arbitrum + Hyperliquid?

- **Arbitrum**: 이더리움 L2, 가스비 절감 (Funding 수익률에 가장 큰 영향)
- **Hyperliquid**: 온체인 Perp DEX, API 지원

---

## 2. 핵심 공식

### 2.1 Funding Fee

```
Funding Rate = clamp(
    EMA(Premium Index) + Interest Rate,
    MinRate,
    MaxRate
)

Premium Index = (Perp Price − Index Price) / Index Price
Funding Payment = Position Notional × Funding Rate
```

- **Perp > Spot** → Long이 Short에게 지급 (우리가 수익)
- **Perp < Spot** → Short가 Long에게 지급 (손실)
- **전략은 Funding Rate > 0 인 경우에만 유의미**

### 2.2 Delta (ε)

```
SpotUSD = SpotQty × SpotPrice
PerpUSD = |PerpQty| × PerpMarkPrice
DeltaUSD = SpotUSD − PerpUSD

목표: DeltaUSD ≈ 0
```

### 2.3 Delta Ratio

```
DeltaRatio = |DeltaUSD| / SpotUSD
```

- `DeltaRatio ≤ ε` → 유지
- `DeltaRatio > ε` → 리밸런싱 (ε = 3~5%)

---

## 3. 기능 요구사항

### 3.1 Vault (자금 관리)

#### Deposit
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| V-D1 | User Deposit | 시스템은 사용자가 Vault에 자산을 예치할 수 있도록 허용해야 한다 | |
| V-D2 | Deposit Handling | 시스템은 예치된 자산을 즉시 포지션에 사용하지 않고 대기 상태로 보관해야 한다 | |
| V-D3 | Deposit State | 시스템은 예치 직후 Vault 상태를 Idle로 설정해야 한다 | |

#### State
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| V-S1 | Idle → Active | Funding 조건이 충족될 경우 시스템은 Vault 상태를 Active로 변경해야 한다 | |
| V-S2 | Active → Idle | Funding Fee가 0 이하로 전환될 경우 시스템은 포지션을 정리하고 Idle 상태로 전환해야 한다 | |
| V-S3 | Transition Lock | 시스템은 상태 전환 중 중복 포지션 생성을 방지해야 한다 | |

#### Withdrawal
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| V-W1 | Withdraw Request | 시스템은 사용자가 출금을 요청할 수 있도록 허용해야 한다 | |
| V-W2 | Position Unwind | 출금 요청 시 시스템은 Perp 포지션을 우선적으로 정리해야 한다 | |
| V-W3 | Asset Return | 시스템은 출금 완료 후 사용자의 자산을 반환해야 한다 | |

### 3.2 Strategy (전략 로직)

#### Allocation
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| S-A1 | Funding Scan | 시스템은 지원 거래소들의 Funding Fee를 주기적으로 조회해야 한다 | Interval 기반 |
| S-A2 | Allocation Filter | 시스템은 Funding Fee가 양수이고 임계값 이상인 거래소만 후보로 선정해야 한다 | X, T 파라미터 |
| S-A3 | Single Allocation | 시스템은 하나의 거래소에만 자산을 배분해야 한다 | |
| S-A4 | No Valid Venue | Funding 조건을 만족하는 거래소가 없을 경우 시스템은 Vault를 Idle 상태로 유지해야 한다 | Pause |

### 3.3 Position (포지션 관리)

#### Entry
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| P-E1 | Position Entry | Funding 조건이 충족될 경우 시스템은 포지션을 생성해야 한다 | Delta Neutral (±ε 허용) |
| P-E2 | Spot Long | 시스템은 현물 시장에서 자산을 매수해야 한다 | |
| P-E3 | Perp Short | 시스템은 동일 자산에 대해 Perp Short 포지션을 생성해야 한다 | 1x 레버리지 제한 |

#### Rebalancing
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| P-R1 | Delta Check | 시스템은 Spot과 Perp 포지션 간 델타를 주기적으로 계산해야 한다 | `DeltaUSD = SpotUSD − PerpUSD` |
| P-R2 | Rebalance Trigger | 델타가 허용 범위를 초과할 경우 시스템은 리밸런싱을 수행해야 한다 | Perp만 조정, 브릿지 미사용 |

### 3.4 Risk (리스크 관리)

#### Control
| ID | 항목 | 요구사항 | 비고 |
|----|------|----------|------|
| R-C1 | Funding Guard | 시스템은 Funding Fee가 음수일 경우 신규 포지션 생성을 제한해야 한다 | |
| R-C2 | Volatility Guard | 급격한 가격 변동 시 시스템은 Perp 포지션을 축소할 수 있어야 한다 | |
| R-C3 | ADL Awareness | 시스템은 ADL 발생 가능성을 고려한 포지션 크기 제한 규칙을 적용해야 한다 | |

---

## 4. 리밸런싱 상세

### 4.1 기본 원칙

- **Spot = Anchor** (고정)
- **Perp Short 수량만 조정**
- 체인/거래소 간 이동 없음

### 4.2 목표 Perp 수량

```
TargetPerpQty = SpotUSD / PerpMarkPrice
TargetQp = −TargetPerpQty

AdjustQty = TargetQp − CurrentQp
```

### 4.3 리밸런싱 제약

- 최소 주문 수량 미만 조정 금지
- 최대 조정 비율 제한 (예: 기존 Perp 수량의 20%)

### 4.4 추가 트리거

| 트리거 | 조건 | 조치 |
|--------|------|------|
| 가격 급변 | `\|ΔPrice\| > θ%` (짧은 시간) | Perp Short 부분 축소, ε 일시 확대 |
| Funding 구조 변화 | `Funding > 0` but `Funding < X` | Exit 또는 축소 판단 |
| 유동성/슬리피지 | `예상 슬리피지 > S_max` | 리밸런싱 스킵 |

---

## 5. 상태 다이어그램

```
[Deposit] → [Idle] ←→ [Active]
                ↓
           [Withdrawal]
```

| 상태 | 설명 |
|------|------|
| **Idle** | 포지션 없음, 자금 대기 중 |
| **Active** | 포지션 활성화, Funding 수취 중 |

---

## 6. 파라미터

| 파라미터 | 설명 | 예시 값 |
|----------|------|---------|
| `ε` (epsilon) | Delta 허용 범위 | 3~5% |
| `T` | Funding Rate 임계값 | TBD |
| `X` | 최소 Funding Rate | TBD |
| `θ` | 가격 급변 임계값 | TBD |
| `S_max` | 최대 허용 슬리피지 | TBD |
| Scan Interval | Funding 조회 주기 | TBD |

---

## 7. 참고 자료

- [Hyperliquid Docs](https://hyperliquid.gitbook.io/hyperliquid-docs)
- [디젠들은 하락장에도 계속 행복할 권리가 있다 - A41](https://medium.a41.io/investment-디젠들은-하락장에도-계속-행복할-권리가-있다-ea2cfb7cc48b)
- [AMM Delta-neutral 전략 Deep Dive](https://medium.com/@everything-numbers/amm-delta-neutral-전략-deep-dive-3cdd794ffb31)
- [ERC-4626 알아보기](https://medium.com/@aiden.p/erc-4626-알아보기-8ed6d514e22e)
