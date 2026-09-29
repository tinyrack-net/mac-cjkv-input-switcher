# Mac CJKV Input Switcher

macOS 메뉴 막대에서 실행되며 전역 단축키로 활성 입력 소스를 순서대로 전환하는 앱입니다.

## 설치

GitHub Releases에서 DMG를 내려받아 앱을 `Applications` 폴더로 드래그한 뒤 실행합니다. Homebrew에서는 다음처럼 설치할 수 있습니다.

```sh
brew tap tinyrack-net/tap
brew install --cask mac-cjkv-input-switcher
```

## 사용법

기본 단축키는 `⌃⌥⇧Space`입니다. 메뉴 막대 아이콘의 `설정…`에서 단축키를 변경할 수 있습니다. 새 조합은 즉시 저장되고 다음 실행에도 유지됩니다. 최소 한 개의 보조 키가 필요합니다.

앱 첫 실행 시 로그인 후 자동 실행을 등록합니다. 앱 메뉴에서 `종료`를 선택하면 자동 실행 등록도 해제합니다.

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
