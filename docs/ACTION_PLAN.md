# Funding/Basis Spread Capture - 핵심 액션플랜

> **목표**: Hyperliquid에서 Perp Short + Arbitrum에서 Spot Long으로 Delta Neutral 포지션 구축

---

## Phase 0: 환경 설정 (1일)

### 0.1 Hyperliquid 계정 준비
- [ ] Hyperliquid 계정 생성 및 API Key 발급
- [ ] API Key 권한 설정: `Trade`, `Read` (Withdraw 제외)
- [ ] 테스트넷에서 API 연동 테스트

### 0.2 Arbitrum 지갑 준비
- [ ] 전용 지갑 생성 (새 Private Key)
- [ ] Arbitrum 네트워크 설정
- [ ] ETH (가스비용) + USDC 준비

### 0.3 개발 환경
- [ ] Python 3.11+ 또는 TypeScript 환경 구성
- [ ] 필수 라이브러리: `hyperliquid-python-sdk`, `web3.py`, `ccxt`

---

## Phase 1: 데이터 수집 모듈 (2-3일)

### 1.1 Funding Rate 조회 (핵심)
```
목표: Hyperliquid Funding Rate 실시간 모니터링
```

**구현 항목:**
- [ ] Hyperliquid API 연동
  - `GET /info` → Funding Rate 조회
  - WebSocket 구독 → 실시간 업데이트
- [ ] Funding Rate 데이터 구조
  ```python
  {
    "asset": "ETH",
    "funding_rate": 0.0001,  # 0.01%
    "next_funding_time": 1234567890,
    "mark_price": 3000.0,
    "index_price": 2998.5
  }
  ```
- [ ] 주기적 스캔 (5분 간격)

### 1.2 가격 데이터 조회
- [ ] Hyperliquid Mark Price / Index Price
- [ ] Arbitrum DEX 현물 가격 (Uniswap V3 Pool)
- [ ] 가격 차이 (Basis) 계산

---

## Phase 2: 포지션 진입 로직 (3-4일)

### 2.1 진입 조건 체크
```python
def should_enter():
    return (
        funding_rate > MIN_FUNDING_THRESHOLD  # 예: 0.01%
        and vault_state == "IDLE"
        and available_balance > MIN_POSITION_SIZE
    )
```

### 2.2 Spot Long 실행 (Arbitrum)
- [ ] Uniswap V3 Router 연동
- [ ] USDC → ETH 스왑 트랜잭션
- [ ] 슬리피지 제한 설정 (0.5%)
- [ ] 트랜잭션 확인 대기

### 2.3 Perp Short 실행 (Hyperliquid)
- [ ] 시장가 또는 지정가 숏 주문
- [ ] 레버리지 1x 고정
- [ ] Cross 마진 설정
- [ ] **Spot Notional = Perp Notional** 맞추기

### 2.4 진입 순서
```
1. Funding Rate 확인 → 조건 충족
2. Spot Long 먼저 실행 (Arbitrum)
3. Spot 체결 확인
4. Perp Short 실행 (Hyperliquid)
5. Delta 검증 → |DeltaRatio| < ε
```

---

## Phase 3: 리밸런싱 로직 (2-3일)

### 3.1 Delta 모니터링
```python
def calculate_delta():
    spot_usd = spot_qty * spot_price
    perp_usd = abs(perp_qty) * perp_mark_price
    delta_usd = spot_usd - perp_usd
    delta_ratio = abs(delta_usd) / spot_usd
    return delta_ratio
```

### 3.2 리밸런싱 트리거
- [ ] `delta_ratio > EPSILON` (예: 5%) 시 리밸런싱
- [ ] **Perp 수량만 조정** (Spot 고정)

### 3.3 리밸런싱 실행
```python
def rebalance():
    target_perp_qty = spot_usd / perp_mark_price
    adjust_qty = target_perp_qty - abs(current_perp_qty)

    if adjust_qty > 0:
        # Perp Short 추가
        place_order("SELL", adjust_qty)
    else:
        # Perp Short 축소
        place_order("BUY", abs(adjust_qty))
```

---

## Phase 4: 리스크 관리 (2일)

### 4.1 Funding Guard
```python
def funding_guard():
    if funding_rate <= 0:
        return "BLOCK_NEW_POSITION"
    if funding_rate < EXIT_THRESHOLD:
        return "CONSIDER_EXIT"
    return "OK"
```

### 4.2 Volatility Guard
- [ ] 가격 변동률 모니터링
- [ ] `|price_change_1h| > 10%` → Perp 부분 청산 고려

### 4.3 포지션 청산 (Exit)
```
조건:
- Funding Rate < 0 지속
- 가격 급변
- 수동 Exit 요청

순서:
1. Perp Short 청산 (Hyperliquid)
2. Spot Long 매도 (Arbitrum) → USDC 전환
```

---

## Phase 5: 상태 관리 (1-2일)

### 5.1 Vault State Machine
```
IDLE → (enter) → ACTIVE
ACTIVE → (exit) → IDLE
ACTIVE → (rebalance) → ACTIVE
```

### 5.2 State 저장
- [ ] SQLite 또는 JSON 파일
- [ ] 포지션 정보 저장
  ```json
  {
    "state": "ACTIVE",
    "spot_qty": 1.5,
    "spot_entry_price": 3000,
    "perp_qty": -1.5,
    "perp_entry_price": 3002,
    "last_rebalance": "2024-01-01T00:00:00Z"
  }
  ```

---

## 핵심 API 엔드포인트

### Hyperliquid
| 용도 | 엔드포인트 |
|------|------------|
| Funding Rate | `GET /info` → `fundingRates` |
| 포지션 조회 | `POST /info` → `userState` |
| 주문 실행 | `POST /exchange` → `order` |
| 잔고 조회 | `POST /info` → `userState` |

### Arbitrum (Uniswap V3)
| 용도 | 컨트랙트 |
|------|----------|
| Swap | SwapRouter `0xE592...` |
| 가격 조회 | Quoter `0xb27...` |
| Pool 조회 | Factory → getPool |

---

## 최소 기능 (MVP) 체크리스트

**필수 (Week 1-2):**
- [ ] Hyperliquid Funding Rate 조회
- [ ] Hyperliquid Perp Short 주문/조회
- [ ] Arbitrum Spot Long (Uniswap Swap)
- [ ] Delta 계산 및 로깅
- [ ] 기본 진입/청산 로직

**보류 (MVP 이후):**
- ~~Vault 컨트랙트 (ERC-4626)~~ → 수동 자금 관리로 시작
- ~~다중 거래소 지원~~ → Hyperliquid만
- ~~자동 리밸런싱~~ → 수동/알림 기반으로 시작
- ~~ADL 대응~~ → 포지션 크기 제한으로 회피

---

## 디렉토리 구조 (제안)

```
funding-basis-spread-capture/
├── docs/
│   ├── SPEC.md              # 기능 명세
│   └── ACTION_PLAN.md       # 액션플랜 (이 문서)
├── src/
│   ├── config.py            # 설정값
│   ├── hyperliquid/
│   │   ├── client.py        # API 클라이언트
│   │   ├── funding.py       # Funding Rate 조회
│   │   └── trading.py       # 주문 실행
│   ├── arbitrum/
│   │   ├── client.py        # Web3 클라이언트
│   │   └── uniswap.py       # Swap 실행
│   ├── strategy/
│   │   ├── delta.py         # Delta 계산
│   │   ├── entry.py         # 진입 로직
│   │   ├── rebalance.py     # 리밸런싱
│   │   └── exit.py          # 청산 로직
│   └── main.py              # 메인 루프
├── tests/
└── .env                     # API Keys (gitignore)
```

---

## 리스크 체크리스트

| 리스크 | 대응 |
|--------|------|
| Funding Rate 음수 전환 | Exit 또는 대기 |
| 급격한 가격 변동 | Perp 부분 청산 |
| API 장애 | 재시도 로직, 알림 |
| 슬리피지 | 최대 슬리피지 제한 |
| Gas 급등 (Arbitrum) | Gas Price 모니터링 |
| ADL (Hyperliquid) | 포지션 크기 제한 |

---

## 다음 단계

1. **Hyperliquid SDK 테스트** → Funding Rate 조회 확인
2. **테스트넷 주문 테스트** → Perp Short 주문 실행
3. **Arbitrum Uniswap 연동** → Swap 테스트
4. **통합 테스트** → 소액으로 전체 플로우 테스트
