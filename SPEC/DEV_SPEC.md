# DEV_SPEC (Draft) — Funding/Basis Spread Capture

> 이 문서는 `SPEC/MAIN_SPEC.md` + `SPEC/REQUIREMENT/*`를 기반으로, **제가 실제 개발에서 기준으로 삼을 “실행 가능한 스펙”**을 정리한 것입니다.  
> Perp venue는 **Hyperliquid**이며, **온체인(Arbitrum Vault) + 오프체인(Keeper)** 경계를 명확히 둡니다.

## 0) 확정된 전제(당신이 방금 확정해준 내용)

- **담보/회계 기준 자산**: USDT
- **주요 거래 대상(Spot/Perp 기초자산)**: ETH
- **Spot Long 실행**: Arbitrum에서 **1inch Aggregator**로 ETH 매수
- **Perp Short 실행(업데이트)**: **Hyperliquid로 변경**
  - 구현 메모: Hyperliquid는 일반적으로 Arbitrum EVM 컨트랙트 호출로 “Perp 주문”이 끝나지 않음
  - 따라서 본 프로젝트는 **Arbitrum(온체인 Vault) + 오프체인 Keeper(Hyperliquid 주문/조회)** 하이브리드로 설계
- **Funding/포지션 조회(업데이트)**: Hyperliquid 데이터 소스(대부분 API/노드)로 조회 후 Vault에 체크포인트 기록
- **Vault 운영 모델**: **다수 유저 share 모델**
- **Spot 자산 보유 형태**: **Vault가 ETH를 들고 감**
  - 구현 메모: 실제 구현은 native ETH보다 **WETH(ERC20)** 보유가 안전/일반적(1inch도 보통 WETH 경유)
- **출금 정책**: “Vault를 놓고 출금은 내가 원할 때만”
  - 해석(확정 버전): 유저는 언제든 **withdraw 요청**은 할 수 있으나,
    실제 **언와인드/스왑/정산 실행은 운영자(Owner)가 원할 때 배치로 처리**하는 운영 모드

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
  - (선택) 외부 venue가 온체인 호출을 제공하면 직접 호출, 아니면 “체크포인트 기록” 중심

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
- **Withdraw Policy(업데이트)**: “요청은 유저, 실행은 운영자”
  - 유저는 `requestRedeem(shares)`로 요청 등록
  - 운영자는 원할 때 `processWithdrawals(maxCount)`를 호출해
    - (필요 시) Perp를 우선 축소/정리하고
    - Spot(WETH)을 1inch로 USDT로 일부 스왑한 뒤
    - 요청을 순서대로 처리(부분 체결 가능/불가능 정책은 Phase 1에서 확정)
- **Position Unwind**: 출금/정리 시 **Perp를 우선 정리** 후 Spot 정리
- **Asset Return**: 정리 완료 후 USDT로 회수/반환(초기에는 Owner-only 반환 가능성)

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

## 4.1 수수료/비용 모델(필수 반영)

### Perp 거래 수수료(Hyperliquid 기준으로 재정의 필요)
- Hyperliquid의 maker/taker/펀딩/정산 비용 모델을 확인 후 이 섹션을 업데이트해야 함.

### 비용을 고려한 “유효 수익성” 체크(초안)
- 신규 진입/리밸런싱/부분 언와인드 전에는 아래를 항상 체크:
  - **예상 Funding 수익(예: 다음 N번 펀딩 구간)** ≥
    - Perp 진입/조정 수수료(보수적으로 Taker 가정)
    - Spot swap 비용(1inch protocol fee/DEX fee + 슬리피지)
    - 가스비(Arbitrum)
    - 안전 마진(리스크 버퍼)
- 즉, “Funding이 양수”만으로는 부족하고 **Funding이 ‘비용을 이길 만큼’ 양수**여야 함

### 실행 정책(초안)
- **Entry/큰 조정**: 기본은 Taker로 가정(체결 확실성 우선) → 비용을 더 보수적으로 잡음
- **미세 리밸런싱**: Maker를 쓰면 비용은 줄지만 미체결/리스크가 커질 수 있어,
  - 초기 버전은 **Taker-only**로 단순화하고,
  - Phase 3 이후에 Maker 옵션을 추가(명세/리스크 룰 필요)

## 5) 온체인 컨트랙트 인터페이스(초안)

> 현재 `src/SpreadCaptureVault.sol`은 뼈대만 있음. 아래는 “최종적으로 만들 인터페이스” 초안입니다.

- **유저(다수 유저 share 모델 확정)**
  - `depositUsdt(amount) -> shares`
  - `requestRedeem(shares)` (즉시 USDT를 내주지 않고 “요청”만 쌓음)
  - `claim(requestId)` 또는 `claimable(shares)` 형태(배치 처리 후 수령)
- **Keeper**
  - `startActivate(venueId, planHash)` / `finishActivate(checkpoint)`
  - `rebalance(checkpoint)`
  - `startUnwind(reason)` / `finishUnwind(checkpoint)`
- **Owner**
  - 파라미터 설정(ε, 임계값, keeper 교체 등)
  - 출금/언와인드 트리거(“내가 원할 때만” 정책): `processWithdrawals(...)`

### 체크포인트(Checkpoint) 모델(추천)
- 온체인은 “진실의 원장”이라기보다 **감사 가능한 이벤트 로그 + 권한 통제**를 담당
- 오프체인 실행 결과를 아래처럼 기록:
  - `spot_qty`, `perp_qty`, `spot_price`, `perp_mark_price`, `delta_ratio`
  - `funding_rate`, `venue_id`, `timestamp`
- 추후 Perp venue 쪽에서 온체인 검증 가능한 정보가 제공되면, 일부를 on-chain validation으로 강화

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

### Phase 3 — Hyperliquid 연동 고도화
- Hyperliquid 주문/조회/펀딩/수수료 모델을 확정하고,
  - Keeper 운영/키관리/감사 로그를 강화
  - 비용 모델 기반 진입/조정 정책을 튜닝

## 7) 지금 당장 내가 확인해야 하는 미정 사항(질문 목록)

1) **Deposit 자산이 무엇인가?** → USDT (확정)
2) **Spot Long 실행 방식** → 1inch (확정)
3) **Hyperliquid 주문/조회 방식**: API/서명/계정 모델 확정 필요(온체인 호출만으로 끝나지 않는 구조)
4) **Funding 데이터 소스**: Hyperliquid에서 제공하는 funding/mark/index 데이터 경로 확정 필요
5) **출금 UX** → “요청은 유저, 실행은 운영자 배치” (확정)

## 7.1 (업데이트) 남은 핵심 질문 3개

1) **Share 회계 기준(NAV 산정)**: ETH(WETH) 보유분을 USDT 가치로 환산할 때
   - 온체인 오라클(예: Chainlink ETH/USDT)을 쓸지,
   - 또는 “실제 스왑/정산된 USDT 기준”으로만 share 가격을 움직일지(단, 출금 대기 중 불공정 가능)
2) **WETH/ETH 처리 정책**: native ETH 수령/송금 지원 여부(대부분 WETH로 단순화 추천)
3) **Hyperliquid 연동 세부**:
   - 마진 토큰(USDT/USDC 등) 확정 및 입출금 경로
   - 주문 단위/최소 단위/수수료 모델
   - API/서명/계정 모델 및 키 관리
