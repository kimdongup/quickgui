# M1 Windows 연결의 Intel 통합 검토

2026-09-11 UTC. `personal/windows-arm-connections`의 `f81ea92`(앱 코드
`1877d60`)를 최신 `personal/preview`의 `13860d6`에서 만든 별도 worktree
`personal/m1-connections-integration`에 fast-forward했다. 파일 충돌이나
추가 앱 코드 수정 없이 아래 Intel 회귀를 통과한 후보를 `personal/preview`에 반영한다.

## 검토 결과

- Windows 연결 설정·버튼은 Windows native VM에만 표시된다. 공통 모델의 새 필드는
  기본값을 제공하므로 기존 macOS 레코드와 호환된다.
- Windows 실행 구현은 ARM64 조건부 컴파일 안에 있다. Intel 채널은 미지원 상태를
  반환하며 기존 Quickemu 실행·SSH/SPICE 서비스와 macOS native 실행 코드는 유지한다.
- 저장된 SSH 포트와 실행 중인 세션의 접속 주소를 구분한다. 설정 변경은 VM 소유권과
  중지 상태를 확인하며, SSH 전달은 loopback, SPICE는 세션별 Unix 소켓을 사용한다.
- ARM SPICE backend가 없으면 Cocoa 경로를 유지한다. 별도 ARM 바이너리는 Git에
  포함되지 않으며 Intel backend를 대신 사용하지 않는다. 설치 방법과 의존성은
  [M1 backend 문서](M1_WINDOWS_SPICE_BACKEND.ko.md)를 따른다.
- 통합을 막는 오류는 발견하지 못했다. 현재 상태 표와 초기 인계·대기 기록의 시점을
  명확히 하도록 문서를 정리했다. 공통 upstream PR #325 브랜치는 변경하지 않는다.

## 이번 Intel 실행 결과

실행 위치는 `/private/tmp/quickgui-m1-connections-integration`, 호스트는 Intel
macOS 15.7.9다. 실제 VM 검사는 새 임시 디스크만 사용했다.

| 검사 | 결과 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | PASS, 커밋된 의존성 사용 |
| Dart format / `flutter analyze --no-pub` | PASS, 포맷 변경 0 / 분석 문제 0 |
| 전체 `flutter test --no-pub` | 87 PASS, 선택적 실제 환경 검사 4 skipped |
| 실제 toolchain·quickget catalog·Quickemu 검사 | 환경 플래그를 켜고 13 PASS. 임시 VM 시작·종료·삭제 포함 |
| Swift MacVMStore 검사 | 22 PASS, 기존 레코드·자원/네트워크 보존·경로 보호 포함 |
| Swift NativeStorageStore 검사 | 57 PASS, 공유 디스크·ISO 삭제 보호 포함 |
| Python 도구 unittest | 14개 중 11 PASS, 선택적 환경 검사 3 skipped |
| Intel SPICE C 검증기 | `-Wall -Werror` 컴파일 PASS |
| 실제 Intel SPICE smoke | 임시 VM의 720×400 화면·K 입력·재접속 2회 및 실제 spicy 4개 채널 PASS |
| macOS release 빌드·서명·아키텍처 | PASS, 48.3 MB. `codesign --verify --deep --strict` 성공, 실행 파일과 App.framework 모두 x86_64·arm64 |

릴리스 빌드에는 기존 `window_size`의 Swift Package Manager 미지원 안내와 출력 파일을 선언하지 않은 Run Script 경고가 있었다. 빌드는 성공했으며 `pubspec.lock`과 `macos/Podfile.lock`은 변경되지 않았다.

실제 Intel 도구 검사는 다음 명령으로 실행했다.

```sh
QUICKGUI_REAL_CATALOG_TESTS=1 QUICKGUI_REAL_VM_TESTS=1 \
  flutter test --no-pub --reporter expanded \
  test/toolchain_test.dart test/real_catalog_test.dart test/real_vm_smoke_test.dart

cc -Wall -Werror tool/spice/capture.c \
  -o /private/tmp/quickgui-m1-integration-capture \
  $(pkg-config --cflags --libs spice-client-glib-2.0 gdk-pixbuf-2.0)
python3 tool/spice/smoke.py \
  --qemu /Users/mac/quickemu/validation/spice-backend/bin/qemu-system-x86_64 \
  --capture /private/tmp/quickgui-m1-integration-capture \
  --viewer /usr/local/bin/spicy --firmware /usr/local/share/qemu
```

전체 로컬 로그는 `/private/tmp/quickgui-m1-integration-*.log`에 있다.
임시 검사 VM은 검사 도구가 정리한다. 이번 SPICE smoke는 설치된 macOS 게스트의
SSH·바탕화면을 다시 검사한 것이 아니며, 과거의 [Intel 설치 게스트 증거](MACOS_SPICE_BACKEND.ko.md)와 구분한다.

## M1 증거와 남은 범위

[M1 실행 결과](M1_WINDOWS_CONNECTION_RESULTS.ko.md),
[backend 기록](M1_WINDOWS_SPICE_BACKEND.ko.md),
[JSON 증거](evidence/m1-windows-connections.json)를 먼저 검토했다.
실제 SSH 인증·재접속, SPICE 화면·포인터·키보드·재접속, Flutter 앱 설정 저장·재실행·
SSH/SPICE 연결은 M1에서 수행한 결과다. Swift ARM 전용 검사 35개도 M1 결과이며
Intel에서 다시 실행한 것으로 계산하지 않는다. 앱 코드 `1877d60`의
[Build CI](https://github.com/kimdongup/quickgui/actions/runs/34579501893)와
[Public Quickemu smoke CI](https://github.com/kimdongup/quickgui/actions/runs/34579501905)는
GitHub 조회에서도 같은 SHA의 성공 상태를 확인했다.

일반 GTK viewer의 접근성 자동 제어 제한은 남아 있다. 프로토콜 입력 성공을
일반 GTK 창의 모든 조작·오디오·클립보드·USB·전체 게스트 도구의 성공으로 확대하지
않는다. Intel 설치 게스트의 일반 Run SPICE 자동 설정·GUI 전체 흐름 제한도 기존
기록대로 유지한다. macOS ARM 바탕화면·재부팅·SSH는 기존 사용자 완료 확인을 유지한다.

## 기존 작업 보존과 반영

원래 작업 폴더의 변경 파일 5개(`macos/.DS_Store`, `.vscode/acp-bridge.json`,
`docs/FORK_AND_UPSTREAM_STRATEGY.ko.md`, `docs/FUNCTIONAL_QA_PLAN.ko.md`,
`docs/REVIEW_AND_PR_PLAN.ko.md`)는 별도로 복사하고 SHA-256 일치를 확인했다.
백업 위치는 로컬 `/private/tmp/quickgui-m1-integration-preserve-path`에 기록했다.
이 파일들은 통합 커밋에 포함하지 않는다. 기존 설치 VM·ISO를 시작·중지·편집·삭제하지
않았으며, M1의 미커밋 lockfile이나 VM에도 접근하지 않았다.

검증된 후보는 원래 작업 폴더에서 fast-forward하고 `origin/personal/preview`로
push한다. M1 소스 브랜치와 공통 PR 브랜치는 그대로 유지한다. 최신 통합 커밋은
이 문서의 Git 이력으로 확인한다.

## 최종 반영 후속

`32fcd67`의 [Build](https://github.com/kimdongup/quickgui/actions/runs/34581922224)와
[Public Quickemu smoke](https://github.com/kimdongup/quickgui/actions/runs/34581922279)는
모두 success로 완료됐다. 사용자 요청으로 추가 기능 검증은 종료했다.
검증된 통합 빌드를 `/Applications/quickgui.app`에 설치했으며, 기존 앱은
`/Users/mac/Applications/Quickgui-backup-32fcd67/quickgui.app`에 보존했다.
실행 중인 VM은 종료하거나 재시작하지 않았다. 공통 PR #325는 Ready for review로
전환했으며 개인 기능을 PR에 추가하지 않았다. 이 후속 커밋은 운영 문서만 갱신한다.
