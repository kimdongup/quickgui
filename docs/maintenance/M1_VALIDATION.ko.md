# M1 Quickgui PATH·Bash 수정 검증

2026-09-09 (Pacific/Honolulu). 사용자 M1 맥미니에서 실제 실행한 결과다.
이번 범위는 Quickemu/Quickget의 Bash 선택 오류 수정, 회귀 검사와 macOS 빌드다.
게스트 OS 설치·실행 완료를 의미하지 않는다.

## 시작 상태와 변경 분리

- 작업 폴더: `/Users/mac/quickemu/quickgui`
- 시작 브랜치: `personal/apple-silicon`
- 시작 HEAD: `fcee3f121bb61ea7c0114b0362b6d64632a1e1cf`
- 시작 시 `git status --short`: ` M pubspec.lock` 한 건. 기존 사용자 변경이며 되돌리거나 이번 수정에 커밋하지 않았다.
- 공통 기준: `origin/integration/stabilization`, `ae57d7dc7fdf8f4cdb1770550a9b1f446b5f2ca6`.
  Toolchain, CommandRunner 및 관련 기존 테스트는 개인 브랜치와 같았다.
- 공통 worktree: `/Users/mac/quickemu/quickgui-m1-common`, 브랜치 `pr/macos-homebrew-path`.
- 공통 수정 커밋: `dc51dd011750392854306feefacf4ae607d1d578`.
  `lib/src/services/toolchain.dart`와 `test/toolchain_test.dart`만 포함한다.
- 개인 브랜치 반영: `git cherry-pick -x dc51dd011750392854306feefacf4ae607d1d578`,
  코드 검증 SHA는 `fb94a516a2d0502c7b2f35836567dc8d62f2867d`.
  개인 기능·운영 기록은 공통 후보에 넣지 않았다. 원격 push·upstream PR 제출은 수행하지 않았다.

개인 브랜치의 검증 대상은 위 코드 SHA와 **시작 시부터 존재하던 lockfile 변경을 포함한 작업 트리**다.
기존 변경은 다음과 같으며, 이번 작업에서는 패키지를 업그레이드하지 않았다.

| 패키지 | HEAD의 lockfile | 시작 시 작업 트리의 lockfile |
| --- | --- | --- |
| dio | 5.11.0 | 5.11.1 |
| dio_web_adapter | 2.2.1 | 2.2.2 |
| platform | 3.1.6 | 3.2.0 |

`shasum -a 256 pubspec.lock` 기준:

- 개인 작업 트리: `c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` (시작 시, 반영 후, 전체 검증·빌드 후 동일).
- 공통 후보: `57d412434d34228eb7cb1901e92e697621ba8329504fd2f1d2a01231d424aeb6` (커밋된 lockfile 그대로).
- 두 폴더 모두 `flutter pub get --enforce-lockfile`로 의존성을 준비했다.

## 실행 환경

| 항목 | 실제 확인값 |
| --- | --- |
| CPU / 아키텍처 | Apple M1 / `arm64` |
| RAM | 8 GiB (`8589934592` bytes) |
| macOS | 26.6.2, build 25G83 |
| Flutter | 3.47.2 stable, framework `d3b14c8769`, `/Users/mac/develop/flutter` |
| Dart | Flutter 번들 3.13.2 |
| Xcode | 26.6, build 17F113 |
| CocoaPods | 1.17.0, `/opt/homebrew/bin/pod` |
| Homebrew Bash | 5.3.15(1)-release, aarch64, `/opt/homebrew/bin/bash` |
| Quickemu / Quickget | 각각 4.9.9, `/opt/homebrew/bin/quickemu`, `/opt/homebrew/bin/quickget` |

실행한 환경 명령: `uname -m`, `sw_vers`, `sysctl -n hw.memsize`,
`sysctl -n machdep.cpu.brand_string`, `flutter --version`, `flutter doctor -v`,
`flutter devices`, `xcodebuild -version`, `pod --version`,
`/opt/homebrew/bin/bash --version`, `quickemu --version`, `quickget --version`.

`flutter devices`는 `macos / darwin-arm64`를 인식했다.
`flutter doctor -v`는 전체 정상 상태가 아니다. Android 라이선스 상태 미확인과
Xcode의 Simulator runtime 목록 조회 실패를 보고했다. 이 항목은 이번에 변경하지 않았다.
macOS desktop 빌드 결과는 아래 표에 별도로 기록한다.

## 오류 재현과 원인

수정 전 다음 명령은 **각각 exit 1**이며 동일한 메시지를 출력했다.

```sh
/usr/bin/env PATH=/bin:/usr/bin:/opt/homebrew/bin /opt/homebrew/bin/quickget --version
/usr/bin/env PATH=/bin:/usr/bin:/opt/homebrew/bin /opt/homebrew/bin/quickemu --version
```

```text
Sorry, you need bash 4.0 or newer to run this script.
```

설치된 Quickget의 shebang은 `#!/usr/bin/env bash`다. 기존 Toolchain은
부모 PATH 뒤에 Homebrew 경로를 추가하므로 `/bin` 또는 `/usr/bin`이 앞에 있으면
오래된 macOS Bash를 선택한다. Quickget 실행 파일 자체를 절대 경로로 찾아도
`env bash`의 인터프리터 선택은 자식 환경의 PATH를 따르므로 오류를 해결하지 못한다.

`CommandRunner.start`는 이미 `environment: environment`와
`includeParentEnvironment: false`를 사용한다. 목록 조회·다운로드·VM 실행·개인 backend 설정 검사도
Toolchain 환경을 전달한다. 따라서 실행부를 Bash로 감싸거나 UI를 변경하지 않고
공통 Toolchain의 PATH만 수정했다. 오류의 `Command: command`는
`CommandResult.requireSuccess()`가 예외에 넣는 일반 실행 이름이며,
별도의 `command` 셸 명령 실행 실패를 의미하지 않는다.

## 수정 동작과 회귀 검사

macOS에서는 첫 Homebrew 또는 시스템 경로 위치에 `/opt/homebrew/bin`, `/usr/local/bin`을
중복 없이 배치한다. 시스템 경로는 `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`이다.
그보다 앞에 사용자가 둔 사용자 지정 디렉터리와 나머지 디렉터리의 상대 순서는 유지한다.
Linux의 PATH 처리 및 명시적 backend 실행 경로 설정은 그대로다.

예를 들어 `/custom tools/bin:/bin:/another/bin:/usr/bin`은
`/custom tools/bin:/opt/homebrew/bin:/usr/local/bin:/bin:/another/bin:/usr/bin:…`이 된다.
이 환경을 도구 탐색과 자식 프로세스가 함께 사용하므로 자식의 `env bash`에도 적용된다.
부모 터미널의 PATH나 로그인 셸 설정은 수정하지 않았다.

새 테스트는 시스템 디렉터리 4종의 우선순위, 사용자 지정 경로, 이미 앞선 Homebrew,
빈/누락 PATH, Linux 순서, 호출자가 전달한 환경 보존을 확인한다.
실제 macOS Bash 검사에서는 공백이 있는 임시 스크립트의 `env bash` shebang과
그 스크립트가 다시 실행하는 `env bash`가 모두 Bash 4 이상을 사용하고,
`a value; $(not-a-command)` 인자가 셸 평가 없이 보존되는지 확인한다.
이 검사는 macOS와 Homebrew Bash가 필요하며 이 M1에서는 skip 없이 실행됐다.

수정 전 코드에 최초 새 테스트 10개를 적용했을 때 **3개 통과, 7개 실패**였다.
그중 실제 shebang 검사는 위 Bash 오류로 실패했다. 수정 후 10개 모두 통과했다.
후속 opt-in 검사 1개는 설치된 Quickemu/Quickget의 `--version`을
시스템 우선 PATH와 Homebrew가 없는 최소 PATH에서 각각 실행한다.

## 실제 검증 결과

각 폴더에서 다음 명령을 실행했다.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build macos --release --no-pub
```

| 검사 | 공통 `dc51dd0` | 개인 `fb94a51` + 기존 lockfile 변경 |
| --- | --- | --- |
| lockfile 강제 의존성 설치 | PASS | PASS |
| format | PASS, 51 files / 0 changed | PASS, 62 files / 0 changed |
| analyze | PASS, No issues found | PASS, No issues found |
| 전체 test | PASS, 40 passed / 3 skipped | PASS, 53 passed / 4 skipped |
| macOS release 빌드 | PASS, 46.6 MB | PASS, 46.7 MB |
| runner / App.framework 아키텍처 | 각각 x86_64, arm64 | 각각 x86_64, arm64 |
| 문제 PATH의 실 backend·catalog 검사 | PASS, 12 passed | PASS, 12 passed |

전체 테스트의 skip은 opt-in 외부 실행 검사다. 공통 후보는 실제 VM·catalog·추가 backend 검사,
개인 후보는 이에 이미지 다운로드 검사가 더해진다. UI 회귀 테스트도 전체 테스트에 포함되어
기존 화면 구성과 반복 화면 전환을 검사했다. UI 소스는 변경하지 않았다.

문제가 발생하던 PATH에서 실제 backend와 catalog를 확인하는 명령:

```sh
/usr/bin/env PATH=/bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin \
  QUICKGUI_REAL_CATALOG_TESTS=1 \
  /Users/mac/develop/flutter/bin/flutter test --no-pub \
  test/toolchain_test.dart test/real_catalog_test.dart
```

실 backend 검사는 각 Toolchain 환경에서 두 backend의 버전 호출이 exit 0인지 확인한다.
catalog 검사는 실제 Quickget `--list-csv`를 실행하고 20개를 넘는 OS 및 각 OS의
비어 있지 않은 버전 목록을 파싱하는지 확인한다. VM이나 게스트 이미지를 생성하지 않는다.

빌드 아키텍처 확인 명령:

```sh
lipo -archs build/macos/Build/Products/Release/quickgui.app/Contents/MacOS/quickgui
lipo -archs build/macos/Build/Products/Release/quickgui.app/Contents/Frameworks/App.framework/App
```

양쪽 빌드는 `window_size`의 Swift Package Manager 미지원 경고를 남겼지만 exit 0으로 완료됐다.
공통 빌드에는 Flutter Assemble의 출력 미지정 Run Script 경고도 있었다.
의존성 변경으로 경고를 숨기지 않았다. 개인 release 앱 위치는
`/Users/mac/quickemu/quickgui/build/macos/Build/Products/Release/quickgui.app`이다.

검증 후 `git diff --check`는 통과했다. 공통 worktree는 clean이며,
개인 브랜치에서는 기존 `pubspec.lock` 변경을 제외한 코드 수정과 이 기록을 별도 커밋으로 분리했다.

## 남은 검증 범위

- Finder에서 release 앱을 열어 직접 조작하는 수동 검토는 수행하지 않았다.
  이번 검증은 문제 PATH를 명시한 실제 자식 프로세스 검사와 위젯 테스트다.
- 실제 VM 부팅·다운로드·게스트 설치·SSH·SPICE·ARM 게스트 지원은 이번에 검사하지 않았다.
- Homebrew Bash 자체가 없는 호스트를 자동 복구하지 않는다. 사용자가 PATH 맨 앞의
  사용자 지정 디렉터리에서 별도 Bash를 의도적으로 우선한 경우도 강제로 교체하지 않는다.
- Linux PATH 순서는 테스트했지만 이번 M1 작업에서 Linux 실행·빌드를 수행하지 않았다.
- 서명/notarization과 원격 CI는 실행하지 않았다.
