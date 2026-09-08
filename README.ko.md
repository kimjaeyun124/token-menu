<p align="center">
  <img src="assets/token-menu-icon.png" alt="Token Menu 앱 아이콘" width="144">
</p>

# Token Menu

[English](README.md) · [한국어](README.ko.md)

Token Menu는 Codex와 Claude Code 등 지원되는 AI 코딩 서비스의 사용량을 확인할 수 있는 오픈소스 macOS 메뉴바 유틸리티입니다.

남은 사용량을 메뉴바에서 확인하고, 아이콘을 눌러 상세 정보를 열 수 있습니다. 실행 중에는 Dock에 표시되지 않습니다.

**[최신 DMG 다운로드](https://github.com/kimjaeyun124/token-menu/releases/latest)**

## 주요 기능

- 메뉴바에 남은 사용량 표시: 기본적으로 5시간 한도를 우선 표시합니다.
- 주간 한도와 초기화까지 남은 시간 표시: 하루 이상 남으면 일·시간·분으로 보여 줍니다.
- 다시 확인·설정·종료 버튼을 갖춘 간결한 사용량 창.
- 서비스별 표시 여부, 순서, 확인 주기 및 사용량 부족 알림 설정.
- 기본 흰색 AI 아이콘과 아이콘 색상 설정.
- 한국어·영어 인터페이스, 로그인 시 자동 실행, 선택적으로 사용하는 Control–Option–C 단축키.
- 현재 데스크톱에서 열리는 설정 창과 최소 창 크기, 행 전체를 누를 수 있는 사이드바.

Token Menu는 서비스가 제공하는 사용량 한도를 표시합니다. 토큰 수를 추정하지 않으며, 정보가 없으면 0%가 아닌 확인할 수 없는 상태로 표시합니다.

## 서비스 지원 범위

| 서비스 | 현재 동작 |
| --- | --- |
| Codex | 설치되어 있고 로그인된 Codex의 app-server를 통해 실제 사용량 한도를 조회합니다. |
| Claude Code | 서비스로 선택할 수 있지만, 현재 구현에서는 백그라운드 사용량 조회를 지원하지 않습니다. |

Claude Code의 대화형 사용량 화면은 독립적인 백그라운드 조회 API가 아닙니다. Token Menu는 해당 화면을 수집하거나 조회를 위해 Claude 설정을 변경하지 않습니다.

## 설치

**macOS 13 이상**이 필요합니다. Universal DMG에는 Apple Silicon과 Intel 실행 파일이 모두 포함됩니다. 실제 실행 검증은 Apple Silicon에서 수행하며, Intel과 macOS 13에서는 아직 실행 검증하지 않았습니다.

1. [Releases](https://github.com/kimjaeyun124/token-menu/releases/latest)에서 DMG를 다운로드합니다.
2. DMG를 열고 **Token Menu.app**을 **Applications(응용 프로그램)** 폴더로 드래그합니다.
3. 응용 프로그램 폴더에서 Token Menu를 한 번 실행합니다.
4. 메뉴바에 표시되는 사용량을 클릭해 사용량 창을 엽니다.
5. 필요하면 **설정 → 일반 → 로그인할 때 자동 실행**을 켭니다.

현재 배포본은 임시 서명(ad-hoc)을 사용하며 **Apple 공증을 받지 않았습니다**. 처음 실행할 때 macOS에서 차단할 수 있습니다. 다운로드 출처를 확인한 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기**를 사용하세요. Gatekeeper를 끌 필요는 없습니다.

기존 Codex Usage에서 변경하는 경우 먼저 이전 앱을 종료하세요. 기존 설정은 유지되며, 두 앱을 동시에 실행하지 않는 것이 좋습니다.

사용량을 조회하기 전에 설치된 Codex CLI 또는 데스크톱 앱에서 로그인해 주세요. 조회 시간이 초과되면 다시 확인 버튼으로 재시도할 수 있습니다. 시간 초과는 남은 사용량이 0%라는 뜻이 아닙니다.

## 개인정보 보호

인증은 설치된 Codex 프로세스가 처리합니다. Token Menu는 인증 파일, 브라우저 쿠키, API 키 또는 인증 헤더를 읽거나 복사하지 않습니다. 서비스 응답 원문을 로그에 남기지 않으며, 조회에 실패했을 때 사용량을 추정하지 않습니다.

## 빌드 및 테스트

Xcode 또는 Command Line Tools와 패키지에서 사용할 수 있는 Swift 도구 모음(Swift 5.9 이상)이 필요합니다.

```sh
git clone https://github.com/kimjaeyun124/token-menu.git
cd token-menu

# 일반 테스트: 실제 서비스 조회 테스트는 기본적으로 건너뜁니다.
swift test

# 선택 사항: 로그인된 Codex 서비스에 별도로 실제 조회를 요청합니다.
CODEX_LIVE_TEST=1 swift test --filter CodexUsageTests.testLiveCodexProviderWhenExplicitlyEnabled

# 앱 아이콘을 포함하는 Universal 앱과 압축 DMG를 만듭니다.
./scripts/build-dmg.sh
open "dist/Token Menu.app"
```

결과물은 `dist/Token Menu.app`, `dist/token-menu-1.0.0-macOS-universal.dmg`, 검증용 `.sha256` 파일입니다. 단일 아키텍처로 빌드하려면 `ARCHITECTURE=arm64` 또는 `ARCHITECTURE=x86_64`를 지정하세요. 앱을 이미 빌드했다면 `SKIP_BUILD=1 ./scripts/build-dmg.sh`로 DMG만 생성할 수 있습니다.

서명과 배포 방법, 검증 범위는 [배포 문서](docs/distribution.md)를 참고하세요. 기존 설정을 유지하기 위해 내부 Swift 타깃 이름과 번들 식별자는 유지합니다.

## 라이선스

Token Menu는 MIT License로 공개되는 오픈소스 프로젝트입니다.

MIT License의 조건에 따라 소스 코드를 자유롭게 사용하고 복사하고 수정하고 배포할 수 있으며 상업적 사용도 허용됩니다.

자세한 내용은 [LICENSE](LICENSE) 파일을 확인해 주세요. 제3자 서비스의 로고·상표·브랜드 자산에는 Token Menu의 MIT License가 **적용되지 않습니다**. 자세한 구분은 [NOTICE.md](NOTICE.md)를 참고하세요.

## 상표 및 브랜드 고지

Codex, OpenAI, ChatGPT 및 관련 이름, 로고와 표시는 OpenAI의 상표 또는 기타 지식재산입니다.

Claude, Anthropic 및 관련 이름, 로고와 표시는 Anthropic의 상표 또는 기타 지식재산입니다.

Token Menu에 포함되거나 언급되는 제3자의 이름, 로고, 아이콘 및 기타 브랜드 자산은 MIT License의 적용 대상이 아니며 각각의 권리자 정책과 권리가 별도로 적용됩니다.

Token Menu는 독립적으로 개발된 제3자 프로젝트이며 OpenAI 또는 Anthropic과 제휴 관계가 없고 공식 승인, 후원 또는 지원을 받은 프로젝트가 아닙니다.
