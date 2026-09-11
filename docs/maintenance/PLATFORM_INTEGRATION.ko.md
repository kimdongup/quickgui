# Intel/M1 개인 후보 통합 검토

2026-09-10, Intel Mac에서 `personal/platform-integration`을 검토한다.

## 기준과 완료된 게스트 검증

| 기준 | 내용 |
| --- | --- |
| Intel `personal/preview` | `64cfd5991b889d7ff268a41362bed498229ccc7c`: macOS x64 설치·구동 사용자 확인 |
| M1 `personal/apple-silicon` | `f3f5c2bd807f0dbb7dc0e250e7c1996a68340586`: Windows ARM64 설치 후 앱 재실행 검증 |
| 공통 조상 | `fcee3f121bb61ea7c0114b0362b6d64632a1e1cf` |
| 마지막 M1 앱 코드 | `0517cf2`: Windows ARM64 네트워크 드라이버 수정 |

Windows ARM64의 초기 설정·바탕화면·입력·HTTPS·정상 종료/부팅은 사용자 확인 완료다. M1 실행 기록은 설치 완료 표시 저장, Quickgui 완전 종료·재실행, 같은 VM의 설치 ISO 없는 실행과 외부 TCP 연결을 확인했다. 이번 사용자는 macOS ARM의 바탕화면·재부팅·SSH도 직접 검증했다고 확인했다. 확인 주체와 상세 근거는 [M1 검증 기록](M1_VALIDATION.ko.md)을 따른다.

merge `f3b1900`으로 양쪽 브랜치의 이력을 보존했다. 충돌은 `STATUS.ko.md`, `GUEST_VALIDATION.ko.md`의 검증 상태에만 발생했다. 각 호스트의 최신 사실과 macOS ARM의 추가 사용자 확인을 기록했으며, merge 시 앱·의존성 코드는 M1 후보와 동일했다. 이어진 코드 검토에서 아래 삭제 보호 오류를 재현하여 별도 수정한다.

## 통합 검토에서 발견한 삭제 보호 오류

설치 파일 관리의 Quickemu 참조 검사가 `iso="..."`만 인식하고 유효한 `export iso="..."`를 건너뛰었다. 따라서 기존 x64 VM이 참조하는 이미지도 미리보기·삭제 검사를 통과할 수 있었다. 새 fixture를 수정 전 코드에서 실행하면 기존 17개 확인 뒤 `exported Quickemu ISO reference protects media`가 실패하고 exit 1이었다.

수정은 Bash를 실행하지 않고 리터럴 `NAME=value`와 안전한 `export`·`declare`·`typeset`·`readonly` 접두사를 검사한다. `source`·`.`·명령 치환·실행문·여러 대입문·해석할 수 없는 옵션·비어 있지 않은 `extra_args`는 추가 참조를 판정할 수 없어 삭제를 거부한다. 일반 VM 실행은 바꾸지 않는다. 복잡한 설정을 가진 작업 폴더에서 설치 파일 삭제가 제한되는 것은 이 보호 동작의 범위다.

수정 후 57개 실제 파일시스템 확인이 성공했다. 삭제 확인 뒤 새로운 export 참조가 추가된 경우와 원본 bytes 보존, 인용된 세미콜론·공백·한국어 경로, 구성을 실행하지 않는 것, 무관한 파일의 정상 삭제도 포함한다. 사용자 VM·설치 파일 대신 임시 fixture를 사용했다. 같은 Swift 검사를 macOS CI에 추가했다.

## Intel 검사

별도 worktree `/private/tmp/quickgui-platform-integration-20260910`에서 커밋된 lockfile로 검사한다. 기존 Intel 작업 폴더의 사용자 변경, M1의 미커밋 lockfile, 실행 중인 VM과 설치 이미지는 건드리지 않는다.

Flutter 3.47.2 / Dart 3.13.2, 커밋된 lockfile SHA256 `57d412434d34228eb7cb1901e92e697621ba8329504fd2f1d2a01231d424aeb6`를 사용했다. lockfile은 변경하지 않았다.

| 검사 | Intel 결과 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | PASS, 커밋된 lockfile 유지 |
| `dart format --output=none --set-exit-if-changed lib test` | PASS, 77 files / 0 changed |
| `flutter analyze --no-pub` | PASS, No issues found |
| `flutter test --no-pub --reporter expanded` | PASS, 82 passed / 4 external opt-in skipped |
| `QUICKGUI_REAL_CATALOG_TESTS=1 flutter test --no-pub --reporter expanded test/toolchain_test.dart test/real_catalog_test.dart` | PASS, 12 tests. 실제 Intel Homebrew Bash·Quickemu·Quickget과 catalog |
| Swift native storage fixture | PASS, 57 checks. 수정 전 export 참조 재현은 실패 |
| `flutter build macos --release --no-pub` | PASS, 48.2 MB |
| `codesign --verify --deep --strict` | PASS, 생성된 앱 서명 검증 |
| runner / App.framework 아키텍처 | 각각 x86_64 / arm64 |
| workflow YAML·문서 링크·`git diff --check` | PASS |

Flutter 검사는 두 후보의 앱을 합친 `f3b1900`에 대해 실행했고, 뒤이은 Swift 삭제 보호 수정은 57개 네이티브 검사로 검증했다. 전체 Flutter 테스트의 네 가지 opt-in은 별도 실행 조건이며, 위 실제 backend/catalog 검사는 따로 실행했다. 이번에 사용자 VM을 다시 설치하거나 M1 원격 검증을 수행하지 않았다.

로컬 Flutter 로그는 `/private/tmp/quickgui-platform-integration-{tests,catalog,build}.log`에 있다. 기존 `window_size`의 Swift Package Manager 미지원 안내와 출력이 지정되지 않은 Run Script 경고는 남아 있으나 CocoaPods를 사용한 release 빌드는 exit 0이었다. 생성된 앱을 기존 설치 앱 위에 배포하거나 실제 사용자 VM으로 실행하지 않았다. 기존 M1 CI 성공과 이번 Intel 검사 결과를 구분한다.

## 공통 PR 경계와 다음 단계

- 공통 PATH `dc51dd0`의 [CI](https://github.com/kimdongup/quickgui/actions/runs/34506027934)와 파일 선택 `c59d53b`의 [CI](https://github.com/kimdongup/quickgui/actions/runs/34506028056)는 분석·테스트·Linux·Nix·macOS 성공, fork의 PPA 단계는 skipped다.
- M1 `f3f5c2b`의 [Build](https://github.com/kimdongup/quickgui/actions/runs/34519762183)와 [실제 Quickemu smoke](https://github.com/kimdongup/quickgui/actions/runs/34519762199)도 성공했다. 통합 후보의 새 CI 결과와 구분한다.
- 두 공통 브랜치는 `integration/stabilization` / `ae57d7d`에서 각각 분기했다. upstream `74949e0`에 그대로 제출하면 PATH는 14커밋·62파일, 파일 선택은 14커밋·63파일이다. [기존 제출 순서](UPSTREAM_PRS.md)에 맞춰 선행 변경이 수용된 뒤 범위를 다시 정리하거나 upstream 기준으로 개별 수정을 이식해야 한다.
- Intel 통합 검사를 통과한 개인 후보는 `personal/preview`로 반영한다. `main` 안정판 승격·공개 릴리스·upstream PR 제출은 별도 단계다.
- 통합 후속에서 Intel macOS 설치 게스트의 SSH 인증·명령·재접속, 같은 디스크의 SPICE 부팅·화면·키 입력·포인터 클릭 및 앱의 조회·접속 준비 서비스를 확인했다. 실제 spicy 창의 결과와 GUI 일반 Run 연동의 제한은 [Intel 연결 기록](MACOS_SPICE_BACKEND.ko.md)을 따른다. 다음 Windows ARM64 SSH → SPICE → 앱 연동은 [맥미니 기존 Codex 세션에 인계](M1_WINDOWS_CONNECTION_HANDOFF.ko.md)한다. Windows의 기존 화면은 Cocoa이며 접속 구성이 추가로 필요하다. M1 macOS ARM SSH는 사용자 확인 완료를 유지한다. 오디오·전체 게스트 도구·추가 공유 기능은 별도 범위다.
