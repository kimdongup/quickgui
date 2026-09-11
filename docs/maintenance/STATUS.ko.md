# Fork 구현·검증 기록

2026-09-11 Windows x64 후속: 기존 다운로드 버튼이 외부 Quickget의 Windows 자동 미디어 생성 경로를 유지하던 문제를 수정했다. Windows 11 x64의 공식 ISO 링크·로컬 파일 선택, HTML/불완전 ISO 거부, 선택형 VirtIO와 Intel 프로필, 기존 VM을 덮어쓰지 않는 수동 설치 준비를 추가했다. 상세 근거와 사용법은 [Windows x64 미디어 수정](WINDOWS_X64_MEDIA_FIX.ko.md)을 따른다.

2026-09-11 UTC 최종 진행: 개인 통합 `32fcd67`의 Build·Public Quickemu smoke CI 모두 성공. 검증된 빌드를 `/Applications/quickgui.app`에 설치했고 기존 앱은 `/Users/mac/Applications/Quickgui-backup-32fcd67/quickgui.app`에 보존했다. 사용자 요청으로 추가 기능 검증을 종료하고 공통 [PR #325](https://github.com/quickemu-project/quickgui/pull/325)를 Ready for review로 전환했다. 실행 중인 VM과 미커밋 파일은 보존했다.

2026-09-11 UTC 통합 검토: M1 연결 작업 `f81ea92`(앱 코드 `1877d60`)를 최신 `personal/preview` 기준 `13860d6`에 충돌 없이 통합했다. Intel 회귀와 보존 범위는 [통합 검토 결과](M1_CONNECTION_INTEGRATION.ko.md)를 따른다. 아래 날짜별 기록의 미완료 표시는 당시 상태다.

2026-09-10 PR 제출: 첫 공통 수정 [Draft PR #325](https://github.com/quickemu-project/quickgui/pull/325)를 `pr/upstream-desktop-compatibility` / `448e7e4`에서 제출했다. upstream 기준 단일 커밋이며 Flutter 빌드·자산 목록 API·macOS 파일 선택 권한을 포함한다. macOS 최소 버전 12.0 상향을 명시했다. 개인 ARM·VM 서비스와 운영 문서는 포함하지 않았다. 로컬 분석·2개 공통 테스트·Release 빌드·서명 검사는 통과했고, 제출 커밋의 CI 및 다음 순서는 [첫 PR 기록](UPSTREAM_DESKTOP_PR.ko.md)을 따른다.

2026-09-10 HST / 2026-09-11 UTC 연결 검증 후속: 설치된 Intel macOS의 실제 SSH 인증·명령·재접속, 정상 종료 후 같은 디스크의 SPICE 부팅·바탕화면·키 입력·포인터 클릭을 확인했다. 앱 서비스의 실제 VM 조회·SSH 감지·SPICE 인자 검사 1개도 통과했다. 실제 spicy 창의 결과와 일반 Run 연동의 제한은 [Intel 연결 기록](MACOS_SPICE_BACKEND.ko.md)을 따른다. Windows ARM64는 접속 구성·실사용 검증이 남아 있으며 [맥미니의 기존 Codex 세션으로 인계](M1_WINDOWS_CONNECTION_HANDOFF.ko.md)한다. M1 macOS ARM SSH의 사용자 확인 완료는 유지한다.

2026-09-10 통합 후속: 사용자가 M1 macOS ARM의 **바탕화면·재부팅·SSH 검증 완료**를 확인했다. Windows ARM64의 설치 후 실사용과 함께 [M1 검증 기록](M1_VALIDATION.ko.md)에 반영했다. `personal/preview`의 `64cfd59`와 `personal/apple-silicon`의 `f3f5c2b`를 별도 `personal/platform-integration` 후보에서 merge했다. 추가로 발견한 선언형 ISO 경로의 삭제 보호 오류를 수정했다. Intel 분석·82개 Flutter 테스트·12개 실제 도구/catalog 검사·57개 네이티브 검사·release 빌드가 통과했다. 상세 결과와 남은 범위는 [통합 검토](PLATFORM_INTEGRATION.ko.md)를 따른다.

2026-09-10 Windows ARM64 실사용 후속: 사용자께서 초기 설정·바탕화면·입력·HTTPS 및
정상 종료와 설치 완료 후 부팅(요청 1~3단계)을 직접 검토해 정상이라고 확인했다.
이번 M1 검사에서는 기존 VM 정상 종료 → 설치 완료 표시 저장 → Quickgui 완전 종료·재실행 →
동일 VM Run을 수행했다. 설치 ISO 없이 실행되고 외부 TCP 연결이 다시 성립했다.
VM·원본 ISO·기존 미커밋 lockfile을 보존했으며 새 코드 오류는 재현되지 않았다.
Intel macOS x64 설치·구동의 사용자 확인(`personal/preview` / `64cfd59`)도 반영했다.
상세 근거와 사용자 확인/직접 검사 구분은 [M1 검증 기록](M1_VALIDATION.ko.md)의 마지막 절을 따른다.

2026-09-10 검토 정리: 완료 범위, 커밋된 lockfile로 수행한 재현 검사, 공통/개인 브랜치와
원격 반영 결과는 [M1 검토 완료 결과](M1_REVIEW_RESULT.ko.md)에 정리했다.
아래 날짜별 기록은 당시 상태를 보존하며, 현재 완료·미확인 범위는 위의 최신 후속 기록을 우선한다.

2026-09-10 Windows ARM64 네트워크 후속: 사용자가 OOBE의 네트워크 화면에서 어댑터가 없는 상태를 확인했다.
기존 usb-net을 VirtIO Ethernet으로 변경하고 공식 UTM 배포본의 Windows 11 ARM64 NetKVM만
담은 QGNET CD 준비·연결과 Network setup 안내를 추가했다. 위젯 9, 네이티브 22, 준비 도구 5,
실제 QEMU 시작·중지/미디어 잠금, 분석·release 빌드를 통과했다. 기존 사용자 VM을 수정 앱으로
다시 실행해 NIC와 CD 연결을 확인했다. 후속 NAT 조회에서 게스트 10.0.2.15의 외부 공인 주소로 향하는
TCP 연결 36개(443 포트 25개)가 ESTABLISHED 상태여서 실제 네트워크 통신도 확인했다.
OOBE 완료·바탕화면과 게스트 브라우저의 HTTPS 응답 내용은 아직 확인하지 않았다.
절차는 [WINDOWS_ARM_VM.ko.md](WINDOWS_ARM_VM.ko.md), 증거는 M1 검증 기록을 따른다.

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
- 개인 통합 후보: `personal/platform-integration`을 `personal/preview`에 반영했다. Intel 기준 `64cfd59`와 M1 기준 `personal/apple-silicon` / `f3f5c2b`의 이력을 함께 보존한다. M1 원래 브랜치의 마지막 앱 코드 변경은 `0517cf2`이고 그 브랜치의 후속은 검증 문서였다. 통합 후 `f48009b`에서 Swift 삭제 보호 코드와 CI를 수정했다. Intel 검사·승격 결과는 [통합 검토](PLATFORM_INTEGRATION.ko.md)를 따른다.
- Intel macOS x64 설치·구동은 사용자 확인 완료(`64cfd59`)이며, 후속에서 설치 게스트의 SSH 인증·재접속과 실제 SPICE 화면·키 입력·포인터 클릭을 확인했다. 별도 SPICE 검사 VM의 과거 성공과 구분한다. 세부 접속 결과와 앱 연동 범위는 [게스트 검증](GUEST_VALIDATION.ko.md)을 따른다.
- M1의 Windows ARM64는 초기 설정·바탕화면·입력·HTTPS·정상 종료/부팅의 사용자 확인과 앱 재실행·설치 ISO 없는 실행·외부 TCP 검사를 완료했다. macOS ARM의 바탕화면·재부팅·SSH도 2026-09-10 사용자 확인 완료다. Windows SSH/SPICE와 앱 연결은 [M1 후속 검증](M1_WINDOWS_CONNECTION_RESULTS.ko.md)에서 완료했으며, 오디오·전체 게스트 도구와 Intel ARM64 TCG 추가 실험은 별도로 관리한다.
- `main`은 아직 upstream 기준이다. 아래 실사용 수용 검증을 마친 뒤 개인 안정판으로 승격한다. 공개 태그·릴리스는 아직 없으며, 첫 upstream 제출은 공통 빌드 호환성 Draft PR #325다.

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
| 설치된 Intel macOS 15.7.9 | [실접속 기록](MACOS_SPICE_BACKEND.ko.md) | SSH 인증·재접속(Cocoa 및 SPICE 부팅), SPICE 1920×1080 화면·키 입력·포인터 클릭 PASS. 앱 소스의 live 조회·접속 준비 1 test PASS. 실제 spicy 창·GUI 전체 연동의 확인 범위는 상세 기록 참조 |
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
- Linux ARM64 게스트 실사용. M1 macOS ARM의 바탕화면·재부팅·SSH와 Windows ARM64의 설치 후 기본 실사용은 사용자 확인 및 M1 실행 기록으로 완료했다. Windows ARM64 일반 GTK 창의 전체 조작·오디오·전체 게스트 도구와 macOS ARM 오디오·클립보드·공유 폴더 등은 별도 검증 항목이다.
- 최소 Quickemu 버전의 전체 실행 matrix. 중지는 4.9.6 이상을 요구하지만 주 검증 backend는 4.9.9이다.
- 한국어는 기존 지원 locale 목록에 없다. 지원하지 않는 locale의 영어 fallback은 확인했으며 한국어 번역 완료를 주장하지 않는다.
- 배포용 Developer ID 서명/notarization, 설치 프로그램, AppImage/deb/rpm, 동시에 설치하는 별도 앱 ID/설정 migration. 이번 개인 패키지는 압축된 앱 번들이며 현재 앱 ID와 기존 설정을 유지한다. 로컬 ad-hoc 서명 검사는 배포 인증과 구분한다.
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
