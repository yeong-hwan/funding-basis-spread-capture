# Funding/Basis Spread Capture

Chain: Arbitrum
Person: 장영환
Tag: DeFi

## About Perpetual DEX

### Perp. DEX

---

https://gmb.vc/article/perp-dex

이 중 오늘 이야기해볼 Perp DEX는 선물 거래를 지원하는 DEX입니다. DEX와 같이 온체인 상에서 거래가 실행되며 사용자가 본인의 지갑에서 자산 관리를 한다는 것은 같으나 레버리지 거래가 가능하다는 점이 차이점입니다. 대표적인 Perp DEX로는 dYdX, GMX, Hyperliquid 등이 있습니다.

**AARK, vertex, aster**

### Key Projects

---

https://hyperliquid.gitbook.io/hyperliquid-docs

https://docs.asterdex.com/

## Functional Requirements

### Key Concept

---

<aside>
✏️

**[Funding/Basis Spread Capture]**

---

같은 자산을 현물로 보유(Spot Long)하고,

같은 자산을 perpetual 선물로 동일 가치만큼 숏(Perp Short, 1x, Cross)하여

가격 변동은 상쇄하고 Funding Fee만 수익으로 남긴다.

</aside>

- Funding Fee
    
    Funding Rate = Premium Component ± Interest Component
    Funding Payment = Position Notional × Funding Rate
    
    Premium Index = (Perp Price − Index Price) / Index Price
    
    Funding Rate = clamp(
    EMA(Premium Index) + Interest Rate,
    MinRate,
    MaxRate
    )
    
- Delta(ε)
    
    SpotUSD = SpotQty × SpotPrice
    PerpUSD = |PerpQty| × PerpMarkPrice
    DeltaUSD = SpotUSD − PerpUSD
    
    DeltaUSD ≈ 0
    
- Rebalancing
    
    리밸런싱은 **포지션 정리나 매도가 아니라**, Active 상태를 유지하기 위한 **미세 조정 과정**이다.
    
    ### 리밸런싱 대상
    
    - ❌ Spot 포지션
    - ⭕ Perp Short 포지션 수량만 조정
    
    ### 트리거 조건 (밴드 방식)
    
    ```
    DeltaRatio = |DeltaUSD| / SpotUSD
    ```
    
    - `DeltaRatio ≤ ε` → 아무 것도 하지 않음
    - `DeltaRatio > ε` → 리밸런싱 수행
    
    (ε는 고정 파라미터, 예: 3~5%)
    
    ### 목표 Perp 수량
    
    ```
    TargetPerpQty = SpotUSD / PerpMarkPrice
    TargetQp = −TargetPerpQty
    ```
    
    조정 수량:
    
    ```
    AdjustQty = TargetQp − CurrentQp
    ```
    
    리밸런싱은 다음 제약을 따른다.
    
    - 최소 주문 수량 미만 조정 금지
    - 최대 조정 비율 제한 (예: 기존 Perp 수량의 20%)
    - 체인/거래소 간 이동 없음
- Other Rebalancing Trigger
    
    ### ② **가격 급변 트리거 (Risk / De-risk)**
    
    ---
    
    > 목적: 청산·ADL 리스크 완화
    > 
    - 조건 예:
        
        ```
        |ΔPrice| > θ%  (짧은 시간 내)
        ```
        
    - 조치:
        - **Perp Short 부분 축소** (완전 Exit 아님)
        - ε 일시 확대(리밸런싱 완화)
    - 비고: 델타가 맞아도 **급변 시엔 안전 우선**
    
    ### ③ **Funding 구조 변화 트리거 (Strategy Health)**
    
    ---
    
    > 목적: “유지할 가치”가 있는지 재검증
    > 
    - 조건 예:
        
        ```
        Funding > 0 이지만
        Funding < X  (임계값 하회)
        ```
        
    - 조치:
        - 리밸런싱 ❌
        - **Exit 또는 축소** 판단
    - 비고: 이건 **리밸런싱이 아니라 전략 판단**에 가깝다
    
    ### ④ **유동성/슬리피지 트리거 (Execution Safety)**
    
    ---
    
    > 목적: 실행 비용 폭증 방지
    > 
    - 조건 예:
        
        ```
        예상 슬리피지 > S_max
        ```
        
    - 조치:
        - **리밸런싱 스킵**
        - 다음 관측까지 대기
    - 비고: 델타가 깨져도 **못 건드리는 상황**은 존재한다

아비트럼

- 디파이에서 많이 쓰임
- 과제도 아비트럼으로

### Functional Requirements

---

[Funding/Basis Spread Capture](Funding%20Basis%20Spread%20Capture/Funding%20Basis%20Spread%20Capture%202e88c07c8d7380caba2fda3cc3845aec.csv)

# 공부(과제 이해)

### 아비트럼

- 이더리움 L2
- 옵티미스틱 롤업
    
    → 트랜잭션이 유효하다고 낙관적으로 가정하고 이더리움에 요약본(posting)만 제출
    
    Fraud Proof: 일정 챌린지 기간동안 악의적 트랜잭션 검증되면 롤백
    
- 특징
    - 가스비 절감
    - 높은 TPS
    - L1 대비 빠른 체결시간
    - 출금은 챌린지 기간 때문에 수일 소요

### 왜 펀딩피 델타뉴트럴에 아비트럼?

- Funding 수익률은 Gas cost 영향이 가장 크다
- 아비트럼은 거래단가가 매우 낮은 편

### Position

- Perp Short 1x: 하이퍼리퀴드
- Spot Long: Uniswap 등에서 arbitrum

### 봇 요구사항

- Funding rate 계산펴
- 포지션 비율 계산
- Hyperliquid API로 Perp 주문
- Arbitrum RPC로 Spot 트랜잭션 전송

### Funding Fee

- Perp > Spot → Long이 Short에게 지급
- Perp < Spot → Short가 Long에게 지급

### Funding Rate

```sql
Funding Rate = clamp(
	EMA(Premium Index) + Interest Rate,
	MinRate,
	MaxRate
)
```

- Perp–Spot 괴리 지표
- 극단값 제한(clamp)
- 전략은 항상 Perp Short → **Funding Rate > 0**인 경우에만 유의미

### Rebalancing

- 스팟이 Anchor이고, Perp Short 수량만 조절
- 허용가능한 ε 벗어나면 미세조정

### 그 외 디테일

- 가격 급변할 때 Perp short 수량 조절
- 슬리피지 있을 때 리밸런싱 하지 않기

### 아비트럼?

- 하이퍼리퀴드에서 tx
- 유저가 vault에 돈을 넣는다.
    - vault를 구현하는게 아비트럼으로 된다.
    - **aster**
- 프로그램을 아비트럼에 올린다
    - 솔리디티에서 어떤 체인에 올릴지 설정할 수 있다.