# Fork 구현·검증 기록

2026-09-09 삭제 기능 후속: native macOS/Windows VM 삭제 및 ISO/IPSW 관리 화면을 개인 기능으로 추가했다.
이름 입력 확인, 실행/설치 중 보호, 참조·잠금·변경 파일 검사를 적용했다.
전체 Flutter 81 passed / 4 skipped, 네이티브 삭제 26 + 기존 38 checks, 실제 QEMU 잠금 수명 검사,
분석·release 빌드와 실제 파일 목록·확인 창 검증을 완료했다.
사용법은 [STORAGE_MANAGEMENT.ko.md](STORAGE_MANAGEMENT.ko.md), 세부 결과는 M1 검증 기록을 따른다.

2026-09-09 파일 선택 후속: ISO 선택의 entitlement 오류를 공통 `pr/macos-file-picker-entitlements` /
`c59d53b`, 개인 `1942c4e`에서 수정했다. Debug/Release 빌드·서명·분석과 실제 release 앱의
Windows ISO 선택 및 자원 설정 화면 도달을 확인했다. 상세 결과는 [M1_VALIDATION.ko.md](M1_VALIDATION.ko.md)를 따른다.

2026-09-09 Apple VM 후속: IPSW → 생성·설치 → Manager 실행을 개인 기능으로 연결했다.
M1에서 macOS 26.6.2 설치와 최초 언어 선택 화면 부팅, 새 프로세스 재실행, 창 다시 열기를 확인했다.
전체 테스트 73 passed / 4 skipped, 네이티브 저장 안전성 22 checks, 분석 0, release 빌드 PASS.
사용법은 [APPLE_SILICON_VM.ko.md](APPLE_SILICON_VM.ko.md), 실제 결과는 [M1_VALIDATION.ko.md](M1_VALIDATION.ko.md)를 따른다.
이 후속 기록은 아래의 Apple Virtualization backend 미구현 상태와 이전 게스트 검증 권장 순서를 갱신한다.
Windows ARM64 생성·설치/실행 경로도 연결했다. M1에서 Secure Boot 활성화와 설치 요구 사항 검사 통과,
64GB 디스크·UDF ISO 인식을 확인했다. 전체 테스트 76 passed / 4 skipped, 네이티브 22 + 16 checks,
펌웨어 준비 3 tests, 분석 0, 최종 release 47.8MB를 확인했다.
호스트 여유 공간이 32GiB 미만이므로 Windows 전체 설치·바탕화면은 아직 진행하지 않았다.
WinPE 네트워크 어댑터가 표시되지 않아 게스트 드라이버/네트워크 검증도 남아 있다.
사용법은 [WINDOWS_ARM_VM.ko.md](WINDOWS_ARM_VM.ko.md), 실제 성공·실패 범위는 M1 검증 기록을 따른다.

2026-09-08. 이전 세 설계 문서는 최초 계획의 보존본이다. 현재 실행 상태는 이 문서를 따른다.

2026-09-09 M1 후속: 시스템 PATH가 Homebrew보다 앞설 때 발생한 Bash 버전 오류를 공통 후보
`pr/macos-homebrew-path` / `dc51dd0`에서 수정하고 `personal/apple-silicon` / `fb94a51`에 반영했다.
M1에서 양쪽 분석·전체 테스트·release 빌드와 실제 backend/catalog 검사를 통과했다.
기존 개인 lockfile 변경 보존, 실행 환경과 명령, 미검증 범위는 [M1 검증 기록](M1_VALIDATION.ko.md)을 따른다.
아래 2026-09-08 기록의 M1 미실행 상태는 이 결과로 갱신한다. 이후 ARM 게스트 결과는 문서 상단의 후속 기록을 따른다.

같은 날 개인 브랜치에 OS 아키텍처 구분과 [ARM 설치 이미지 다운로드](ARM_DOWNLOADS.ko.md)를 추가했다.
Windows는 Microsoft 공식 ARM64 링크 입력, macOS는 Apple의 호환 IPSW 조회·저장 경로다.
분석·66개 테스트·macOS release 빌드를 통과했고 Apple 이미지 메타데이터·범위 응답을 실검증했다.
ARM 이미지 전체 실다운로드와 VM 생성·설치·부팅은 아직 검증/구현 완료로 표시하지 않는다.

후속 다운로드 완료 확인: 사용자가 저장한 macOS 26.6.2 / 25G83 IPSW의 전체 크기와 SHA256이
Apple 서버의 값과 일치했다. macOS ARM 이미지 파일 무결성 검증은 PASS로 갱신한다.
Windows ARM ISO 전체 다운로드 및 ARM VM 생성·설치·부팅은 남아 있다. 경로·체크섬은 M1 검증 기록에 추가했다.

## 운영 상태

- `origin`: `https://github.com/kimdongup/quickgui.git`
- `upstream`: `https://github.com/quickemu-project/quickgui.git`
- upstream 기준: `74949e086154f3f2d555f9268778545c78ff2b51`
- 기존 텍스트 수정 보존: `archive/local-start` / `e6d30ff`. 기존 `.DS_Store`와 한국어 설계 원본은 로컬에 보존했다.
- 공통 PR 후보: `integration/stabilization` / `ae57d7d`. `pr/functional-regressions`, `pr/spice-unix`도 같은 커밋이다. 공유 저장소 삭제 보호 후보 `pr/shared-vm-storage`는 `ab1ff85`로 보존한다. 개인 기능과 개인 운영 문서는 포함하지 않는다.
- 개인 VM 기능: `personal/vm-workflow` / `eaba8b8`.
- 개인 고급 설정: `personal/backend-settings` / `d6a3369`.
- 개인 패키지 후보: `personal/release-ops` / `2f0d9fd` (이후 문서만 추가될 수 있다).
- 현재 개인 통합 후보의 앱 코드: `personal/preview` / `09fce12` (이후 검증 도구·문서 커밋은 별도). Windows 설치 경험은 `personal/windows-installation` / `3f85b3d`에서 통합했으며, 공통 삭제 보호와 SPICE Unix 소켓 재접속을 추가했다. 상세 내역과 순차 검증은 [GUEST_VALIDATION.ko.md](GUEST_VALIDATION.ko.md)를 따른다.
- Intel macOS 게스트는 두 차례 Recovery 복귀를 조사한 뒤 외부 복구 매체를 제외한 실행에서 후속 설치를 마쳤다. QuickguiMac 자동 부팅과 최초 설정의 국가·지역 선택 화면까지 확인했다. 사용자 계정 설정·바탕화면·설정 완료 후 재부팅·SSH·SPICE는 아직 남아 있다.
- Apple Silicon 검증 장비는 사용자 보유 M1 맥미니로 정했다. 소스 clone, M1 전용 작업 브랜치와 개발 환경 준비는 [M1_HANDOFF.ko.md](M1_HANDOFF.ko.md)를 따른다. Windows ARM64도 M1을 주 검증 호스트로 권장하며 Intel TCG는 추가 실험으로 남긴다. macOS x64 → Windows ARM64 → macOS ARM 순서는 유지하고 M1 실행 결과는 아직 없다.
- `main`은 아직 upstream 기준이다. 아래 실사용 수용 검증을 마친 뒤 개인 안정판으로 승격한다. 공개 태그·릴리스와 upstream PR은 아직 제출하지 않았다.

## 구현한 범위

| 작업 | 결과 |
| --- | --- |
| CORE-01/02 | AssetManifest API, 도구/메타데이터 분리, 실행 가능한 PATH 우선 탐색, 저장 경로 복구, 명시적 작업 디렉터리, 설정 저장 오류 표시 |
| CORE-03 | 4/5/7열 CSV와 quoted field 처리, 목록 오류·재시도·빈 결과 구분, 단일 스크롤 목록과 검색 |
| CORE-04 | 양쪽 출력 소비, 종료 코드 기반 완료, 제한된 로그, 시작 전 취소 및 자식 프로세스 종료, 앱 종료 확인, 알림 실패 격리 |
| CORE-05/06 | config/disk 경로에 맞춘 상태 조회, unknown 상태, VM별 잠금, 실행 직전 재확인, 실제 상태 확인, SSH timeout과 인자 경계, SPICE 클라이언트 오류 처리 |
| CORE-07/08 | 기존 주요 UI 구성 유지, 설정/locale fallback, 반복 화면 생명주기, Flutter 3.47.2/Dart 3.13.2, Linux/macOS/Nix 빌드 CI |
| EXT-01 | Quickget의 성공 출력이 명시한 config를 검증하여 Manager에서 강조. 실패·취소·모호한 출력 제외, 기존 VM과 신규 VM 구분 |
| EXT-02 | 중지된 VM 편집, 로딩 중 저장 차단, 외부 변경 감지, 같은 파일시스템의 임시 파일 교체, 주석·개행·권한 보존, symlink 편집 거부, VM 작업과 잠금 공유 |
| EXT-03 | 선택형 backend 경로, 도움말에서 확인한 display/sound/architecture 옵션, 기본값 유지, 저장·재시작·초기화. 기존 VM architecture는 config를 유지 |
| OPS-01 | fork 전용 패키지/체크섬/SHA manifest, 정확한 태그 검증, 기본 build-only, upstream 배포·자동 flake PR 작업 분리 |
| GUEST-01 | 선택형 Intel Mac Windows x64 호환 프로필, 설치 중 표시 인식·Run 차단·사용자 완료 확인 후 표시 보관, 일반 실행 시 설치 전용 환경 변수 제거. 기존 Windows VM은 읽기만 수행 |
| CORE-05 후속 | 삭제 전 실제 경로를 비교하여 다른 설정이 참조하는 디스크 링크, 디렉터리 별칭과 중첩 VM 디렉터리를 보호. 독립 VM의 삭제는 유지 |
| CORE-06 후속 | Quickemu의 기본 Unix SPICE 소켓을 기존 연결 버튼에서 지원. 경로 문자 보존, 실행 직전 PID/config/소켓 재확인, 기존 TCP 지원 유지 |

## 실행한 검증

| 대상 | 명령/증거 | 결과 |
| --- | --- | --- |
| 공통 `ae57d7d` | 분석/전체 테스트, [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34262907080), [실제 backend CI](https://github.com/kimdongup/quickgui/actions/runs/34262907061) | PASS: 분석 0, 30 tests / 외부 opt-in 2 skipped, Linux/macOS/Nix 및 실제 Linux backend |
| 개인 `09fce12` | 분석/전체 테스트, [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34263261231), [실제 backend CI](https://github.com/kimdongup/quickgui/actions/runs/34263261290) | PASS: 분석 0, 43 tests / 외부 opt-in 3 skipped, Linux/macOS/Nix 및 실제 Linux backend |
| 개인 `09fce12` | macOS release 빌드와 `lipo -archs` | PASS: 46.8 MB, runner/App.framework의 x86_64/arm64 slice |
| Intel Mac 별도 SPICE backend | [구성·실접속 기록](MACOS_SPICE_BACKEND.ko.md), [재현 도구](../../tool/spice/README.md) | PASS: 서버 25 tests, QEMU 11.1.1/SPICE 0.16.0, 화면 수신·K 입력·재접속·실제 spicy 4개 채널. 기본 GStreamer 환경에서도 확인. 설치된 게스트 검증과 구분 |
| 실행 중 Unix SPICE VM 읽기 | 실제 `VmRepository.inspect/list`, `spiceArguments` | PASS: 1개 별도 검사. 실행 상태/소켓 경로/재접속 인자 인식, config bytes 보존 |
| 공통 `ab1ff85` | `flutter analyze --no-pub`, `flutter test --no-pub` | PASS: 분석 0, 26 tests / 외부 실행 opt-in 2 skipped. 새 공유 경로 검사 3개 포함 |
| 개인 `bbd021f` | `flutter analyze --no-pub`, `flutter test --no-pub` | PASS: 분석 0, 39 tests / 외부 실행 opt-in 3 skipped. Windows 설치 처리와 공통 삭제 보호 통합 |
| 개인 `bbd021f` | `flutter build macos --release --no-pub`, `lipo -archs` | PASS: 46.8 MB 앱. runner와 App.framework의 x86_64/arm64 slice 확인 |
| 공통 `ab1ff85` | [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34259444705), [실제 backend](https://github.com/kimdongup/quickgui/actions/runs/34259444702) | PASS: Linux/macOS/Nix, 분석/26 tests 및 실제 Linux backend |
| 개인 `bbd021f` | [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34259523524), [실제 backend](https://github.com/kimdongup/quickgui/actions/runs/34259523553) | PASS: Linux/macOS/Nix, 분석/39 tests 및 실제 Linux backend |
| PR 공통 `5d43928` | [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34240467191), [Linux 실제 backend](https://github.com/kimdongup/quickgui/actions/runs/34240467194) | PASS: 분석/23 tests/Linux/macOS/Nix, 임시 VM 시작·중지·디스크 삭제·VM 삭제, Quickget 실제 catalog |
| 개인 VM 기능 `eaba8b8` | [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34240406729), [Linux 실제 backend](https://github.com/kimdongup/quickgui/actions/runs/34240406776) | PASS: 분석/28 tests/Linux/macOS/Nix 및 임시 VM |
| 개인 고급 설정 `d6a3369` | `flutter analyze`, `flutter test` | PASS: info 포함 0, 31 tests. 외부 다운로드/VM/catalog opt-in 테스트는 별도 실행 |
| 개인 고급 설정 `d6a3369` | [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34241115918), [Linux 실제 backend](https://github.com/kimdongup/quickgui/actions/runs/34241115908) | PASS: Linux/macOS/Nix 및 임시 VM |
| 개인 패키지 코드 `2f0d9fd` | [빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34241482643), [실제 backend](https://github.com/kimdongup/quickgui/actions/runs/34241482412), [패키징 CI](https://github.com/kimdongup/quickgui/actions/runs/34241482709) | PASS: 모든 job 성공. Linux x64 9.9 MB, macOS ARM64 18 MB, 두 SHA256 검증과 앱 번들 내부 실행 파일 확인 |
| 편집 화면 추가 회귀 | `flutter test test/config_editor_widget_test.dart` | PASS: 초기 Save 비활성, 저장 중 Save·닫기 차단, 저장 완료 후 원래 화면 복귀. 기존 31개에 1개 추가 |
| macOS Intel, 공통 `d27e7d3` | `QUICKGUI_REAL_VM_TESTS=1 flutter test test/real_vm_smoke_test.dart` | PASS: 실제 Cocoa VM 시작·중지·삭제. 빈 디스크 BIOS 부팅이며 게스트 설치 완료 검증은 아님 |
| macOS Intel, 개인 `d6a3369` | `QUICKGUI_REAL_DOWNLOAD_TESTS=1 flutter test test/real_download_test.dart` | PASS: Tiny Core 15 CorePure64 이미지 실제 다운로드, 완료 판정, 신규 config 식별, 테스트 데이터 정리 |
| macOS Intel, 공통 `d27e7d3` | `flutter build macos --release` | PASS: 46.7 MB 앱 생성 |
| 시각 검토, 공통 `5d43928` | `QUICKGUI_SCREENSHOT_DIR=... QUICKGUI_TEST_FONT_DIR=... flutter test test/ui_regression_test.dart` | PASS: 692×580, Roboto/MaterialIcons, 홈·다운로더·Manager·설정 렌더링. 저장소의 기존 정상 홈 화면과 구성 비교 |
| 반복 조작 | `ui_regression_test.dart` | PASS: 30회 Manager/홈 전환, 타이머/리스너 정리, 미처리 위젯 예외 없음 |
| 개인 릴리스 스크립트 | `python3 -m unittest discover -s tool -p 'test_*.py'` | PASS: 3 tests, 태그/버전 매핑 및 잘못된 태그 거부 |

macOS 환경: macOS 15.7.9, x86_64, Flutter 3.47.2, Dart 3.13.2, QEMU 11.1.1. Homebrew Quickemu/Quickget 4.9.9 파일의 Git blob을 공개 태그 `a28a9ebd56c086cc1463733a1674bb88613b92e3`와 비교해 일치를 확인했다. 부모 디렉터리의 수정된 Quickemu를 기준으로 통과를 주장하지 않는다.

선택 브랜치 `bb50a80`의 [CI](https://github.com/kimdongup/quickgui/actions/runs/34238936068)는 분석/테스트/Linux/macOS/Nix **빌드 단계는 모두 성공**했으나 Magic Nix Cache 후처리 업로드가 장시간 끝나지 않아 해당 run을 취소했다. 전체 run을 success로 표기하지 않는다. 후속 통합 SHA의 동일 빌드·캐시 workflow는 정상 완료됐다.

## 아직 통과로 표시하지 않는 항목

- Q21의 실제 GUI 전체 흐름: 게스트 OS 설치 완료, 게스트 SSH 로그인, Linux SPICE 연결, 앱 재실행 후 재접속. 현재 실제 이미지 다운로드와 폐기 가능한 VM 수명 검증은 각각 통과했지만 이 전체 흐름을 대체하지 않는다.
- Finder에서 시작한 배포 앱의 수동 조작, X11/Wayland 각각의 실사용, dark/light 전체 화면 비교, 실제 휠·트랙패드·키보드 조작. 위젯 렌더링 테스트가 모든 네이티브 동작을 증명하지 않는다.
- Linux ARM64 게스트 실사용. M1 macOS ARM64는 설치·최초 설정 화면까지 확인했으며 바탕화면·SSH·네트워크 실사용은 남아 있다. Windows ARM64는 설치 환경 부팅까지 확인했으며 전체 설치는 남아 있다.
- 최소 Quickemu 버전의 전체 실행 matrix. 중지는 4.9.6 이상을 요구하지만 주 검증 backend는 4.9.9이다.
- 한국어는 기존 지원 locale 목록에 없다. 지원하지 않는 locale의 영어 fallback은 확인했으며 한국어 번역 완료를 주장하지 않는다.
- 서명/notarization, 설치 프로그램, AppImage/deb/rpm, 동시에 설치하는 별도 앱 ID/설정 migration. 이번 개인 패키지는 압축된 앱 번들이며 현재 앱 ID와 기존 설정을 유지한다.
- 외부 프로그램이 마지막 검증 직후 config/PID/파일을 변경하는 모든 경쟁을 원자적으로 방지하지 않는다. GUI 내부 작업은 직렬화하며 읽을 수 없는 상태는 거부한다.
- 공유 저장소 삭제 검사는 현재 작업 폴더에서 읽을 수 있는 리터럴 `disk_img` 설정을 대상으로 한다. 다른 작업 폴더의 설정이나 임의 Bash 로직이 참조하는 모든 디스크를 자동 발견하는 것은 아니다.

따라서 S3 전체 및 안정 릴리스 수용 검증은 **부분 완료**다. 실제 실행하지 않은 항목을 pass로 바꾸거나 `main`을 안정판으로 승격하지 않는다. 개인 기능은 별도 후보 브랜치에 구현·푸시하여 공통 PR 후보와 격리했다.

순서 조정: PR용 구현과 자동·실제 backend 검토 후, 남은 네이티브 실사용 항목을 명시한 상태에서 개인 기능을 후보 브랜치에 선행 구현했다. 이는 S3 전체 통과나 S4 안정판 승격을 의미하지 않는다.

## 재현 명령과 다음 승격

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
QUICKGUI_REAL_VM_TESTS=1 flutter test test/real_vm_smoke_test.dart
QUICKGUI_REAL_CATALOG_TESTS=1 flutter test test/real_catalog_test.dart
# 개인 브랜치만: 외부 이미지 다운로드 약 20 MB, 임시 경로만 사용
QUICKGUI_REAL_DOWNLOAD_TESTS=1 flutter test test/real_download_test.dart
```

위 실사용 항목의 host/backend/후보 SHA와 결과를 추가한 뒤, 검증된 개인 후보를 `main`에 merge하고 `git push origin main`으로 반영한다. upstream 대응표와 제출 순서는 [UPSTREAM_PRS.md](UPSTREAM_PRS.md), 개인 패키지 생성은 [RELEASES.ko.md](RELEASES.ko.md)를 따른다.
