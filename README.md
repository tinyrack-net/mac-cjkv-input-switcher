# Mac CJKV Input Switcher

macOS에서 입력 언어를 전환하는 전역 단축키(`Ctrl` + `Option` + `Shift` + `Space`)를 제공하는 작은 백그라운드 프로그램입니다.

맥을 원격으로 제어할 때 키보드 단축키를 눌러도 입력 언어가 바뀌지 않는 문제를 해결하기 위해 만들었습니다.

## 목적

macOS에는 CJKV(중국어·일본어·한국어·베트남어) 입력기로 전환할 때 간헐적으로 입력 상태가 제대로 반영되지 않는 문제가 있습니다.
이때 메뉴 막대의 아이콘은 바뀌었는데도 실제로 입력하면 이전 언어가 계속 입력되는 증상이 발생합니다.
이 문제는 주로 맥을 원격으로 제어하는 환경에서 발생합니다.

이 도구는 Carbon Text Input Source Services를 사용해, CJKV 전환에만 다음 우회 절차를 적용합니다.

- 목표 입력기를 먼저 선택해 macOS가 목표 입력기를 "이전 입력 소스"로 기억하게 함
- ABC/U.S. 같은 CJKV가 아닌 입력기로 한 번 이동 (이 전환은 안정적으로 동작)
- "이전 입력 소스 선택" 단축키를 합성해, macOS가 정상 이벤트 경로로 목표 입력기로 돌아가게 함
- 약 150ms 안에 목표 입력기에 도달했는지 확인하고, 실패하면 한 번 더 시도
- 그래도 실패하면 임시 창으로 입력 컨텍스트 재연결을 유도하고 직접 전환을 재시도
- 전환 중 단축키가 반복 입력되면 중복 요청은 무시
- 전환이 끝나면 원래 사용하던 앱으로 포커스 복원

ABC/U.S. 같은 일반 키보드 레이아웃은 즉시 전환합니다.

이 방식은 Karabiner-Elements가 CJKV 입력기 전환 문제를 피하는 방법과 Kawa가 사용하는 우회 절차를 그대로 따른 것입니다.

## 필요한 설정

위 우회 절차는 다음 조건이 갖춰져야 동작합니다. 조건이 빠지면 자동으로 임시 창을 사용하는 예전 방식으로 되돌아갑니다.

1. ABC/U.S. 같은 CJKV가 아닌 입력 소스가 하나 이상 활성화되어 있어야 합니다.
2. 시스템 설정 > 키보드 > 키보드 단축키 > 입력 소스에서 "이전 입력 소스 선택" 단축키가 켜져 있어야 합니다.
   기본값(Control-Space)이 아니어도 되며, 이 도구는 설정된 단축키를 그대로 읽어 사용합니다.
3. 손쉬운 사용(Accessibility) 권한이 필요합니다. 단축키를 합성하려면 macOS가 이 권한을 요구합니다.
   시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 `+` 버튼으로 실제 실행 파일인 `~/.local/bin/MacCJKVInputSwitcher`를 추가하고, 권한을 켠 뒤 `make restart`로 다시 시작합니다.
   다시 빌드해 설치하면 서명이 바뀌므로 권한을 다시 확인해야 할 수 있습니다.

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

## 진단

입력기가 예상대로 바뀌지 않으면 설정이 제대로 잡혔는지 먼저 확인합니다. 입력기를 전환하지 않고 설정만 출력합니다.

```sh
~/.local/bin/MacCJKVInputSwitcher --diagnose
```

출력에서 확인할 항목은 다음과 같습니다.

- 입력 소스 목록에 CJKV가 아닌 입력기가 있는지
- "Previous input source shortcut"이 켜져 있는지
- "Accessibility permission"이 granted인지

`Accessibility permission`은 이 명령을 실행한 프로세스 기준으로 표시됩니다. 실제로 동작하는 데몬의 권한 상태는 시작할 때 남는 로그를 확인하는 편이 정확합니다.

단축키를 눌렀을 때 실제로 어떤 경로로 전환되었는지는 로그에서 확인할 수 있습니다.

```sh
make logs
```

`Switched to ... through the input source shortcut workaround`가 찍히면 우회 절차가 동작한 것이고,
`forcing an input context rebind`가 찍히면 예전 방식으로 되돌아간 것입니다.

키보드가 없는 원격 세션에서는 신호로도 전환할 수 있습니다.

```sh
kill -USR1 $(pgrep MacCJKVInputSwitcher)
```

## 기타 명령

```sh
make build    # 릴리스 빌드
make restart  # 다시 빌드하고 LaunchAgent 재등록
make status   # LaunchAgent 상태
make logs     # 로그 추적
make diagnose # 현재 입력 소스와 우회 절차 설정 출력
make clean    # SwiftPM 빌드 산출물 삭제
```
