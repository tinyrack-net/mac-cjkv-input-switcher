# Mac CJKV Input Switcher

macOS 메뉴 막대에서 실행되며 전역 단축키로 활성 입력 소스를 순서대로 전환하는 앱입니다.

맥을 원격으로 제어할 때 키보드 단축키를 눌러도 입력 언어가 바뀌지 않는 문제를 해결하기 위해 만들었습니다.

## 목적

macOS에는 CJKV(중국어·일본어·한국어·베트남어) 입력기로 전환할 때 간헐적으로 입력 상태가 제대로 반영되지 않는 문제가 있습니다.
이때 메뉴 막대의 아이콘은 바뀌었는데도 실제로 입력하면 이전 언어가 계속 입력되는 증상이 발생합니다.
이 문제는 주로 맥을 원격으로 제어하는 환경에서 발생합니다.

이 도구는 Carbon Text Input Source Services를 사용해, CJKV 전환에만 다음 우회 절차를 적용합니다.

- 임시 창을 잠깐 띄워 macOS가 현재 앱의 입력 상태를 다시 연결하도록 유도
- 약 150ms 후 입력기 전환
- 실제로 전환되었는지 확인하고, 실패하면 최대 2번 재시도
- 전환 중 단축키가 반복 입력되면 중복 요청은 무시
- 전환이 끝나면 원래 사용하던 앱으로 포커스 복원

ABC/U.S. 같은 일반 키보드 레이아웃은 즉시 전환합니다.

## 설치

GitHub Releases에서 DMG를 내려받아 앱을 `Applications` 폴더로 드래그한 뒤 실행합니다. Homebrew에서는 다음처럼 설치할 수 있습니다.

```sh
brew tap tinyrack-net/tap
brew install --cask mac-cjkv-input-switcher
```

## 사용법

기본 단축키는 `⌃⌥⇧Space`입니다. 메뉴 막대 아이콘의 `설정…`에서 단축키를 변경할 수 있습니다. 새 조합은 즉시 저장되고 다음 실행에도 유지됩니다. 최소 한 개의 보조 키가 필요합니다.

같은 설정 창의 `로그인 시 자동으로 시작`을 켜면 macOS에 로그인할 때 앱이 자동으로 실행됩니다. 이 설정은 앱을 종료해도 유지되며 다음 로그인부터 적용됩니다.

설정은 `~/Library/LaunchAgents/com.winetree.MacCJKVInputSwitcher.plist` 파일로 저장됩니다. macOS가 로그인할 때 이 파일을 읽어 앱을 실행하므로, 앱을 다른 위치로 옮겼다면 설정 창에서 한 번 껐다 켜 실행 경로를 갱신하세요.

## 요구 사항

- macOS 13 이상
- macOS 키보드 설정에서 사용할 입력 소스 활성화

## 개발

```sh
make build
make app
make universal
make dmg
```

`make install`은 빌드한 실행 파일을 `~/.local/bin`에 복사하고 `~/Library/LaunchAgents`에 자동 실행 설정을 등록합니다. `make uninstall`은 실행 파일과 설정을 함께 제거합니다.

```sh
make install
make restart  # 다시 빌드하고 LaunchAgent 재등록
make status   # LaunchAgent 상태
make logs     # 로그 추적
```

릴리스는 다음 흐름으로 진행합니다.

```sh
make release-prepare BUMP=patch
# release/vX.Y.Z 브랜치 PR을 main에 병합
make release-finalize
```

`vX.Y.Z` 태그가 push되면 GitHub Actions가 arm64와 Intel 앱을 빌드하고 Universal 앱, 공증된 DMG, SHA-256 체크섬을 생성합니다. 이후 `tinyrack-net/homebrew-tap`의 `Casks/mac-cjkv-input-switcher.rb`를 자동으로 갱신합니다.

Homebrew 배포에 필요한 GitHub Actions Secret은 다음과 같습니다.

- `HOMEBREW_TAP_TOKEN`: `tinyrack-net/homebrew-tap`에 Cask를 push할 수 있는 토큰
- `APPLE_DEVELOPER_ID`: Developer ID Application 서명 identity

공증을 활성화할 때는 Apple notarization API 키용 Secret도 추가합니다.
