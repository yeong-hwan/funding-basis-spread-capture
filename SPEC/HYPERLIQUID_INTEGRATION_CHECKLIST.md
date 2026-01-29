# Hyperliquid 연동 체크리스트 (필수)

> 목적: Arbitrum(온체인 Vault) + Hyperliquid(Perp Short) 하이브리드 구조로
> “어디를 어떻게 호출/서명해야 하는지”를 확정한다.

## 1) 핵심 결론(아키텍처)

- **Spot**: Arbitrum에서 1inch로 ETH(실제로는 WETH) 매수/보유
- **Perp**: Hyperliquid에 계정(서명키)로 **오프체인 주문**을 넣어 ETH Perp Short 유지
- **상태/회계**: 온체인 Vault는 share 회계와 “체크포인트 기록(감사 로그)”를 담당
- **실행 주체**: Keeper가
  - Vault에서 자금 이동(필요 시)
  - Hyperliquid 주문/포지션/펀딩 조회
  - 결과를 Vault에 기록

## 2) 네가 나에게 제공해야 하는 최소 정보(복붙 템플릿)

- Hyperliquid **market symbol** (ETH Perp): `...` (예: `ETH`/`ETH-PERP` 등 정확한 심볼)
- Hyperliquid **account model**
  - (A) Vault 소유 EOA 1개로 운용?  
  - (B) Keeper 전용 키로 운용?  
  - (C) 멀티시그/세이프 기반? (권장, 단 구현 난이도↑)
- Hyperliquid **주문 단위**
  - qty 단위(contracts? base size?): `...`
  - 최소 주문 단위 / tick size: `...`
- Hyperliquid **fee 모델**
  - maker/taker fee: `...`
  - funding 정산 주기/단위: `...`
- Hyperliquid **자금(마진) 입출금 경로**
  - 어떤 토큰이 마진인지(USDT/USDC 등): `...`
  - Arbitrum에서 Hyperliquid로 넣는 방법(브릿지/입금 컨트랙트/단순 전송 등): `...`

## 3) 우리가 확인해야 하는 기술 리스크 3개

1. **마진 토큰 불일치 가능성**
   - Vault는 USDT 기준으로 예치/회계인데,
   - Hyperliquid 마진이 USDC 등 다른 토큰이면
     - USDT→USDC 스왑이 추가되고 비용/리스크가 커짐

2. **키 관리**
   - Hyperliquid 주문은 서명 키가 필요할 가능성이 높음
   - 다수 유저 share 모델에서 “개인키를 Vault가 직접 들고”는 갈수록 위험해짐
   - 초기는 Keeper 키로 단순화 가능하지만, 권한/감사/사고 대응 설계를 같이 해야 함

3. **테스트 전략**
   - 테스트넷이 없다면 “메인넷 포크 + 모의 Hyperliquid” 형태로 가야 함
   - `SPEC/TESTING_PLAN.md` 참고

