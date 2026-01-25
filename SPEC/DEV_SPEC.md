# DEV_SPEC (Draft) — Funding/Basis Spread Capture

> 이 문서는 `SPEC/MAIN_SPEC.md` + `SPEC/REQUIREMENT/*`를 기반으로, **제가 실제 개발에서 기준으로 삼을 “실행 가능한 스펙”**을 정리한 것입니다.  
> Aster(Perp) 연동 세부사항은 아직 미정이므로, **온체인/오프체인 경계를 명확히** 두고 추후 Aster 문서/ABI에 맞춰 교체합니다.

## 1) 프로젝트를 내가 이해한 형태로 설명

### 1.1 핵심 전략(델타 중립 + 펀딩 수취)
- 같은 자산에 대해
  - **Spot Long**: 현물(온체인 DEX 등)로 보유
  - **Perp Short (1x, Cross)**: 무기한 선물로 동일 노션만큼 숏
- 목표는 가격 방향성(Δ)을 거의 0으로 만들고, **Funding Rate가 양수일 때 Short가 받는 Funding Payment**를 수익으로 남기는 것

### 1.2 “리밸런싱”의 정의 (중요)
- 스펙에서 리밸런싱은 **포지션 청산/매도가 아니라 Active 상태 유지용 미세조정**
- **Spot은 Anchor(고정)**이고, 리밸런싱은 **Perp Short 수량만 조정**
- 델타 기준:
  - \(SpotUSD = SpotQty \times SpotPrice\)
  - \(PerpUSD = |PerpQty| \times PerpMarkPrice\)
  - \(DeltaUSD = SpotUSD - PerpUSD\)
  - \(DeltaRatio = |DeltaUSD| / SpotUSD\)
- 밴드 방식:
  - `DeltaRatio ≤ ε` → 유지
  - `DeltaRatio > ε` → Perp 수량을 목표치로 조정

### 1.3 상태머신 관점(Idle/Active)
- **Idle**: 자금은 Vault에 있지만 포지션 없음(또는 정리 중)
- **Active**: Spot Long + Perp Short 포지션이 존재하며 델타 중립 유지
- 전환 규칙(요약):
  - Idle → Active: Funding 조건 충족 시 포지션 생성
  - Active → Idle: Funding이 0 이하로 전환되거나(또는 리스크/출금) 포지션 정리
  - Transition Lock: 전환 중 중복 진입/중복 청산 방지

## 2) 구성 요소(온체인/오프체인)와 책임 분리

### 2.1 온체인(Solidity, Arbitrum)
**목표:** 자금 보관/권한/상태/회계(share) + “무엇을 해야 하는지” 이벤트/체크포인트 기록

- `SpreadCaptureVault` (향후 확장):
  - 유저 예치/출금 요청
  - 상태(Idle/Active/Transition) 관리
  - Keeper 권한 관리(봇 트리거)
  - (선택) Aster가 온체인 거래를 제공하면 직접 호출, 아니면 “체크포인트 기록” 중심

### 2.2 오프체인(Keeper/Bot)
**목표:** 시장 데이터(Funding/Mark/Index), 슬리피지 추정, 주문 실행(Spot swap / Perp 주문), 위험 제어

- 주기적으로:
  - Funding Scan + Allocation Filter (후보 거래소 선정)
  - Delta Check + Rebalance Trigger
  - Volatility Guard / Funding Guard / ADL Awareness 판단
- 실행 후 온체인에:
  - “전환 시작/완료”, “현재 노출(Spot/Perp)”, “선택된 거래소(venue)” 등의 체크포인트를 기록(이벤트)

> **왜 이렇게 나누나?**  
> Perp DEX의 주문/포지션 관리가 완전 온체인으로 끝나지 않는 경우가 많고,  
> Funding/슬리피지/ADL 같은 신호는 오프체인에서 계산/집계하는 편이 현실적입니다.

## 3) 기능 요구사항을 개발 항목으로 재구성

### 3.1 Deposit / Withdrawal
- **User Deposit**: 유저가 Vault에 예치 가능
- **Deposit Handling**: 예치 즉시 포지션에 쓰지 않고 “대기 자금”으로 보관
- **Deposit State**: 예치 직후 Vault 상태는 Idle
- **Withdraw Request**: 유저가 출금을 요청(즉시 출금이 아닐 수 있음)
- **Position Unwind**: 출금 요청 시 **Perp를 우선 정리**
- **Asset Return**: 정리 완료 후 유저에게 자산 반환

### 3.2 Entry / Allocation
- **Funding Scan**: 지원 거래소들의 펀딩을 주기적으로 조회
- **Allocation Filter**: Funding이 양수이며 임계값 이상(파라미터 X)인 거래소만 후보
- **Single Allocation**: 한 번에 하나의 거래소(venue)에만 배분
- **No Valid Venue**: 조건 만족 venue가 없으면 Idle 유지
- **Spot Long / Perp Short**: 조건 충족 시 Spot 매수 + Perp 1x 숏 생성

### 3.3 Active 유지(리밸런싱)
- **Delta Check**: 주기적으로 델타 계산
- **Rebalance Trigger**: `DeltaRatio > ε`면 Perp만 조정(브릿지 금지)

### 3.4 Risk Controls
- **Funding Guard**: Funding이 음수면 신규 진입 제한
- **Active → Idle**: Funding이 0 이하로 전환되면 포지션 정리 후 Idle 전환
- **Volatility Guard**: 급변 시 Perp 축소(De-risk)
- **ADL Awareness**: ADL 가능성을 고려한 포지션 크기 제한(주로 오프체인 룰)
- **Transition Lock**: 상태 전환 중 중복 포지션 생성 방지

## 4) 내가 사용할 “운영 파라미터” 초안

> 값은 아직 미정. 우선 “필드/의미”만 확정하고, 백테스트/실거래로 튜닝합니다.

- **ε (epsilon)**: 델타 허용 밴드(예: 3~5%)
- **rebalance_max_adjust_ratio**: 한 번 리밸런싱에서 변경 가능한 Perp 수량 상한(예: 20%)
- **min_adjust_notional / min_order_size**: 최소 주문/조정 단위
- **funding_threshold_x**: 진입 가능한 최소 Funding(Allocation Filter의 X)
- **funding_scan_interval_sec**: Funding Scan 주기
- **volatility_theta_pct + volatility_window_sec**: 급변 트리거 기준
- **slippage_max_bps**: 예상 슬리피지 상한(초과 시 스킵)
- **adl_risk_limit**: venue별 ADL 리스크 기반 최대 노출(오프체인 룰)
- **cooldown_sec**: 전환/리밸런싱 연속 실행 방지

## 5) 온체인 컨트랙트 인터페이스(초안)

> 현재 `src/SpreadCaptureVault.sol`은 뼈대만 있음. 아래는 “최종적으로 만들 인터페이스” 초안입니다.

- **유저**
  - `deposit(amount) -> shares`
  - `requestWithdraw(shares)`
  - `claimWithdraw(requestId)` (비동기 출금일 경우)
- **Keeper**
  - `startActivate(venueId, planHash)` / `finishActivate(checkpoint)`
  - `rebalance(checkpoint)`
  - `startUnwind(reason)` / `finishUnwind(checkpoint)`
- **Owner**
  - 파라미터 설정(ε, 임계값, keeper 교체 등)

### 체크포인트(Checkpoint) 모델(추천)
- 온체인은 “진실의 원장”이라기보다 **감사 가능한 이벤트 로그 + 권한 통제**를 담당
- 오프체인 실행 결과를 아래처럼 기록:
  - `spot_qty`, `perp_qty`, `spot_price`, `perp_mark_price`, `delta_ratio`
  - `funding_rate`, `venue_id`, `timestamp`
- 추후 Aster가 온체인 포지션 조회를 제공하면, 일부를 on-chain validation으로 강화

## 6) 개발 로드맵(내가 제안하는 단계)

### Phase 0 — 현재(완료)
- Foundry 세팅 + Vault 뼈대 + 배포 스크립트 + 기본 테스트

### Phase 1 — 온체인 Vault 회계/상태머신 완성
- ERC4626 유사 share 회계(예치/출금 요청 큐)
- Idle/Active/Transition Lock 구현
- Keeper 체크포인트/이벤트 스키마 확정

### Phase 2 — 오프체인 Keeper PoC
- Funding Scan/Filter + Delta Check + Rebalance Trigger 구현(모의 데이터부터)
- 시뮬레이션/로깅 + 안전장치(쿨다운/슬리피지 스킵)

### Phase 3 — Aster 연동
- Aster가 온체인 거래/포지션 API를 제공하는지 확인 후:
  - (A) 온체인 연동: Solidity 인터페이스/어댑터 구현
  - (B) 오프체인 연동: API/서명 기반 주문 + 온체인 체크포인트 강화

## 7) 지금 당장 내가 확인해야 하는 미정 사항(질문 목록)

1) **Deposit 자산이 무엇인가?** (USDC 같은 스테이블? 혹은 해당 Spot 자산 자체?)
2) **Spot Long 실행 방식**: 온체인 DEX(예: Uniswap/1inch)로 매수/보관 후 고정?  
3) **Aster Perp가 온체인으로 주문 가능한가?** 가능하다면 컨트랙트 주소/ABI/마진 토큰은?
4) **Funding 데이터 소스**: Aster 온체인/오프체인 어디서 읽나? (keeper가 읽고 기록?)
5) **출금은 언제 확정되는가?** 즉시 출금 vs “unwind 완료 후 claim”

