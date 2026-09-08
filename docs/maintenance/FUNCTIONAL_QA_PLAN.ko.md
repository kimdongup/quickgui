# PR 구현 완료 후 기능 전수 검증 계획

작성일: 2026-09-08. 상태: **계획이며 아래 항목을 실행/통과했다는 기록이 아니다.**

목적: 기존 UI를 유지한 PR용 전체 구현을 완료한 다음, 개별 수정 테스트에서 놓치기 쉬운 실제 사용자 흐름과 기능 간 간섭을 확인한다. 운영 순서는 [분리 운영 설계](FORK_AND_UPSTREAM_STRATEGY.ko.md)를 따른다.

## 검증 환경과 데이터

- 기준 코드: topic별 head SHA와 integration/stabilization의 고정 SHA. 수정이 발생하면 새 SHA로 영향을 받는 검사와 핵심 전체 흐름을 다시 수행한다.
- 기준 UI: 변경 전 정상 홈/선택/다운로드/Manager/설정 화면. light/dark, 영어/한국어, 지원 창 크기, 고정 font/scale/platform 조건을 기록한다. 정상 화면의 기준선을 오류 화면으로 교체하지 않는다.
- backend: 공개 Quickemu의 최소 지원/주 검증 버전을 기록한다. 개인 수정 Quickemu는 별도 조합으로 기록한다. 구체 버전은 구현 시작 시 실행 가능한 버전과 실제 계약을 확인해 확정한다.
- 실제 동작 필수 대상: Linux x86_64와 현재 사용 중인 macOS의 실제 architecture. macOS의 다른 architecture와 Linux ARM64는 별도 목표로 구분하고 검증 전 지원 완료를 주장하지 않는다. Intel/ARM 빌드 성공만으로 가상화 가속 동작을 증명하지 않는다.
- Linux의 디스플레이 환경(X11/Wayland), macOS의 Terminal/Finder 실행, Homebrew/Nix/PATH 조합을 구분한다. guest는 host-native Linux를 기본 end-to-end 대상으로 하고 Windows/macOS/BSD 및 타 architecture는 backend가 지원하는 대표 사례를 별도 확장 검증한다.
- unit/widget는 fake filesystem/process/clock, 프로세스 integration은 실제 임시 executable/pipe/PID fixture, 최종 smoke는 별도로 만든 테스트 VM을 사용한다. 실제 사용 중인 VM으로 삭제/디스크 장애를 재현하지 않는다.
- 외부 ISO 다운로드 전체를 PR마다 반복하지 않는다. parser/실패/경쟁은 고정 fixture로 재현하고 release 후보에서 대표 실제 다운로드를 검증한다. 외부 서버 실패와 GUI 실패를 나눠 기록한다.

## 기능별 필수 시나리오

| QA ID / 기능 | 정상 흐름 | 오류·경계·경쟁 시나리오 | 수용 조건 |
| --- | --- | --- | --- |
| Q01 시작/도구 발견 | 터미널 및 Finder에서 실행 | quickget만 없음/quickemu만 없음/둘 다 없음, 실행 권한 없음, 경로 공백, PATH 중복·우선순위, 실행 파일 제거 | 각 원인 구별, 복구 가능한 UI, 의도한 executable 선택, 미처리 예외 없음 |
| Q02 초기 정보/아이콘 | 앱 버전·Quickemu 버전·OS 아이콘 표시 | package info 실패, version 실패/이상 문자열, asset 누락, 설정 읽기 실패 | 기능 설치 여부를 package info와 혼동하지 않음, 기본 아이콘·설정 복구, 무한 로딩 없음 |
| Q03 저장 경로 | 두 진입 화면에서 폴더 선택 후 재시작 | 미설정/빈 값/삭제된 경로/해제된 외장 볼륨/읽기 전용/홈 없음, 선택 취소, 저장 실패 | 기존 선호 경로 보존, 임의 fallback 덮어쓰기 없음, 작업별 경로 일관 |
| Q04 경로와 파일명 | ASCII·공백·한글 config/디렉터리 | 따옴표/괄호, 같은 이름의 다른 workspace, symlink, 파일 대신 디렉터리인 .conf, 바뀐/읽을 수 없는 파일 | 인자 경계 유지, VM 정체성 혼동 없음, 한 불량 항목이 목록 전체를 멈추지 않음 |
| Q05 목록 파싱 | 지원 4/5/7열 CSV fixture | CRLF/BOM/빈 행/부족한 열/quoted field/중복·순서 변경, 비정상 exit, 큰 목록, 잘못된 UTF-8 | 지원 형식 명시, 잘못된 데이터 진단, loading/empty/error 분리, 재시도 가능 |
| Q06 선택/검색/스크롤 | OS→버전→옵션→다운로드 | 옵션 0/1/여러 개, 취소 후 재선택, OS 변경 후 이전 옵션 잔류, 검색 후 목록 축소, wheel/trackpad/drag | 실제 선택과 명령 일치, null 예외 없음, 맨 아래 항목 접근, 선택 상태 오염 없음 |
| Q07 다운로드 성공 | curl/zsync 지원 조합의 성공 | 0%/100%/진행률 없는 출력, 여러 파일, 분할된 진행 문자열, 출력 chunk 경계, stdout/stderr 동시 대량 출력 | pipe 정체 없음, 진행률이 최종 성공 판정을 대신하지 않음, 종료/스트림 완료 후 성공 |
| Q08 다운로드 실패 | 실패 안내와 재시도 | start 실패, exit 1/2, signal, 중간 네트워크 끊김, 디스크 부족/권한 변경, 스트림 decode 오류 | 실패를 완료로 표시하지 않음, 관련 로그 확인 가능, 다시 시도 가능 |
| Q09 취소/생명주기 | 진행 중 취소→종료 결과 | start 완료 전 취소, 성공과 취소 동시 발생, 여러 번 취소, 자식이 계속 출력, 창 종료, 빠른 화면 이동 | 상태 전이 일관, 세션이 소유한 자식 정리, 다른 프로세스 보존, 닫힌 stream add/setState 오류 없음 |
| Q10 알림/권한 probe | 완료·취소·실패 메시지 | 알림 서비스 없음/알림 전송 실패, 기존 modecheck.tmp 존재, probe 생성 실패 | 알림 실패가 다운로드 결과를 덮어쓰지 않음, 기존 파일 내용·존재 보존 |
| Q11 VM 목록/상태 | config 발견, 외부 시작/종료 반영 | 빈/stale/손상 PID, 다른 프로세스 PID, 손상 ports, 다른 disk_img 디렉터리, 해석 불가 경로, 목록 읽는 중 파일 제거 | running/stopped/unknown 구분, 파괴적 조작 전 상태 재확인, 목록 갱신 지속 |
| Q12 시작 | VM 시작과 상태 반영 | 지연 PID, 즉시 QEMU 실패, 미지원 display/sound, 두 번 클릭, 두 VM 동시 시작, 대기 중 폴더 변경 | VM당 시작 1회, 다른 VM 독립, 오류·로그 제공, 오래된 결과가 새 workspace에 반영되지 않음 |
| Q13 중지 | 확인→중지→상태 재조회 | 확인 취소, version 파싱 실패, kill 실패, 도중 외부 종료/재시작, 창 닫기 | 실패를 꺼짐으로 선반영하지 않음, 잘못된 프로세스 종료 없음, 종료 여부 재조회 |
| Q14 디스크/VM 삭제 | 폐기 가능한 VM에서 각각 실행 | starting/running/stopping/unknown, 확인창 대기 중 외부 시작, config·disk 경로 불일치, 권한 실패, 재클릭 | config 유지/전체 삭제의 약속 일치, 실행 중 삭제 차단, 실패 표시, 다른 파일 보존 |
| Q15 SSH | 탐지→사용자명 입력→지원 터미널 연결 | 서버 없음/응답 없는 socket/분할 banner, 잘못된 port/사용자명, 클라이언트 없음, osascript 실패, 화면 dispose | connect/read timeout 및 socket 정리, 인자/escaping 검증, 중복 probe 제한, 미처리 예외 없음 |
| Q16 SPICE | Linux client 연결/재연결 | port 없음/잘못된 port, client 없음/실행 실패, macOS 미지원 조합 | 가능한 조합에서만 활성, null 강제 해제 없음, 원인 표시, 지원하지 않는 플랫폼 기능을 성공으로 표시하지 않음 |
| Q17 설정/번역 | theme/locale 변경→종료→재실행 | 지원하지 않는 locale, region/encoding 포함 값, 잘못된 preference 타입, 번역 누락, package info 없음 | 설정 보존/fallback, drawer 열기 실패 없음, 언어 변경이 선택/작업 상태 초기화하지 않음 |
| Q18 UI/내비게이션 | 기존 버튼/화면 이동/키보드 동작 | 최소/최대 창, 긴 경로/이름/번역, dark/light, focus 순서, OS 제공 back/escape | 레이아웃 overflow 없음, 주요 UI 유지, 작업 중 불가능한 버튼 차단, controller/listener 정리 |
| Q19 반복/동시 조작 | 목록 및 화면 반복 열기/닫기 | 30회 화면 전환, 10회 fixture 시작/취소, 여러 workspace 전환, 늦은 refresh/SSH 응답 | 예약 timer/구독/child/socket 수가 초기 안정 상태로 복귀, 상태 뒤섞임/지속 증가 없음 |
| Q20 빌드/설치 | clean checkout 의존성 해결·빌드·설치 실행 | 최소/주 SDK, macOS SwiftPM+Pods, Linux/Nix, lockfile만 변경, macOS만 변경, fork PR secret 없음 | 필수 CI 실제 실행, 생성 산출물 존재, 설치한 release에서 smoke 통과 |
| Q21 사용자 전체 흐름 | 시작→경로→OS 선택→다운로드→Manager→시작→연결→중지→재시작 | 다운로드 실패 후 복구, 앱 재실행 후 기존 VM 탐지, 다른 workspace 전환 | 현재 UI로 전체 흐름 완료. 실제 VM 실행/연결/중지와 로그를 기록 |

Q14의 앱 내부 직렬화와 실행 전 재검증만으로 다른 프로그램과의 모든 filesystem 경쟁을 완전히 막았다고 주장하지 않는다. backend가 제공하는 원자적 보장 범위를 확인하고, 확인할 수 없는 상태에서는 오류로 반환하도록 검증한다.

## 개인 기능의 추가 수용 조건

| QA ID / 기능 | 검증 내용 |
| --- | --- |
| X01 새 VM 이동/강조 | 성공한 config만 선택, 취소/실패 제외, 기존 VM 덮어쓰기 여부 구별, 최근 수정된 엉뚱한 폴더 무시, workspace 간 같은 이름 구별, 강조 해제 정책 일관 |
| X02 config 편집 | load 중 Save disabled, load/save 실패와 dialog 종료, 동시 외부 편집 감지, 임시 저장 실패 시 원본 보존, 주석·개행·권한 유지, symlink 정책, VM 시작과 편집 잠금 공유 |
| X03 고급 설정 | 기본값에서 PR용과 같은 명령 생성, override 저장·해제·재시작, 미지원 backend 옵션 처리, CPU architecture와 다운로드/실행 계약 일치 |
| X04 개인 배포 | repo/tag/SHA/asset 대상 일치, upstream 배포 job 미실행, 개인 식별 정보 및 checksum, 업그레이드 설정 보존, 별도 설치 ID 사용 시 upstream과 충돌 없음 |

## 테스트 구성과 완료 판정

테스트는 함수 이름/구현 문자열을 복제하기보다 사용자에게 보장하는 결과를 검증한다. unit은 파싱·인자·상태 전이, widget은 표시/버튼/생명주기, 프로세스 integration은 실제 파이프·종료·취소를 맡는다. 모든 경우를 느린 실제 VM 테스트로 옮기지 않는다.

UI 비교는 고정 환경의 대표 정상 화면 golden과 실제 Linux/macOS 스크린샷을 함께 사용한다. golden 갱신은 변경 이유를 기록하고 필요한 화면만 한다. 하나의 OS에서 생성한 golden을 모든 OS 렌더링의 절대 기준으로 사용하지 않는다.

완료 조건:

1. PR용 CORE-01–08 구현 완료. F1–F10와 전수 검토에서 발견된 공통 결함에 재현/수정/회귀 근거가 있다.
2. `dart format --output=none --set-exit-if-changed lib test integration_test`는 존재하는 대상 디렉터리에 대해 실행, `flutter analyze`는 info 포함 0, 정식 테스트와 필요한 desktop/Nix 빌드 통과. 기존 info를 무시하는 analyzer 제외 확대로 통과시키지 않는다.
3. Q01–Q21의 적용 가능한 필수 항목이 정확한 후보 SHA에서 pass. 미지원 조합은 근거를 남기고 지원 목록에서 제외한다. 필수 host 환경을 사용할 수 없어 실행하지 못한 경우 상태는 not-run이며 PR용 전수 검증 완료로 표시하지 않는다.
4. Linux x86_64와 현재 macOS host에서 Q21 실제 smoke를 완료한다. VM console/SSH/SPICE는 backend와 host가 지원하는 경로를 검증한다. 빌드 job 성공으로 이 항목을 대체하지 않는다.
5. 정상 화면의 원치 않는 UI 변경, 미처리 비동기 예외, 고아 다운로드 프로세스, 다른 VM/사용자 파일에 대한 변경이 없다.
6. topic별 최소 diff와 통합판을 모두 확인한다. 통합판에서만 다른 topic 덕분에 우연히 통과하는 PR은 의존성 또는 제출 순서를 수정한다.
7. 발견 결함은 담당 topic에서 수정하고 영향받는 테스트 및 Q21을 다시 확인한다. 이미 통과한 무관한 검사를 이유 없이 반복하지 않는다.

## 검증 결과 기록 양식

아래는 실행 시 채우는 템플릿이다. 빈 칸이나 NOT RUN은 통과를 의미하지 않는다.

```text
Candidate SHA / topic:
Upstream base SHA:
Host OS / architecture / display environment:
Flutter / Dart / Quickemu / quickget version:
Quickemu source: public release | personal revision
QA ID / fixture or disposable VM:
Command or UI actions:
Expected result:
Actual result:
Status: PASS | FAIL | NOT RUN | NOT APPLICABLE (reason required)
Log / screenshot / CI run URL:
Related defect / fix SHA / retest result:
```

개인 정보가 들어 있는 경로·사용자명·로그는 upstream PR에 올리기 전에 필요한 재현 정보만 남긴다. 로컬 원본 증거와 공개용 설명을 구분하고, 실제 실행하지 않은 체크리스트 항목은 체크하지 않는다.
