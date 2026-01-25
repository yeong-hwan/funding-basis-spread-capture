# funding-basis-spread-capture

Arbitrum에서 Solidity로 **Funding/Basis Spread Capture** 전략(Spot Long + Perp Short로 델타중립 후 Funding 수취)을 위한 스마트컨트랙트/봇 연동 프로젝트를 구성합니다.

> 현재 단계: **Solidity 개발 환경(Foundry) 세팅 + 기본 컨트랙트 스캐폴딩**  
> Aster 거래소 연동/정확한 포지션 관리 로직은 이후 명세에 맞춰 확장합니다.

## 로컬 개발 환경 (Foundry)

### 설치
- Foundry 설치: `foundryup` (공식 가이드 참고)
- (선택) 표준 라이브러리 설치(더 편한 테스트/스크립트용):

```bash
forge install foundry-rs/forge-std --no-commit
```

### 빌드/테스트

```bash
forge build
forge test -vvv
```

> 네트워크가 막힌 환경(샌드박스/CI 제한 등)에서는 `forge test`가 OpenChain 시그니처 조회를 시도하다 실패할 수 있습니다.  
> 이 경우 아래처럼 실행하면 됩니다:
>
> ```bash
> forge test --offline
> ```

### solc 경로 참고(맥 Homebrew)

이 레포의 `foundry.toml`은 `solc = "/opt/homebrew/bin/solc"`로 설정되어 있습니다.  
Homebrew 경로가 다르면 `which solc`로 확인 후 해당 경로로 수정하세요(예: Intel 맥은 `/usr/local/bin/solc`일 수 있음).

### 환경변수

```bash
cp env.example .env
```

`.env`에 아래 값을 채운 뒤 배포 스크립트를 실행합니다.

- **ARBITRUM_RPC_URL**: Arbitrum RPC URL
- **DEPLOYER_PRIVATE_KEY**: 배포자 개인키(커밋 금지)
- **COLLATERAL_TOKEN**: 담보 토큰 컨트랙트 주소(예: Arbitrum USDC)
- **KEEPER**: Keeper(봇) 주소

### Arbitrum 배포 예시

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$ARBITRUM_RPC_URL" \
  --broadcast \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  -vvv
```

## 구조
- `src/`: Solidity 컨트랙트
- `src/interfaces/`: 외부 프로토콜(예: Aster) 인터페이스 플레이스홀더
- `script/`: 배포 스크립트(Foundry `forge script`)
- `test/`: 테스트
- `SPEC/`: 요구사항 및 개발 스펙 문서

## 다음에 필요한 명세(천천히 주셔도 됩니다)
- 어떤 거래소/계정 모델로 Aster에 주문을 넣을지(온체인/오프체인, 서명 방식)
- 자금 흐름(유저 예치/출금, 수수료 구조, Keeper 권한)
- 리스크(청산/슬리피지/리밸런싱 트리거)와 모니터링 방식
