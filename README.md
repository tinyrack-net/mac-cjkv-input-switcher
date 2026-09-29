# Mac CJKV Input Switcher

macOS에서 입력 언어를 전환하는 전역 단축키(`Ctrl` + `Option` + `Shift` + `Space`)를 제공하는 작은 백그라운드 프로그램입니다.

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

## 요구 사항

- macOS 13+
- Xcode Command Line Tools
- macOS 키보드 설정에서 입력 소스 활성화

## 설치 및 제거

```sh
make install
make uninstall
```

설치하면 다음 위치에 파일이 만들어집니다.

- 실행 파일: `~/.local/bin/MacCJKVInputSwitcher`
- 자동 실행 설정: `~/Library/LaunchAgents/com.winetree.MacCJKVInputSwitcher.plist`
- 로그 파일: `~/Library/Logs/MacCJKVInputSwitcher.log`

## 사용법

프로그램을 설치하고 나면 `Ctrl` + `Option` + `Shift` + `Space`를 눌러 macOS 설정에 활성화된 입력기를 순서대로 전환할 수 있습니다.
입력기가 안정적으로 다시 연결될 수 있도록 단축키를 누른 직후 약간의 지연이 발생합니다.

## 기타 명령

```sh
make build    # 릴리스 빌드
make restart  # 다시 빌드하고 LaunchAgent 재등록
make status   # LaunchAgent 상태
make logs     # 로그 추적
make clean    # SwiftPM 빌드 산출물 삭제
```
