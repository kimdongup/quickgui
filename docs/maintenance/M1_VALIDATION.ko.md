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

## 2026-09-09 후속: ARM 선택과 실제 이미지 다운로드 경로

이 절은 위 PATH 수정 이후의 개인 기능 검증이다. 시작 HEAD는 `230f2d6`, 브랜치는
`personal/apple-silicon`이다. OS 선택에서 macOS Intel x64 / Apple Silicon ARM64와
Windows x64 / ARM64를 구분하고 VERSION 제목에도 표시한다.
사용법과 저장 경로는 [ARM_DOWNLOADS.ko.md](ARM_DOWNLOADS.ko.md)를 따른다.

Windows ARM64는 사용자가 제공한
[Microsoft 공식 페이지](https://www.microsoft.com/en-us/software-download/windows11arm64)에서
언어별로 발급받은 ISO 링크를 앱에 붙여 넣어 다운로드한다.
macOS ARM64는 Apple `VZMacOSRestoreImage.fetchLatestSupported`가 반환한 호환 IPSW를 다운로드한다.
ARM 다운로드는 설치 이미지 저장까지만 구현했으며 `.conf`, VM 디스크, 설치 실행기는 생성하지 않는다.
기존 x64 Quickget 경로는 `--arch amd64`를 명시해 전역 ARM 설정과 혼동되지 않도록 했다.

| 명령/검사 | 실제 결과 |
| --- | --- |
| `flutter analyze --no-pub` | PASS, No issues found |
| `flutter test --no-pub test/arm_media_test.dart test/arm_media_widget_test.dart` | PASS, 13 tests |
| `flutter test --no-pub` | PASS, 66 passed / 4 opt-in skipped |
| 영문 안내 추가 후 `flutter test --no-pub test/arm_media_widget_test.dart` | PASS, 3 tests, 새 안내의 번역 누락 로그 해소 |
| `flutter build macos --release --no-pub` | PASS, 47.2 MB |
| release runner `lipo -archs` | x86_64 arm64 |
| release 앱 entitlement 조회 | `com.apple.security.virtualization = true` 확인 |
| 아래 Swift probe | PASS, Apple API에서 macOS 26.6.2 / build 25G83 반환 |
| 반환된 공식 IPSW URL의 `Range: bytes=0-3` 요청 | PASS, HTTP 206, 4 bytes, `50 4b 03 04` |
| 기존 사용자 lockfile SHA256 | `c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` 유지 |

회귀 검사는 x64/ARM64 선택 분리, 전역 ARM 설정과 x64 인자의 충돌 방지, 잘못된 주소 거부,
실제 로컬 HTTP 서버를 통한 ISO/IPSW fixture 전체 전송, 기존 파일 보존, 공식/비공식 리다이렉트,
HTTP 오류·HTML 응답·잘못된 헤더·전송 중단, 취소와 임시 파일 정리, macOS 조회 실패 후 재시도를 포함한다.
로컬 fixture는 전송 상태 검사용 데이터이며 실제 설치 가능한 OS 이미지가 아니다.

Apple 조회는 앱에 포함한 동일한 `RestoreImageSource.swift`를 다음처럼 별도 프로그램으로 실행했다.
Swift 캐시 및 네트워크 검사는 sandbox 밖 실행 승인을 받아 수행했다.

```sh
mkdir -p /tmp/quickgui-arm-validation
xcrun swiftc macos/Runner/RestoreImageSource.swift tool/check_restore_image.swift \
  -o /tmp/quickgui-arm-validation/check-restore-image
codesign --force --sign - --entitlements macos/Runner/Release.entitlements \
  /tmp/quickgui-arm-validation/check-restore-image
/tmp/quickgui-arm-validation/check-restore-image
```

실제 반환 URL은 다음 공식 Apple 주소였다.

```text
https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-75212/A2A24B94-1FC1-45A3-93F7-C51B02AF1F4D/UniversalMac_26.6.2_25G83_Restore.ipsw
```

이 주소에 `curl --range 0-3 --max-filesize 1024 --max-time 30`으로 제한된 요청을 보냈다.
응답은 `Content-Range: bytes 0-3/19772231540`, `Content-Length: 4`였다.
약 19.8 GB의 전체 IPSW는 다운로드하지 않았다. Microsoft에서 새 언어별 링크를 발급받아
전체 ISO를 받는 실검증도 수행하지 않았다. 실제 파일의 전체 SHA256, 설치, 부팅은 미검증이다.
네이티브 GUI 수동 조작을 수행했다고 주장하지 않으며, 위젯 검사·앱 빌드·동일 Swift 소스의
실제 Apple 조회를 구분한다. 기존 `window_size`의 Swift Package Manager 경고는 남아 있다.

이 확장은 개인 브랜치에만 포함하며 공통 후보 `pr/macos-homebrew-path`에는 넣지 않는다.
Flutter 3.47.2/Dart 3.13.2 및 기존 의존성 버전을 유지했고 원격 push/PR 제출은 수행하지 않았다.

### 최종 커밋과 격리 빌드

최종 기능 커밋은 `bdd47d0bd64d03006a8dcdf02de8fd59388150d1`이다.
사용자가 지정한 `/en-us/software-download/windows11arm64` 주소를 포함한다.
원본 작업 폴더의 마지막 빌드 시도는 `build.db` 잠금으로 실패했다.
프로세스 확인에서 같은 폴더의 `flutter run -d macos`가 발견되어 해당 실행을 종료하지 않고
`/tmp/quickgui-arm-release`에 위 커밋의 detached worktree를 만들었다.
기존 사용자 lockfile을 이 폴더에도 복사해 동일한 패키지 조합을 유지했다.

이 격리 폴더에서 `flutter pub get --enforce-lockfile`, `flutter analyze --no-pub`,
`flutter test --no-pub`, `flutter build macos --release --no-pub`를 다시 실행했다.
모두 PASS: 분석 0, 66 passed / 4 skipped, 47.2 MB release 앱.
검증 후 lockfile SHA256은 위 값과 동일하다. 따라서 DB 잠금 실패를 빌드 통과로 바꾸어 기록하지 않고,
별도 폴더에서 성공한 최종 빌드와 구분한다.

최종 앱은 실행 중인 앱의 빌드 폴더를 덮어쓰지 않고 다음 경로에 복사했다.

```text
/Users/mac/quickemu/quickgui/dist/arm-downloads-bdd47d0/quickgui.app
```

복사본의 runner와 App.framework에서 각각 `x86_64 arm64`를 확인했다.
이 앱은 로컬 검토용 빌드이며 원격 배포·notarization은 수행하지 않았다.

### 사용자 다운로드 완료 후 전체 IPSW 검증

2026-09-09. 사용자가 다운로드 완료와 저장 폴더를 보고했다.
이후 다음 로컬 파일을 직접 읽어 크기·전체 SHA256·내부 manifest를 확인했다.

```text
/Users/mac/quickemu/Install Media/macos-arm64-IgBrV2/macOS-Apple-Silicon.ipsw
```

| 확인 항목 | 실제 결과 |
| --- | --- |
| 파일 크기 (`stat -f '%z bytes'`) | 19,772,231,540 bytes, 앞서 확인한 Apple 응답의 전체 크기와 일치 |
| 전체 파일 `shasum -a 256` | `885503b7f4b06609e9a512f2befd40f59730640a3f1233e3892d60affdd51c95` |
| Apple 응답의 `x-amz-meta-digest-sha256`와 비교 | PASS, 위 SHA256과 정확히 일치 |
| ZIP 내부 `BuildManifest.plist` | ProductVersion 26.6.2, ProductBuildVersion 25G83 |
| manifest의 SupportedProductTypes | Macmini9,1 및 VirtualMac2,1 포함 |

따라서 앞 절의 macOS IPSW 전체 다운로드·SHA256 미검증 상태는 **완료 파일의 무결성 검증 PASS**로 갱신한다.
다운로드 과정의 GUI 조작은 사용자 보고이며, 직접 관찰한 범위는 저장된 전체 파일 검사다.
원본 IPSW는 변경하지 않았다. 이 시점에는 Windows ARM64 ISO 전체 다운로드와 ARM VM 생성·설치·부팅은 별도 단계였다.

## Apple Silicon VM 생성·설치 연결 (2026-09-09)

사용자의 후속 요청으로 이전 권장 순서와 별개로 macOS ARM backend를 먼저 구현했다.
`personal/apple-silicon`, 시작 HEAD `f5fb3bc`. 기존 사용자 lockfile 및 다운로드 완료 기록을 보존했다.
공통 `pr/macos-homebrew-path` worktree는 변경하지 않았다.

다운로드/기존 IPSW → 호환성·자원 확인 → 독립 `.quickgui-macvm` 생성 → 설치 진행률/취소 →
Manager Run/화면 다시 열기/종료를 연결했다. Apple VM은 Quickemu를 실행하지 않는다.
네이티브 설치 상태·고유 식별 정보·MAC·UEFI 보조 저장소를 보존하며 기존 폴더 덮어쓰기,
공유 파일/심볼릭 링크 저장소, 같은 VM 동시 실행과 미완료 VM 실행을 방지한다.

| 검증 | 실제 결과 |
| --- | --- |
| Apple API로 로컬 IPSW 검사 | macOS 26.6.2 / 25G83, 최소 CPU 2개·RAM 4GiB, 이 호스트 최대 선택 7개·6GiB |
| 실제 새 VM 생성·설치 | `/Users/mac/quickemu/macOS-Apple-Silicon.quickgui-macvm`, CPU 2개·4GiB·64GiB sparse disk, `VZMacOSInstaller` 성공, metadata `ready` |
| 새 프로세스에서 90초 부팅 | `running`, macOS 최초 언어 선택 화면을 실제 VM framebuffer에서 캡처 |
| 수정 후 새 프로세스 30초 부팅 | `running`, 중복 start 거부, 창 닫기/다시 열기 성공, 강제 중지 완료 후 즉시 `stopped` |
| `flutter analyze --no-pub` | PASS, No issues found |
| `flutter test --no-pub` | PASS, 73 passed / 4 external opt-in skipped; 새 Flutter 검사 7개 |
| `tool/test_mac_vm_store.swift` | PASS, 22 checks: 이름/기존 폴더/디스크 보호, 동시 잠금·즉시 해제, sparse 용량, symlink/hardlink 거부, 상태·식별 정보 유지 |
| `flutter build macos --release --no-pub` | PASS, `/tmp/quickgui-vm-release` 격리 worktree에 현재 변경을 복사해 빌드, 47.7MB |
| 의존성 | `pub get --enforce-lockfile` 통과, 기존 lockfile SHA256 `c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` 유지 |

두 차례 부팅 후 hardware-model SHA256 `976e66740c64041cf9f127588f93eabf7efb9e7d3cbaee9582bcded88ba5e8d3`,
machine-identifier `0351d86ffe1560c45423be9ccf70c4fb63649a99400f1183784a5c7173a2e730`을 확인했다.
실제 이미지: [최초 설정 화면](evidence/macos-arm64-first-setup.png).
로컬 앱: `/Users/mac/quickemu/quickgui/dist/apple-vm/quickgui.app`.
기존 `flutter run`을 종료하거나 빌드 디렉터리를 덮어쓰지 않았다.

```sh
xcrun swiftc macos/Runner/MacVMStore.swift macos/Runner/AppleVirtualMachine.swift \
  tool/check_apple_vm.swift -o /tmp/quickgui-arm-validation/check-apple-vm
codesign --force --sign - --entitlements macos/Runner/Release.entitlements \
  /tmp/quickgui-arm-validation/check-apple-vm
/tmp/quickgui-arm-validation/check-apple-vm inspect \
  '/Users/mac/quickemu/Install Media/macos-arm64-IgBrV2/macOS-Apple-Silicon.ipsw'
/tmp/quickgui-arm-validation/check-apple-vm install /Users/mac/quickemu macOS-Apple-Silicon \
  '/Users/mac/quickemu/Install Media/macos-arm64-IgBrV2/macOS-Apple-Silicon.ipsw'
/tmp/quickgui-arm-validation/check-apple-vm boot \
  /Users/mac/quickemu/macOS-Apple-Silicon.quickgui-macvm 30 /tmp/quickgui-arm-validation/apple-vm-reopen.png
xcrun swiftc macos/Runner/MacVMStore.swift tool/test_mac_vm_store.swift \
  -o /tmp/quickgui-arm-validation/test-mac-vm-store
/tmp/quickgui-arm-validation/test-mac-vm-store
```

첫 설치 실험에서 디렉터리 URL 표현 차이로 자기 VM을 외부 잠금으로 잘못 표시했다.
설치는 정상 완료했지만 진행률 관측은 실패했다. 경로 비교를 수정했으며 후속 재실행에서 `running`을 확인했다.
첫 중지 직후에는 callback의 객체 수명 때문에 잠금이 잠깐 유지됐다. 명시적 잠금 해제로 수정했고
최종 재실행에서 종료 callback 안의 즉시 `stopped` 조회를 확인했다. 대화상자 테스트의 animation 대기로 인한
초기 timeout 2개는 프레임 대기 방식을 수정한 후 전체 테스트에서 통과했다.

검증 후 VM은 중지 상태이며 원본 IPSW는 보존했다. VM 실제 사용 공간은 약 23GiB이다.
계정 생성·바탕화면·게스트 내 정상 종료·SSH·오디오/네트워크 실사용과 앱 GUI의 설치 전체 조작은 미검증이다.
네이티브 취소의 실제 설치 중 재현은 아직 없으며, 취소 요청/실행 차단은 Flutter 테스트로 검증했다.
앱 전체 검증과 동일 소스 CLI 검증을 구분한다. 빌드의 기존 `window_size` SPM 및 Run Script 경고는 남아 있다.

## Windows ARM64 생성·설치 연결 (2026-09-09)

사용자의 추가 요청으로 `6abf33b`의 Apple VM 기능에 Windows ARM64 경로를 연결했다.
개인 브랜치는 `personal/apple-silicon`이며 공통 PATH 수정 worktree는 clean 상태로 유지했다.
기존 Apple 전용 Flutter 생성/제어 화면을 `native_vm_*`로 공유하고, 네이티브 실행 채널과 VM 저장소는
macOS/Windows별로 분리했다. Windows는 `.quickgui-winarm`과 QEMU/HVF를 사용한다.

### 실제 ISO와 실행 구성

```text
/Users/mac/Downloads/Win11_25H2_Korean_Arm64_v2.iso
7,951,140,864 bytes
SHA256: 723fdcb737b39a5ec1f4b0eadacf288f1a2c4c4c8c845eb1f6a433cc264bd426
```

전체 로컬 SHA256, ARM64 EFI PE machine `0xaa64`, `boot.wim`/`install.wim`을 확인했다.
위 Windows ISO SHA256은 로컬 계산값이며 Microsoft 게시 체크섬과 대조한 것으로 표시하지 않는다.
원본 ISO와 기존 IPSW는 수정하지 않았다. Windows PE 표시 버전은 `10.0.26100.8037`이었다.

Homebrew QEMU 11.1.1, swtpm 0.10.2, `virt-9.2,highmem=on,gic-version=3`, HVF/host CPU,
CPU 2개·RAM 4GiB·64GiB QCOW2, NVMe, TPM 2.0, RAMFB + VirtIO PCI display,
USB BOT의 명시적 SCSI CD-ROM, user-mode NAT/USB network를 구성했다.
Homebrew 기본 ARM 펌웨어에는 필요한 Secure Boot 지원이 없어 별도 검증 펌웨어를 준비했다.

펌웨어 출처는 [UTM QEMU 고정 커밋](https://github.com/utmapp/qemu/tree/b44153a4b6aabf86edebf92199b14aec26e15d59/pc-bios)이다.
준비 도구는 고정 파일의 다운로드 SHA256과 최종 파일 SHA256을 확인한다. UTM 앱은 설치하지 않았다.

| 파일 | SHA256 |
| --- | --- |
| `edk2-aarch64-secure-code.fd.bz2` 다운로드 | `89206fa3bce0a43161e6d8dc143c6246ac03f095ce9873a1243cdb99efe4ee63` |
| `edk2-arm-secure-vars.fd.bz2` 다운로드 | `4dba10d7c7169b52a7b7bb8e0cef1c0b630312ff13725eff10d4711f21d9f373` |
| VM에 복사할 `uefi-code.fd` | `c85a57de1ac39e550a6529bd66a4214eb1d8c14dcda7e22dedf72566a769fbc7` |
| QCOW2 템플릿을 raw로 변환한 `uefi-vars.fd` | `8203a22c79a52ec6c34320e58bae8a63b890a76bf62167b2e7551e88b974dc77` |

준비 위치: `~/Library/Application Support/Quickgui/Firmware/utm-b44153a4/`.
등록된 키를 수정하지 않으며, 각 VM은 독립 NVRAM·TPM·UUID·MAC을 유지한다.
동일 파일임을 추가 확인하기 위해 공식 UTM 4.7.5 DMG도 읽기 전용으로 검사했다.
DMG SHA256 `a8435c93cfb5f8bbfeea4b134cfad1ac66b67632b75e438c63b1a8ae043bef0e`는
GitHub release asset digest와 일치했고, 내부 ARM 펌웨어는 위 소스 파일과 동일했다. 검사 후 DMG를 분리했다.

### 실제 관찰과 회귀 검증

| 항목 | 결과 |
| --- | --- |
| 폐기 가능한 Windows VM 시작 | PASS: 네이티브 backend, QEMU/HVF/TPM 시작과 QMP `running` 확인 |
| 중복 실행 회귀 | PASS: 두 번째 start 거부 후 원래 VM의 backend 상태와 QMP `running` 유지 |
| 설치 화면 | PASS: Windows 11 한국어 언어/키보드/설치 옵션/제품 키/에디션 선택 화면 |
| Windows 요구 사항 검사 | PASS: Home 선택 후 PC 검사를 통과하여 사용 조건 화면 도달. 요구 사항 우회 레지스트리는 사용하지 않음 |
| 실제 Secure Boot 상태 | PASS: WinPE의 `UEFISecureBootEnabled` 값 `0x1` |
| 실제 디스크/ISO 인식 | PASS: DiskPart에 온라인 64GB 디스크와 UDF CD-ROM 7582MB. 원본 ISO는 읽기 전용 |
| 중지와 정리 | PASS: QMP quit → `stopped`, 잠금/소켓/TPM 정리, 해당 폐기용 VM 폴더 제거 |
| Windows 설치 환경 네트워크 | 미완료: `ipconfig`에 어댑터가 표시되지 않음. 전체 Windows의 드라이버/네트워크 동작으로 확대 해석하지 않음 |
| Flutter 전체 테스트 | PASS: 76 passed / 4 external opt-in skipped. Windows 생성 채널·공간 부족 오류·설치 완료 확인·재발견/실행 회귀 포함 |
| Flutter 분석 | PASS: `flutter analyze --no-pub`, No issues found |
| macOS 저장소 회귀 | PASS: `tool/test_mac_vm_store.swift`, 22 checks |
| Windows 네이티브 회귀 | PASS: `tool/test_windows_vm.swift`, 16 checks. 동시 잠금/잔여 소유 프로세스/메타데이터/설치 완료·원본 경로/광학 장치/두 화면 장치 순서 포함 |
| 펌웨어 준비 회귀 | PASS: Python 3 tests. 변조 다운로드, 변조 기존 파일, symbolic link 거부; 실제 준비와 재실행 시 기존 파일 검증도 성공 |
| 최종 macOS release 빌드 | PASS: 격리 worktree `/tmp/quickgui-vm-release`, 47.8MB. runner/App.framework `x86_64 arm64`, codesign verify 통과 |
| 의존성 보존 | 기존 lockfile SHA256 `c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` 유지. Flutter 3.47.2/Dart 3.13.2 유지 |

증거: [Windows 설치 화면](evidence/windows-arm64-setup.png),
[Secure Boot와 저장 장치 인식](evidence/windows-arm64-secureboot-storage.png).
최종 소스에서도 중복 start 거부 후 한국어 설치 화면을 다시 확인했다.
빌드와 병행한 90초 검사는 WinPE 배경만 표시된 시점에 종료됐으므로 설치 화면 도달로 세지 않았다.
빌드 완료 후 180초 예산으로 재검사해 설치 화면을 확인했다.
최종 앱은 `/Users/mac/quickemu/quickgui/dist/arm-vms/quickgui.app`에 복사했다.
사용자의 실행 중 Flutter 빌드 폴더를 덮어쓰지 않았다. 원격 배포/notarization은 하지 않았다.

### 실패에서 확인한 수정

- ISO를 `usb-storage`의 raw 디스크로 연결했을 때 WinPE에서 RAW 이동식 디스크로 인식되어
  미디어 드라이버 요구 화면이 나타났다. NVMe 자체는 이미 정상 인식했다.
  명시적 `usb-bot` + `scsi-cd`, 충분한 xHCI 포트로 바꾸어 실제 UDF CD-ROM 인식을 확인했다.
- Homebrew 기본 펌웨어에서는 Windows PC 검사에 Secure Boot 미지원이 표시됐다.
  Debian Secure Boot 펌웨어 2025/2026 및 콘솔 템플릿 초기화 실험은 이 호스트에서 부팅이 멈췄다.
  해당 다운로드/템플릿 변경 실험은 최종 코드에서 제거했다.
- UTM Secure Boot 펌웨어에서 RAMFB 단독은 화면이 초기화되지 않았고 VirtIO GPU 단독은
  Windows 부팅이 진행되지 않았다. RAMFB를 첫 화면으로 두고 VirtIO PCI display를 함께 연결한
  구성에서 설치 화면, 요구 사항 검사, Secure Boot 활성화까지 확인했다.
- `highmem=off` 실험은 4GiB RAM의 주소 범위 때문에 QEMU 시작 단계에서 거부됐다. 최종 구성은 `highmem=on`이다.
- 최종 검토에서 중복 start의 오류 처리가 기존 세션까지 정리할 수 있는 경로를 발견했다.
  중복 요청을 정리 경로 진입 전에 거부하도록 수정했고 실제 실행 중 VM에 두 번째 start를 보내
  요청 거부와 원래 VM의 `running` 유지를 확인했다. 이 변경을 포함해 release 앱을 다시 빌드했다.

재현 명령은 다음과 같다. `probe`는 별도 빈 디스크의 부팅 검사이며 Windows를 설치하지 않는다.
생산 생성 경로의 호스트 여유 공간 32GiB 검사를 대신하는 도구가 아니다.

```sh
python3 tool/prepare_windows_arm_firmware.py
xcrun swiftc macos/Runner/MacVMStore.swift macos/Runner/WindowsVMTools.swift \
  macos/Runner/WindowsArmVirtualMachine.swift tool/check_windows_arm_vm.swift \
  -o /tmp/quickgui-arm-validation/check-windows-arm-vm
/tmp/quickgui-arm-validation/check-windows-arm-vm probe \
  /Users/mac/Downloads/Win11_25H2_Korean_Arm64_v2.iso \
  /tmp/quickgui-arm-validation/windows-production.png 180
xcrun swiftc macos/Runner/MacVMStore.swift macos/Runner/WindowsVMTools.swift \
  macos/Runner/WindowsArmVirtualMachine.swift tool/test_windows_vm.swift \
  -o /tmp/quickgui-arm-validation/test-windows-vm
/tmp/quickgui-arm-validation/test-windows-vm
python3 -m unittest discover -s tool -p 'test_windows_firmware.py'
```

현재 호스트 여유 공간은 실행 시점에 약 22–26GiB였다. 새 Windows 전체 설치에 필요한 앱의
32GiB 시작 조건에 못 미쳐 영구 Windows VM 생성과 전체 설치는 진행하지 않았다.
Windows 사용 조건 동의·디스크 선택/복사·OOBE·바탕화면·설치 후 재부팅·정상 종료·네트워크/게스트 드라이버·오디오는 남아 있다.
앱 GUI의 설치 전체 조작과 동일 소스 네이티브 CLI 검증을 구분한다. 사용법은 [WINDOWS_ARM_VM.ko.md](WINDOWS_ARM_VM.ko.md)를 따른다.

## macOS 파일 선택 entitlement 오류 수정 (2026-09-09)

Windows ARM64 생성 화면의 **Choose ARM64 ISO**에서 다음 오류가 발생했다.

```text
Either the Read-Only or Read-Write entitlement is required for this action.
```

실행 중인 Debug 앱에서도 같은 오류 문구를 직접 확인했다. 고정 의존성
`file_picker` 12.2.0 / `file_picker_darwin` 1.1.0의 `MacOSFilePickerHandler.checkEntitlement`
검사는 sandbox 여부와 관계없이 사용자 선택 파일의 read-only 또는 read-write entitlement를 요구한다.
기존 DebugProfile/Release 설정과 배포 앱 서명에는 둘 다 없었다.
앞선 네이티브 CLI의 ISO 검사는 Flutter 파일 선택 플러그인을 통과하지 않아 이 오류를 발견하지 못했다.

공통 기준 `ae57d7d`에서 `pr/macos-file-picker-entitlements` / `c59d53b`를 분리했다.
공통 커밋은 entitlement 파일 2개만 변경하며, 개인 브랜치에는 `1942c4e`로 반영했다.
사용자가 선택한 VM 작업 폴더에는 쓰기도 필요하므로 두 빌드 설정에
`com.apple.security.files.user-selected.read-write = true`를 추가했다.
개인의 virtualization 및 Debug JIT entitlement를 보존했고 App Sandbox 설정은 바꾸지 않았다.
의존성·Flutter SDK·플러그인 소스·기존 UI는 변경하지 않았다.

| 실제 검사 | 결과 |
| --- | --- |
| 두 entitlement plist 구문 | PASS: `plutil -lint` |
| 격리 worktree release 빌드 | PASS: `flutter build macos --release --no-pub`, 47.8MB |
| 격리 worktree debug 빌드 | PASS: `flutter build macos --debug --no-pub` |
| Debug/Release 최종 서명 | PASS: `codesign --verify --deep --strict`; 실제 서명에서 파일 read-write, virtualization, Debug JIT 값 확인 |
| 분석 | PASS: `flutter analyze --no-pub`, No issues found |
| 실제 release 앱 파일 선택 | PASS: Manager → Create Windows ARM64 VM → Choose ARM64 ISO → macOS Open 창 표시 |
| 실제 ISO 반환·검사 | PASS: `/Users/mac/Downloads/Win11_25H2_Korean_Arm64_v2.iso` 선택 후 Windows ARM64 정보와 CPU 2개/RAM 4GiB/64GiB 디스크 설정, Create and install 버튼 표시. entitlement 오류 재발 없음 |
| lockfile 보존 | SHA256 `c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` 유지 |

수정 앱을 `dist/arm-vms/quickgui.app`에 갱신했다. 실행 중인 VM이 없음을 확인하고
오류가 난 이전 Debug 앱을 정상 종료한 뒤 이 release 앱을 실행해 위 GUI 검사를 수행했다.
검증 후 ISO가 선택된 생성 화면을 열어두었다. 새 Windows VM/디스크를 만들거나 설치를 시작하지 않았다.
호스트 여유 공간은 약 23GiB로, 설치 시작의 32GiB 조건에 여전히 못 미친다.
이번 변경은 앱 서명 설정이므로 기존 위젯 테스트를 추가·반복하지 않고 실제 서명과 네이티브 파일 선택을 검증했다.

## VM·설치 파일 삭제 기능 (2026-09-09)

개인 기준 0e7565a에서 후속 구현했다. 공통 PATH 및 file-picker entitlement 후보는 변경하지 않았다.
Manager에 native VM별 Delete VM과 Installation files 화면을 추가했다.
다운로더에서도 설치 파일 관리로 이동할 수 있다. 확인 창에는 실제 경로·디스크 할당 크기를 표시하며,
이름을 정확히 입력해야 영구 삭제를 실행한다. VM 폴더 밖의 원본 설치 이미지는 별도 삭제 대상이다.
사용법과 검사 범위는 [STORAGE_MANAGEMENT.ko.md](STORAGE_MANAGEMENT.ko.md)에 정리했다.

파일 잠금/소유 프로세스, 알려진 작업 폴더의 native VM 및 Quickemu 리터럴 참조를 확인한다.
설치 미디어는 inode에 대응하는 앱 전용 공유 잠금으로 사용 중 삭제를 막는다.
확인 시 파일 목록과 식별 정보·수정 시각·크기의 토큰을 만들고 삭제 직전 다시 검사한다.
같은 부모 폴더의 임시 이름으로 옮긴 뒤 디렉터리 핸들을 사용해 삭제하며 symbolic link를 따라가지 않는다.
목록·미리보기·삭제 I/O는 별도 직렬 큐에서 처리한다. 삭제 검사/실행 중 새 ARM VM 시작,
실제 삭제 중 앱 정상 종료를 막는다.

| 실제 검사 | 결과 |
| --- | --- |
| Flutter 전체 회귀 | PASS: 81 passed / 4 external opt-in skipped |
| 최종 삭제·다운로더 위젯 재검사 | PASS: 8 tests. 취소, 다른 이름 입력, 정확한 토큰 전달, 목록 갱신, 사용 중/변경된 파일 오류, 비활성 VM에만 삭제 노출 포함 |
| macOS 저장소 기존 회귀 | PASS: 22 checks |
| Windows 기존 회귀 | PASS: 16 checks |
| 실제 파일시스템 삭제 회귀 | PASS: 26 checks. 시험 VM/ISO 실제 제거, 원본·무관 파일 유지, 잠금/잔여 PID/참조/심볼릭 링크/하드링크/변경된 파일/이전 작업 폴더 보호, 파일 목록 재발견 |
| 실제 QEMU/HVF/TPM 수명 검사 | PASS: 합성 시험 미디어로 running → 사용 중 삭제 잠금 거부 → 중복 start 거부 → stopped → 미디어 잠금 해제 → 시험 폴더 제거 |
| 분석·포맷 | PASS: 분석 0, 수정 Dart 파일 포맷 검사 통과 |
| 최종 release 빌드 | PASS: 격리 worktree /tmp/quickgui-vm-release, 48.1MB |
| 최종 앱 검증 | PASS: codesign verify, runner/App.framework의 x86_64 arm64 |
| 실제 VM 확인 창 | PASS: 설치된 macOS VM의 경로·22.9GiB·이름 입력란 표시. Cancel 후 기존 VM 유지 |
| 실제 설치 파일 화면 | PASS: IPSW 18.4GiB 표시, Add installation file 선택 창을 통해 Windows ISO 추가 후 7.4GiB 항목 표시 |
| 의존성 | Flutter 3.47.2 및 기존 lockfile SHA256 c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a 유지 |

초기 실제 GUI 검사에서 Downloads 자동 열람이 macOS 접근 대기에 걸렸고,
동기 파일 열람 때문에 UI도 멈췄다. 프로세스 sample에서 목록 열람의 open 대기를 확인했다.
파일 I/O를 화면 스레드에서 분리하고, Downloads 등 외부 파일은 파일 선택 창을 통해 등록하도록 수정했다.
최종 앱에서는 목록 표시와 파일 추가가 멈춤 없이 완료됐다.

첫 미디어 보호 구현은 이미지 자체에 flock을 걸어 QEMU의 consistent read 잠금과 충돌했다.
실제 VM 시작 실패 로그에서 이를 확인했다. QEMU의 잠금을 끄지 않고, 별도의 사용자 전용
inode별 잠금 파일로 분리했다. 이후 실제 QEMU 프로세스의 시작·중지와 앱 잠금 해제를 재검증했다.
최종 수명 검사의 ISO는 별도로 만든 합성 파일이며 Windows 설치·부팅 성공 검사로 표시하지 않는다.
이전 실제 Windows 설치 화면 검증과 이번 삭제 보호 회귀 검사를 구분한다.

다음 명령은 시험 파일만 생성·삭제한다.

    xcrun swiftc macos/Runner/MacVMStore.swift macos/Runner/NativeStorageStore.swift tool/test_native_storage.swift -o /tmp/quickgui-arm-validation/test-native-storage
    /tmp/quickgui-arm-validation/test-native-storage
    xcrun swiftc macos/Runner/MacVMStore.swift macos/Runner/WindowsVMTools.swift macos/Runner/WindowsArmVirtualMachine.swift tool/check_windows_arm_vm.swift -o /tmp/quickgui-arm-validation/check-windows-arm-vm
    /tmp/quickgui-arm-validation/check-windows-arm-vm lifecycle /tmp/quickgui-arm-validation/storage-lease
    flutter test --no-pub test/native_storage_widget_test.dart test/arm_media_widget_test.dart

최종 앱은 /Users/mac/quickemu/quickgui/dist/arm-vms/quickgui.app에 갱신하고
Installation files 화면을 열어두었다. 실제 사용자 파일의 영구 삭제 버튼은 누르지 않았다.
검증 종료 시 기존 macOS VM, 19,772,231,540바이트 IPSW, 7,951,140,864바이트 Windows ISO를 확인했다.
실제 제거 작업은 별도의 시험 파일로 수행했다. 실패한 실험의 임시 VM과 합성 미디어도 정리했다.
