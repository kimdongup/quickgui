# Quickgui 코드 리뷰와 PR 준비 설계

검토일: 2026-09-08. 기준: `74949e086154f3f2d555f9268778545c78ff2b51` + 현재 미커밋 변경.

후속 요청 반영: 브랜치·제출·개인 릴리스 운영은 [분리 운영 설계](FORK_AND_UPSTREAM_STRATEGY.ko.md), PR용 구현 완료 후 전수 검증은 [QA 계획](FUNCTIONAL_QA_PLAN.ko.md)을 따른다. 아래 발견 사항은 최초 검토 시점의 코드에 대한 기록이며 수정 완료를 뜻하지 않는다.

## 검토 범위와 현재 상태

- 로컬 HEAD, upstream `main`, `kimdongup/quickgui:main`이 동일하다. GitHub compare 결과 ahead/behind 모두 0. 사용자 수정은 로컬 22개 추적 파일에 있으며, 별도로 미추적 `.DS_Store` 2개가 있다.
- remote `origin`은 **quickemu-project/quickgui**다. fork를 가리킨다고 생각하고 기본 push를 실행하면 안 된다.
- GitHub REST API로 PR 전체 192개를 조회했다. 열린 PR 11개, `merged_at == null` 69개(열린 PR 포함). 웹 목록의 캐시에는 15개가 표시되므로 API 상태를 기준으로 판단했다.
- 변경된 Dart 코드와 연결되는 다운로드·선택·설정·VM 관리 경로, 의존성, macOS 프로젝트 및 CI를 검토했다. 열린 주요 기능 PR은 diff를 읽었고, 과거 닫힌 PR은 제목·범위·관련 의견을 선별 검토했다. 모든 과거 PR의 코드를 전수 검증한 것은 아니다.
- 실제 VM 실행·중지·삭제, ISO 다운로드, Linux/Nix 빌드 및 macOS 새 release 빌드는 수행하지 않았다. 아래에서 정적 판독과 재현 결과를 구분한다.

## 주요 발견

P1은 PR 전 우선 수정, P2는 안정화 과정에서 수정할 항목이다. “기존”은 현재 수정으로 새로 생긴 문제가 아니라 upstream에도 남아 있다는 뜻이다.

### F1 — P1: CI SDK와 의존성 요구 버전 불일치

위치: `pubspec.yaml:7`, `:17`, `:21`; `.github/workflows/build-quickgui.yml:36`, `publish-quickgui.yml:55`.

CI가 `flutter-version-file: pubspec.yaml`을 사용하지만 Flutter 값은 3.22.0이다. 현재 추가한 file_picker 12.2.0은 Flutter >=3.38.0 / Dart >=3.10.0, package_info_plus 10.2.1은 Flutter >=3.38.1 / Dart >=3.10.0을 요구한다. 로컬 Flutter 3.47.2 / Dart 3.13.2에서 분석되어도 CI의 의존성 해결은 실패하는 조합이다. 로컬 설치 패키지의 pubspec으로 확인했다. upstream에도 SDK 기준이 오래된 문제가 있으므로 새 의존성만 유일한 원인으로 보아서는 안 된다.

설계: 지원 최저 Flutter/Dart와 CI 실행 버전을 명시적으로 정한다. 현대화 PR에서 pubspec, CI, Nix Flutter, macOS 최소 버전을 함께 검증한다. 기능 수정 PR이 반드시 대규모 의존성 업데이트에 의존해야 하는지는 별도로 판단한다. 임의로 최신 버전만 지정해서 해결됐다고 간주하지 않는다.

### F2 — P1: 최신 Flutter에서 OS 아이콘 로딩 실패

위치: `lib/main.dart:70`, `:98`. 기존 코드와 새 SDK 조합의 호환성 문제.

`AssetManifest.json`을 직접 읽지만 설치된 SDK는 `AssetManifest.bin`을 생성한다. `getIcons()`도 await하지 않아 실패가 처리되지 않는다. 아이콘이 기본 아이콘으로 남고 비동기 예외가 발생한다. 앱 전체가 항상 종료된다는 뜻은 아니다.

설계: `AssetManifest.loadFromAssetBundle(rootBundle).listAssets()` 사용, 초기화 완료를 명시적으로 기다리고 실패 시 기본 아이콘과 진단 메시지 제공. #303의 예외 처리만 가져오면 예외는 숨겨도 아이콘은 복구하지 못한다. [Flutter 공식 마이그레이션](https://docs.flutter.dev/release/breaking-changes/asset-manifest-dot-json).

### F3 — P1: 다운로드 실패를 완료로 표시하고 출력 파이프가 막힐 수 있음

위치: `lib/src/pages/downloader.dart:63–101`, `:148–151`. 기존 문제.

종료 코드가 음수인지로만 취소를 판단하여 일반적인 실패 코드 1, 2 등을 “Download complete”로 알린다. stdout은 소비하지 않고 zsync 분기에서는 stderr도 소비하지 않는다. 출력이 파이프 용량을 초과하면 자식 프로세스가 진행하지 못할 수 있다. `Process.start` 실패도 catch하지 않아 화면이 대기 상태에 남는다. 실제 다운로드를 통한 재현은 미수행, 코드 경로로 확인했다.

설계: `starting → running → succeeded | failed | cancelled` 상태를 별도로 둔다. 성공은 exitCode 0으로 한정한다. stdout/stderr를 항상 동시에 소비하고 종료 및 스트림 완료를 모두 기다린 뒤 UI 스트림을 닫는다. stderr 일부를 상한이 있는 버퍼에 보관해 오류로 표시한다. 취소 의도를 기록하고 quickget 및 다운로드 자식 프로세스 종료 방식은 Linux/macOS에서 따로 검증한다. `_process.kill()`이 자식 전체를 종료한다고 가정하지 않는다.

### F4 — P1: 시작 중인 VM의 삭제 버튼이 활성 상태

위치: `lib/src/pages/manager.dart:190`, `:445`의 삭제 버튼. 현재 추가한 starting 상태 처리의 누락.

시작 버튼은 `active || starting`으로 막지만 삭제 버튼은 `active`만 본다. PID가 나타나기 전에 삭제를 누를 수 있고, 확인 대화상자가 열린 동안 VM이 실행 상태로 전환돼도 재검증하지 않는다. 빠른 조작으로 시작과 디스크 삭제가 겹칠 수 있다. 실제 삭제 재현은 하지 않았다.

설계: VM별 작업 잠금으로 시작/중지/삭제/편집을 직렬화한다. 버튼 비활성화와 별개로 **확인 후 실행 직전** 상태를 재검증한다. 잠금 키는 이름이 아닌 절대 config 경로다.

### F5 — P1: 공백 있는 VM 이름은 중지·삭제에서 인자가 깨짐

위치: `lib/src/pages/manager.dart:425–432`, `:484`, `:548–599`. 기존 문제이며 시작 경로만 부분 개선됨.

`_startVm()`은 argument list를 사용하지만 중지·삭제는 `Shell.run(command.join(' '))`이다. `my vm.conf`가 두 인자로 나뉘고 실행 파일 경로에 공백이 있어도 실패한다. SSH 사용자명 또한 문자열 조립에 들어가고 macOS Terminal 경로에서는 AppleScript 및 셸 문자열 escaping이 추가로 필요하다. process_run은 자체 명령 파서이므로 모든 구두점이 셸 명령으로 실행된다고 단정하지 않는다.

설계: 공통 runner를 통해 executable과 List<String>을 끝까지 분리한다. Terminal 어댑터만 별도로 quoting하고 SSH username/port를 검증한다. 중지 명령을 await하고 성공·재조회 이후 UI 상태를 바꾼다. 버전 조회 실패/파싱 실패도 사용자 오류로 처리한다.

### F6 — P2: 시작 시 저장 경로 오류가 UI 표시 자체를 막고 설정을 덮어씀

위치: `lib/src/globals.dart:13–34`, `lib/main.dart:87`. 현재 변경.

저장된 외장 디스크가 잠시 해제되면 fallback으로 바꾸고 기존 preference까지 덮어쓴다. fallback 생성이나 `Directory.current` 설정이 권한 문제로 실패하면 runApp 전에 예외가 전파된다. 존재 여부는 쓰기/탐색 가능 여부와 다르다.

설계: 저장된 경로와 현재 사용 가능한 경로를 분리한다. unavailable 상태에서 원래 선택을 보존하고 UI에서 재연결/폴더 선택을 제공한다. 기본 경로 생성은 예외 처리하고, 실제 사용할 작업에 절대 workingDirectory를 전달한다. 전역 cwd 변경을 최종적으로 없앤다.

### F7 — P2: 실행 파일 탐색이 PATH 우선순위와 실행 권한을 무시

위치: `lib/src/globals.dart:37–67`. 현재 변경.

Homebrew/시스템 경로가 기존 PATH보다 먼저 오므로 Nix devshell이나 사용자 지정 Quickemu를 다른 설치본으로 바꿀 수 있다. `existsSync()`만 검사하여 실행 불가능한 일반 파일도 발견된 것으로 취급한다. 상대 PATH 항목은 초기 cwd에서 resolve한 뒤 cwd가 바뀌는 점도 주의해야 한다. 터미널/spicy 탐색은 기존 whichSync여서 Quickemu용 환경 보완과 일관되지 않다.

설계: 명시적 사용자 선택 → 기존 PATH → 플랫폼별 보조 경로 순서. 모든 도구가 동일 resolver/environment를 사용하고 실행 가능 여부 및 실행 실패를 처리한다. Linux에 macOS 경로를 무조건 우선 삽입하지 않는다.

### F8 — P2: VM 상태 파일 경로 추정과 비동기 갱신 경쟁

위치: `lib/src/pages/manager.dart:115–172`, `:217–236`, `:280–299`, `:325–345`.

PID/ports/log를 `$name/$name.*`로 추정한다. 부모 workspace의 quickemu는 `VMDIR=$(dirname "${disk_img}")`를 사용하므로 config 이름과 디스크 디렉터리가 다르면 실행 중 VM을 꺼짐/시작 실패로 판단한다. 이는 실행 중 삭제 차단에도 영향을 준다. 기존 가정에 새 750ms 시작 확인도 의존한다.

시작 대기 중 저장 폴더 변경이 가능하며, 이후 `_getVms()`와 로그 읽기는 변경된 cwd를 참조한다. 동일 이름의 다른 VM으로 결과가 섞일 수 있다. `_detectSsh()`는 build 중 반복 호출되고 timeout과 완료 후 mounted 검사가 없어 화면을 나간 뒤 setState하거나 응답 없는 연결을 남길 수 있다. `.ports`의 열/포트 유효성 검사도 부족하다.

설계: 작업 시작 시 configPath/workingDirectory를 고정한다. refresh 세대 번호 또는 취소 토큰으로 오래된 결과를 버리고 폴더별 캐시를 분리한다. SSH probing은 build 밖에서 제한된 주기·timeout으로 수행한다. 상태 파일 위치는 지원하는 Quickemu 버전과 명시적 계약을 정한다. config를 source하여 파싱하지 말고, 지원 가능한 리터럴만 읽거나 backend 인터페이스를 확장한다. PID 존재만으로 프로세스 정체성을 완전히 증명할 수 없다는 점도 반영한다.

### F9 — P2: 목록 조회 실패·잘못된 CSV가 빈 목록 또는 무한 로딩이 됨

위치: `lib/main.dart:26–64`, `lib/src/pages/operating_system_selection.dart:70` 이후. 기존 문제.

exitCode/stderr 검사가 없고 4열이 아닌 행은 최소 5열이라고 가정한다. 실패한 quickget은 빈 목록이 되며 짧은 행은 RangeError를 낸다. FutureBuilder가 hasError를 처리하지 않아 예외 시 로딩 표시를 계속 보여 준다.

설계: 프로세스 성공 검증과 CSV parser를 분리하고 4/5/7열 호환 fixture를 만든다. 빈 목록, 조회 실패, 로딩을 구분하고 재시도를 제공한다. 로컬 quickget의 CSV에는 현재 arch 열이 없으므로 GUI에 ARM 옵션만 추가하지 말고 backend 목록/다운로드 인자 계약을 먼저 확인한다.

### F10 — P2: 쓰기 권한 검사에서 사용자 파일 삭제

위치: `lib/src/widgets/home_page/home_page_button_group.dart:89–101`. 기존 문제.

고정 이름 `modecheck.tmp`가 있으면 내용을 확인하지 않고 삭제한다. 다운로드 버튼 클릭이 기존 사용자 파일을 지우는 결과를 낳는다.

설계: 대상 디렉터리에 고유한 임시 디렉터리/파일을 생성하고 자신이 생성한 것만 finally에서 정리한다. 권한 오류도 같은 try 범위에서 처리한다.

## 미병합 PR에서 차용할 부분

| PR / 실제 상태 | 판단 | 차용 범위와 보완 |
| --- | --- | --- |
| [#224](https://github.com/quickemu-project/quickgui/pull/224) / open | 우선 추천 | 중첩 SingleChildScrollView + shrinkWrap 목록을 단일 ListView + Scrollbar/controller로 변경. 세 선택 화면에 적용하되 FocusNode dispose, 검색 후 스크롤 위치, 오류 UI도 보완. |
| [#303](https://github.com/quickemu-project/quickgui/pull/303) / open | 아이디어 선별 | null/empty/존재하지 않는 저장 경로 검사, 초기화 await. 현재 중앙 초기화와 중복되므로 페이지 initState를 통째로 이식하지 않는다. AssetManifest.json try/catch 대신 F2 수정. mounted·권한 처리는 추가 필요. |
| [#275](https://github.com/quickemu-project/quickgui/pull/275) / open | 안정화 후 | 성공한 다운로드에서 Manager로 이동, 새 VM 강조. 최근 수정된 폴더를 VM으로 선택하는 구현과 실패/취소에서도 등록하는 구현은 채택하지 않는다. 생성된 config를 검증해서 정확한 경로를 반환한다. `getPreference<List<String>>` 분기 수정은 작은 독립 개선으로 유용. |
| [#266](https://github.com/quickemu-project/quickgui/pull/266) / open | 후속 기능 | config 경로 모델과 편집 UI 분리. 현재 PR은 로딩 중 Save가 활성화돼 빈 문자열을 저장할 수 있다. 로딩/저장 중 disable, mounted/dispose, 외부 변경 감지, 같은 디렉터리 임시 파일 + 원자적 교체, 실패 시 원본 보존 필요. Bash config의 주석·표현식을 보존하고 GUI가 임의 실행하지 않는다. |
| [#322](https://github.com/quickemu-project/quickgui/pull/322) / open | 대안 비교 | flutter_distributor 0.6.8 bump. 현재 fastforge 전환과 동일 변경이 아니다. 한 packaging PR에서 하나의 경로를 선택하고 CLI 버전도 pin해 산출물 검증. |
| [#307](https://github.com/quickemu-project/quickgui/pull/307) / open | 중복 제출 불필요 | CONTRIBUTING 링크 수정. 현재 기여 문서의 잘못된 링크와 관련 있으나 사용자 런타임 버그 해결과 분리. |
| [#305](https://github.com/quickemu-project/quickgui/pull/305) / open | 별도 번역 | Georgian 번역. 현재 기능 안정화와 독립. |
| #324, #320, #318, #317 / open | 별도 CI 관리 | Actions/Nix 업데이트. 기능 코드의 차용 후보는 아니며 검증 없이 묶지 않는다. |
| [#98](https://github.com/quickemu-project/quickgui/pull/98) / closed, unmerged | UI 전면 이식 비추천 | 초기 로딩 상태 개선은 참고 가능. 플랫폼마다 다른 외형은 유지보수자가 의도한 동일 Flutter 외형과 맞지 않는다고 명시했다. |
| [#104](https://github.com/quickemu-project/quickgui/pull/104) / closed, merged_at null | 신규 후보로 취급하지 않음 | 유지보수자 댓글에 변경을 반영했다고 적혀 있다. API merged_at만으로 미반영이라고 판단하면 안 된다. |
| [#271](https://github.com/quickemu-project/quickgui/pull/271) / closed, unmerged | 그대로 채택하지 않음 | 캐시 서비스 종료를 이유로 교체했으나 유지보수자가 서비스 복귀를 안내했다. 당시 전제를 현재 장애의 근거로 쓰지 않는다. |

코드를 실제 차용할 때는 PR URL과 원 작성자/커밋을 기록하고 라이선스 및 저작자 표시를 유지한다. 제목만 참고한 것인지 코드 일부를 가져온 것인지 PR 설명에서 구분한다. 오래된 lockfile을 통째로 가져오지 않는다.

## 구현 구조

전면 재작성 대신 현재 Provider 기반 UI를 유지하면서 다음 경계를 점진적으로 만든다.

1. `ProcessRunner`: executable, arguments, environment, workingDirectory를 받는 공통 실행 계층. 실행 실패/종료 코드/출력/취소를 모델로 반환하고 fake 구현을 주입한다.
2. `ToolchainResolver`: quickemu/quickget/terminal/spicy 발견 및 버전·기능 확인. 플랫폼별 보조 PATH를 여기서만 처리한다.
3. `WorkspaceSettings`: 선호 경로, 실제 선택 경로, 접근 가능 상태. 전역 Directory.current에 UI 상태를 저장하지 않는다.
4. `QuickgetService`: catalog parsing, DownloadSession, 생성된 config의 명시적 결과. 성공/실패/취소를 UI와 알림이 동일하게 사용한다.
5. `VmRepository` + `VmController`: 절대 config 경로 기반 목록/상태, VM별 작업 잠금, 시작 확인 timeout, refresh 경쟁 제어. 상태는 stopped/starting/running/stopping/deleting/unknown 등으로 구분하고 unknown에서 파괴적 조작을 허용하지 않는다.

macOS의 cocoa와 hda-output 강제 지정은 현재 환경의 workaround일 수 있다. 모든 guest와 Quickemu 버전에서 필요한지 확인하고 capability/platform 기본값으로 다룬다. 지원되지 않는 CLI 인자를 항상 붙이지 않는다. 사용자 config의 명시적 설정을 덮어쓸 정책도 문서화한다. SwiftPM으로 이동한 플러그인이 Podfile.lock에서 사라진 것은 그 자체로 누락 증거가 아니다. clean checkout에서 SwiftPM + CocoaPods 혼합 빌드를 검증한다.

## PR 분할과 검증 순서

아래 A–E를 먼저 PR용으로 구현하고 별도 전수 검증을 마친다. F/G는 그 이후 개인용에서 먼저 구현하며 후속 upstream PR 후보로 유지한다. 세부 진행 단계와 공통 커밋 전달 정책은 분리 운영 설계가 우선한다.

| 순서 / 제안 제목 | 포함 범위 | 완료 조건 |
| --- | --- | --- |
| A `build: align Flutter dependencies and desktop builds` | SDK 기준/CI, 필요한 패키지·lock 2종, macOS plugin/target; fastforge 전환은 필요 시 별도 A2 | clean pub get, Linux/macOS release, Nix build; 플랫폼 최소 버전 문서 일치 |
| B `fix: make startup and workspace selection recoverable` | F2/F6/F7, 목록 오류 F9, 초기 설정 UI | Finder의 최소 PATH, 기존 PATH 우선, 실행 권한 없음, 해제된 볼륨, 쓰기 금지, 아이콘 로딩, CSV 4/5/7열 |
| C `fix: report download failures and drain process output` | F3/F10, 결과 모델 및 취소/자원 정리 | exit 0/1/signal, start 실패, stdout/stderr 대용량, 늦게 도착한 출력, 취소 후 자식 종료, 기존 modecheck.tmp 보존 |
| D `fix: serialize VM actions and preserve command arguments` | F4/F5/F8, VM별 작업 상태 | 공백/한글/따옴표 경로, 시작 중 삭제, 확인 대기 중 외부 시작, 폴더 전환, 잘못된 ports/PID, SSH timeout, 화면 dispose |
| E `fix: restore scrolling in selection lists` | #224 기반 세 선택 화면 | 휠/트랙패드/스크롤바, 검색 후 목록 축소, 긴 목록, 화면 반복 열기/닫기 |
| F `feat: open newly downloaded machines in the manager` | #275의 UX, 정확한 config 식별 | 성공한 VM만 강조, 다른 폴더가 최근 변경돼도 오인하지 않음 |
| G `feat: edit stopped virtual machine configurations` | #266 보완 | 로딩 중 Save 금지, 시작과 편집 잠금 공유, 파일 변경 충돌/권한 오류/저장 중 실패에서 원본 보존 |

B–E는 논리적으로 작은 PR로 유지한다. A 전체 현대화가 지나치게 크면 upstream이 받아들일 SDK 기준에서 최소 의존성으로 다시 구성하고, 공통 코드가 필요한 PR만 순차적으로 쌓는다. 단순 포맷 변경과 `.DS_Store` 변경을 기능 PR에 섞지 않는다. `.DS_Store`는 이미 추적된 것도 있으므로 ignore 추가만으로는 제외되지 않는다. 의도한 파일만 stage한다.

권장 검증 계층:

- unit: resolver/path/parser/argument builder/status reducer. runner fake로 예외·종료·순서 제어.
- widget: download 실패 문구, starting 중 delete disabled, 폴더 접근 실패 복구, scrolling, dispose 후 callback.
- integration: 임시 가짜 quickget/quickemu가 실제 파이프에 큰 출력을 쓰고 지연 종료. 실제 VM은 별도의 수동 smoke로 확인.
- CI: format check, analyze, test, Linux release, macOS release. Nix lockfile 변환과 build 확인. 모든 테스트 통과 전 PR 체크리스트의 무회귀 항목을 체크하지 않는다.

## fork와 제출 준비

출발점: [upstream](https://github.com/quickemu-project/quickgui), [fork](https://github.com/kimdongup/quickgui), [비교](https://github.com/quickemu-project/quickgui/compare/main...kimdongup:quickgui:main).

현재 사용자 변경을 보존한 상태에서 다음을 **후속 구현 시** 수행한다. 이번 설계 보강에서는 remote/branch/commit/push를 변경하지 않았다. 사용자는 구현물을 fork에 push하며 관리하는 방향을 명시했다.

1. 현재 미커밋 변경을 안전하게 보존한 후 upstream main 기준의 작업 branch 또는 별도 worktree에 PR별 변경을 재구성한다. 현재 작업 디렉터리에서 reset/checkout으로 수정분을 덮어쓰지 않는다.
2. 기존 origin을 upstream으로 rename하고 `https://github.com/kimdongup/quickgui.git`을 origin으로 등록한다. 실제 현재 상태와 목표 설정을 구분한다.
3. 예: `pr/recoverable-startup`을 만들고 B에 필요한 hunk만 포함한다. `git diff --check`, 변경 범위 확인, 해당 테스트를 거친다.
4. 구현 중 검증을 마친 단위로 `git push origin <branch>`하여 fork 이력과 CI를 관리한다. 전수 검증 후 upstream PR base는 `quickemu-project/quickgui:main`, head는 `kimdongup:pr/<topic>`으로 설정한다. 개인용 main과 통합 브랜치 전체는 upstream PR head로 사용하지 않는다.
5. 저장소 `.github/pull_request_template.md`와 Conventional Commits 제목을 사용한다. 의존성 변경 시 pubspec.yaml/lock 및 Nix용 pubspec.lock.json을 함께 갱신한다. API에서 이슈 해결이 검증되지 않은 번호는 임의로 Closes에 넣지 않는다.

첫 런타임 PR(B)의 설명 초안 — 구현 완료 후 실제 변경/검증에 맞춰 수정:

> When Quickgui is launched with a minimal desktop PATH or a saved VM directory is unavailable, startup can fail before a recovery screen appears. This change centralizes tool discovery and workspace validation, preserves the saved location when it is temporarily unavailable, and lets the user choose a usable directory. It also loads OS icons through Flutter's supported AssetManifest API and reports catalog loading failures.
>
> Related work: #303. Validation: [fill in completed resolver, workspace, asset, and catalog tests; list macOS/Linux smoke results].

이 초안은 구현됐다는 보고가 아니라 제출 시 사용할 예정 설명이다. A와 B를 합친 것처럼 SDK/packaging 변경을 이 설명에 덧붙이지 않는다.

## 실행한 검증

- `flutter analyze --no-pub`: 로컬 Flutter 3.47.2 / Dart 3.13.2, error/warning 0, info 8, 명령 종료 코드 1. 정보 수준 항목도 남아 있어 clean analyze라고 표현하지 않는다.
- info: private State 반환형 2건, 직접 dependency에 없는 path import, manager 타입 추론 2건, 문자열 조립 1건, version_selection async context 1건, 불필요 Container 1건.
- `git diff --check`: 통과.
- `flutter test --no-pub /tmp/quickgui-review/review_probe_test.dart`: 진단 4건 통과. 현재 getIcons의 FlutterError, exit 1의 catalog 호출이 빈 목록을 반환함, 실행 권한 없는 파일을 resolver가 채택함, `my vm.conf`가 `my`와 `vm.conf`로 분리됨을 실제 확인했다. 정상 동작 회귀 테스트와 달리 현재 결함의 존재를 확인하는 진단이다. 진단 코드의 누락된 FlutterError import를 보완한 뒤 실행한 최종 결과다. 임시 파일은 OS 정리 대상이며 정식 테스트 suite에는 포함하지 않았다.
- 빌드 산출물이 이미 존재하는 것은 이번 리뷰에서 새 빌드가 통과했다는 증거로 사용하지 않았다.
