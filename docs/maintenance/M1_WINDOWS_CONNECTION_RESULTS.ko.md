# M1 Windows ARM64 연결 작업 기록

2026-09-10 HST / 2026-09-11 UTC. **부분 구현이며 SSH/SPICE 실접속 완료가 아니다.**
최신 `origin/personal/preview` `13860d6`에서 별도 worktree의
`personal/windows-arm-connections`를 만들었다. 구현·단위 검사·release 빌드 소스는
`f2ef0ec5ee43d125e20384c38841c7d3674329fe`다.
[기계 판독 기록](evidence/m1-windows-connections.json)을 함께 참고한다.

## 직접 확인한 결과

| 항목 | 결과 |
| --- | --- |
| 시작 경로 | 첫 명령 `pwd`: `/Users/mac/quickemu/quickgui` |
| 기존 작업 | `personal/apple-silicon`의 미커밋 `pubspec.lock` 보존. 시작/후속 SHA256 일치 |
| 호스트 | ARM64, macOS 26.6.2 / 25G83 |
| 시작 시 VM | Quickgui/QEMU/swtpm 실행 없음. 설치 완료 상태이며 기존 ISO 존재 |
| 보존 | 정지 상태의 VM bundle 전체를 APFS clone으로 별도 백업. UUID/MAC/ISO 참조·자원 설정 유지. UEFI code는 백업과 바이트 해시 일치. 기존 디스크·TPM·NVRAM 경로 재사용 |
| SSH 전달 | native backend가 loopback의 사용 가능한 포트 50827을 선택하고 `vm.json`에 저장. QEMU 인자 `hostfwd=tcp:127.0.0.1:50827-:22`. 새 native 프로세스 실행 후 동일 포트 복원 |
| 포트 충돌 | VM 디스크를 열지 않는 `-machine none` QEMU의 같은 포트 bind 시 exit 1. 기존 VM은 계속 실행됨 |
| 기존 화면 회귀 | 설치 ISO 없는 첫 부팅에서 QMP 화면으로 Windows 바탕화면 직접 확인. 이후 `system_powerdown` 정상 종료 요청과 프로세스 종료 확인 후 재실행 |
| SSH 인증 | **BLOCKED**. TCP listener 이후 SSH 배너 수신 5초 timeout. 게스트 OpenSSH 설치·서비스·방화벽 상태는 아직 모름. 재실행한 Windows의 PIN 화면에서 사용자 직접 로그인을 요청함 |
| ARM SPICE | 설치 QEMU 11.1.1 ARM64의 `-spice help`는 exit 1과 `-spice: invalid option`. 옵션 목록이 나오는 exit 1과 구분. SSH 인증 선행 조건 때문에 별도 backend 구축·화면·입력·재접속은 아직 수행하지 않음 |
| 앱 연동 | native 상태는 저장 포트와 현재 세션의 live 포트를 구분함. Flutter 설정 채널·버튼·앱 재접속은 **미구현/미검증** |
| 최종 VM | 검증용 native 실행기가 소유한 Cocoa VM 실행 중, Windows PIN 로그인 대기. 앱/VM 강제 종료하지 않음 |

원본 설치 ISO는 연결하거나 수정하지 않았다. ISO 수정 시각은 작업 이전이며 최초 전체
ISO 해시는 수집하지 않았다. TPM/NVRAM과 디스크는 부팅에 따라 정상적으로 변경될 수
있으므로 바이트 불변으로 기록하지 않는다. 개인 화면·사용자명·UUID/MAC·인증 정보는
저장소 증거에 포함하지 않는다.

## 구현 범위와 검증

기존 schema 1 metadata에 선택형 `sshPort`를 추가했다. 이전 VM은 첫 실행에 포트를
선택하며, 이후 실행에는 저장값을 사용한다. 포트 범위는 1024~65535다. 포트 변경용
native `configureSSH`는 VM lock과 소유 프로세스 확인을 거치며 실행 중에는 거부한다.
QEMU의 실제 bind 실패를 오류로 처리하며 무관한 프로세스를 종료하지 않는다.
`status`의 `savedSshPort`와 `sshHost`/`sshPort`를 구분해 정지·stopping·busy 상태에
오래된 live endpoint를 표시하지 않는다. 이 단계에서는 UI 포트 변경 기능이 없다.

- Swift native 검사: 30 PASS, exit 0. legacy metadata, 포트 저장/재조회,
  잘못된 포트, writer lock, orphan 소유자, loopback 인자 및 기존 VM 보호 검사 포함.
- `flutter pub get --enforce-lockfile`: exit 0, worktree lockfile 변경 없음.
- `flutter analyze --no-pub`: 문제 없음, exit 0.
- `flutter test --no-pub --reporter expanded`: 82 PASS, 4 opt-in skip, exit 0.
- `flutter build macos --release --no-pub`: 48.1 MB, exit 0.
  ARM64/x86_64 slice와 ad-hoc 서명, `codesign --verify --deep --strict` exit 0 확인.
  기존 `/Applications/quickgui.app`은 교체하지 않았고 새 Flutter 앱은 아직 실행하지 않았다.

실제 VM 전달 검사는 `configureSSH` helper 추가 전의 작업 트리를 컴파일한 native
실행기를 사용했다. 첫 실행은 Homebrew QEMU 그대로다. Cocoa UI 도구가 일반 실행
파일을 앱으로 식별하지 못해, 이후 ARM QEMU 바이너리의 바이트 사본을 별도 `.app`으로
등록했다. 첫 wrapper 실행은 ROM 탐색 실패로 종료됐으며 `-L /opt/homebrew/share/qemu`
추가 후 같은 VM이 정상 시작됐다. 이 wrapper는 검증용이며 앱 제품 코드에 포함하지 않는다.

로컬 백업·실행기·runtime.json·화면·전체 빌드 로그는 저장소 밖
`/Users/mac/quickemu/windows-connections-private-20260910`에 보관한다.
백업 폴더 `vm-backup`은 실행하거나 재설치용으로 사용하지 않는다.
새 release 앱은 작업 worktree의 `build/macos/Build/Products/Release/quickgui.app`이다.

## 이어서 할 일

Windows 창에서 사용자가 직접 PIN 로그인한 후 게스트 OpenSSH 상태를 읽는다.
[Microsoft OpenSSH 설치 안내](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)와
[키 인증 안내](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)를
따라 기존 인증 설정을 보존하면서 준비한다. 실제 SSH 인증·OS/ARM64 명령·재인증을
먼저 통과시킨 다음 ARM SPICE backend의 화면·입력·viewer 재접속, 마지막으로
플랫폼 채널·Flutter 접속 버튼·앱 재실행을 구현하고 검증한다.
현재 커밋을 `personal/preview`의 연결 기능 완료로 통합하지 않는다.
