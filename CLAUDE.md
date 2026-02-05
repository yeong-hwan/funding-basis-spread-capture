# CLAUDE.md - 프로젝트 요구사항 및 지침

> **이 문서는 매 요청/작업 시작 전 반드시 확인할 것**

---

## 프로젝트 개요

**Funding/Basis Spread Capture** - Delta Neutral 전략을 통한 Funding Fee 수익 획득 시스템

- **Perp Short**: Hyperliquid (1x, Cross)
- **Spot Long**: Arbitrum (Uniswap)
- **목표**: 가격 변동 상쇄, Funding Fee만 수익

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

- **Language**: Python 3.11+ (또는 TypeScript)
- **Perp Exchange**: Hyperliquid
- **Spot Chain**: Arbitrum
- **Spot DEX**: Uniswap V3

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
docs/
├── SPEC.md         # 기능 명세서
└── ACTION_PLAN.md  # 액션플랜
```

---

## TODO / 미해결 질문

- [ ] 타겟 자산 선택 (ETH/BTC/기타)
- [ ] 초기 자금 규모 결정
- [ ] 파라미터 값 확정 (ε, MIN_FUNDING 등)

---

## 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-02-06 | 초기 문서 생성, 기본 요구사항 정리 |
