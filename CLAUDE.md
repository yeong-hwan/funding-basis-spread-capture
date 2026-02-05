# CLAUDE.md - 프로젝트 요구사항 및 지침

> **이 문서는 매 요청/작업 시작 전 반드시 확인할 것**

---

## 프로젝트 개요

**Funding/Basis Spread Capture** - Delta Neutral 전략을 통한 Funding Fee 수익 획득 시스템

- **Perp Short**: Hyperliquid HyperEVM (1x, Cross) - **컨트랙트 방식**
- **Spot Long**: Arbitrum (Uniswap)
- **목표**: 가격 변동 상쇄, Funding Fee만 수익

---

## 결정 사항 ✅

| 항목 | 결정 |
|------|------|
| **구현 방식** | 컨트랙트 (Solidity, HyperEVM) |
| **타겟 자산** | ETH |
| **테스트 환경** | 테스트넷 (Faucet 금액) |
| **메인 언어** | Solidity |

---

## 사용자 요구사항

### 작업 규칙

1. **`.gitignore` 관리**
   - 민감 정보 (API Key, Private Key, .env 등) 반드시 제외
   - 새로운 민감 파일 생성 시 즉시 .gitignore에 추가

2. **`CLAUDE.md` 참조**
   - 매 요청/작업 시작 전 이 문서 확인
   - 새로운 요구사항 발생 시 이 문서에 추가

3. **Git 관리**
   - 적정 주기마다 커밋 & 푸시
   - 커밋 메시지는 명확하게 작성
   - 기능 단위 또는 의미 있는 변경 시 커밋

4. **권한 자동 승인**
   - `.claude/settings.local.json`에 자동 승인 설정 완료

---

## 기술 스택

| 구분 | 기술 |
|------|------|
| **Language** | Solidity (메인), Foundry |
| **Perp Chain** | Hyperliquid HyperEVM |
| **Spot Chain** | Arbitrum |
| **Spot DEX** | Uniswap V3 |
| **Framework** | Foundry (forge, cast, anvil) |

---

## 핵심 컨트랙트 주소 (Hyperliquid)

| 컨트랙트 | 주소 |
|----------|------|
| **CoreWriter** | `0x3333333333333333333333333333333333333333` |
| **Oracle Precompile** | `0x0000000000000000000000000000000000000807` |
| **Precompile Base** | `0x0000000000000000000000000000000000000800` |

---

## 핵심 파라미터

| 파라미터 | 설명 | 기본값 |
|----------|------|--------|
| ε (epsilon) | Delta 허용 범위 | 5% |
| MIN_FUNDING | 최소 Funding Rate | TBD |
| MAX_SLIPPAGE | 최대 슬리피지 | 0.5% |

---

## 문서 구조

```
funding-basis-spread-capture/
├── CLAUDE.md                # 이 문서
├── docs/
│   ├── SPEC.md              # 기능 명세서
│   └── ACTION_PLAN.md       # 액션플랜
├── src/                     # Solidity 컨트랙트
├── script/                  # 배포 스크립트
├── test/                    # Foundry 테스트
└── lib/                     # 외부 라이브러리
```

---

## TODO

- [x] 타겟 자산 선택 → **ETH**
- [x] 구현 방식 결정 → **컨트랙트 (Solidity)**
- [x] 테스트 환경 → **테스트넷**
- [ ] Foundry 프로젝트 세팅
- [ ] HyperEVM 테스트넷 연동
- [ ] CoreWriter 인터페이스 구현
- [ ] Spot Long 컨트랙트 (Arbitrum)
- [ ] 통합 테스트

---

## 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-02-06 | 초기 문서 생성 |
| 2026-02-06 | 구현 방식 결정: Solidity 컨트랙트, ETH, 테스트넷 |
