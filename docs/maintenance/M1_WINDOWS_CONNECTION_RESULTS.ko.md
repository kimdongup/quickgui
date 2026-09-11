# M1 Windows ARM64 연결 작업 기록

## 최종 검증 — 앱 코드 `1877d60`

요청 순서대로 SSH 인증·재접속 → SPICE 화면·입력·재접속 → 앱 연동을 수행했다.

| 항목 | 실제 결과 |
| --- | --- |
| SSH | 별도 인증 두 번, 게스트 명령 exit 0. Windows build 26200, OS·프로세스 Arm64. 앱이 시작한 VM에서도 08:29:03/08:30:04 UTC 재검증 PASS |
| SPICE 화면 | 800×600 Windows 바탕화면과 메모장을 실제 SPICE display 채널로 수신 |
| SPICE 포인터·키보드 | SPICE 절대 좌표 클릭으로 시작 메뉴·메모장·새 탭을 열고 `k` 입력 확인 |
| SPICE 재접속 | 클라이언트 프로세스 종료 후 새 접속에서 `k` → `kk`. 앱 VM에서도 `kk` → `kkk` → `kkkk` 확인 |
| 앱 설정 | 잘못된 포트 거부, 50827/SPICE 저장, 앱 정상 종료·재실행 후 같은 값 확인 |
| 앱 시작·SPICE | 기존 VM을 앱 Run으로 시작. 새 소켓과 연결 버튼 확인. 앱 버튼으로 viewer 연결, viewer만 종료 후 버튼 재접속 시 새 연결 ID와 4개 채널 확인 |
| 앱 SSH | 버튼으로 Terminal에 올바른 SSH 명령 실행. 최초 호스트 키 등록 후 인증 전에 종료됐지만 재시도에서 사용자가 Windows 명령 프롬프트 진입 성공 확인 |
| 로컬 검사 | Swift 35, Flutter 87 PASS / 4 opt-in skip, analyze no issues, macOS release 48.2 MB 빌드 PASS |

SPICE 입력의 화면 변화는 `tool/spice/capture.c`와 실제 게스트로 확인했다.
일반 Homebrew spicy GTK 창은 macOS 접근성 도구에서 timeout이 발생했다.
일반 viewer의 프로세스·QMP 채널 연결/재접속은 확인했지만, 해당 창의 메뉴·클립보드·
오디오·USB 리디렉션까지 검증했다고 주장하지 않는다. 개인 파일이 보이는 원본
스크린샷과 상세 로그는 로컬 비공개 폴더에만 보관했다.

앱 SSH 최초 시도에서 사용자가 제공한 지문은 앞서 확인한 게스트 키와 일치했다.
암호 입력 전에 연결이 닫힌 원인은 입증하지 못했으며, 키 확인 중 로그인 제한 시간
만료 가능성으로 설명했다. 다시 앱 버튼을 누른 뒤 사용자가 암호 인증 성공을 확인했다.
서버 인증 설정이나 Hello 옵션을 추가 변경하지 않았다.

최종 앱은 릴리스 빌드 사본에 별도 bundle identifier와 ad-hoc 서명을 적용한
`Quickgui Connections.app`이다. 기존 `/Applications/quickgui.app`을 교체하지 않았다.
앱 재시작 후 실제 VM 실행까지 확인했고, 실행 중인 QEMU를 남겨 앱만 재시작하는
비정상 소유권 인계는 지원한다고 주장하지 않는다. 이전 owner 보호를 유지한다.

기존 VM UUID/MAC·CPU/메모리·이미지 참조·설치 완료 상태와 firmware code 해시를
최초 APFS clone과 대조해 일치했다. 쓰기 가능한 디스크·TPM·NVRAM은 정상 게스트
사용에 따라 갱신됐고 원래 경로와 백업을 유지한다. 원래 작업 트리에는 기존
`M pubspec.lock`만 있으며 SHA256은
`c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` 그대로다.
최종 VM은 바탕화면에서 실행 중이며 검증 앱과 SPICE viewer를 열어 두었다.

코드 `1877d60`의 Build Quickgui 및 Public Quickemu smoke CI는 모두 성공했다.
현재 구조화된 결과와 CI 링크는 [JSON](evidence/m1-windows-connections.json)을 따른다.
아래는 이전 단계별 이력이다.


## 최신 상태 — 2026-09-11 08:17 UTC

전용 ARM64 QEMU/SPICE backend를 구성했고, `ac6c3a1`의 단일 화면 선택 수정으로
SPICE client mouse가 동작한다. 기존 GPU 두 개는 유지하면서 ramfb만 SPICE로
노출했다. 800×600 Windows 잠금 화면을 실제 SPICE로 수신했고, 절대 좌표 클릭으로
PIN 로그인 화면으로 전환했다. 일반 spicy 프로세스의 main/display/inputs/cursor
연결도 확인했다. macOS 접근성 도구는 이 GTK viewer 창에서 timeout을 반환했으므로
일반 viewer GUI 조작은 아직 확인하지 못했다. 전용 SPICE C 검증기로 화면·클릭을
확인한 결과와 구분한다.

같은 VM의 새 backend에서 08:13:08/08:13:47 UTC에 별도 SSH 인증 두 번과
Windows ARM64 명령 실행이 모두 exit 0이었다. 계정·암호는 공개 증거에 포함하지
않았다. 기존 Microsoft 계정이나 Windows Hello 설정은 변경하지 않았다.

현재 VM은 정상 종료 후 재시작하여 PIN 로그인을 기다린다. 로그인 후 메모장 입력,
viewer 종료·재접속 후 입력, 그 다음 Flutter 앱 연동이 남았다. 이 항목들은 PASS로
기록하지 않는다. Swift 검증 35개 통과. 이전 Flutter/CI 결과는 이전 커밋의 결과다.
빌드 절차와 두 화면 문제는 [ARM SPICE backend 기록](M1_WINDOWS_SPICE_BACKEND.ko.md),
구조화된 현재 결과는 [JSON](evidence/m1-windows-connections.json)에 있다.

아래는 이전 단계의 이력이다.

2026-09-10 HST / 2026-09-11 UTC. **SSH 실제 로그인·재접속 PASS. SPICE·앱 연동은 아직 진행 중이다.**
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
| SSH 인증 | **BLOCKED**. 사용자가 PIN 로그인을 완료했고 `get-service sshd`는 서비스 없음으로 반환. 사용자가 OpenSSH 설정을 직접 하기로 선택했으며 완료 응답 대기 중. SSH 배너도 아직 수신하지 못함 |
| ARM SPICE | 설치 QEMU 11.1.1 ARM64의 `-spice help`는 exit 1과 `-spice: invalid option`. 옵션 목록이 나오는 exit 1과 구분. SSH 인증 선행 조건 때문에 별도 backend 구축·화면·입력·재접속은 아직 수행하지 않음 |
| 앱 연동 | native 상태는 저장 포트와 현재 세션의 live 포트를 구분함. Flutter 설정 채널·버튼·앱 재접속은 **미구현/미검증** |
| 최종 VM | 검증용 native 실행기가 소유한 Cocoa VM 실행 중, Windows 바탕화면/PowerShell에서 사용자 OpenSSH 설정 대기. 앱/VM 강제 종료하지 않음 |

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

사용자 PIN 로그인은 완료됐다. 게스트의 `sshd` 서비스가 없는 것을 직접 확인했다.
사용자가 OpenSSH 설치·자동 시작·NAT 호스트로 제한한 방화벽 설정을 직접 진행하기로
선택했으므로 그 완료를 기다린다.
[Microsoft OpenSSH 설치 안내](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)와
[키 인증 안내](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)를
따라 기존 인증 설정을 보존하면서 준비한다. 실제 SSH 인증·OS/ARM64 명령·재인증을
먼저 통과시킨 다음 ARM SPICE backend의 화면·입력·viewer 재접속, 마지막으로
플랫폼 채널·Flutter 접속 버튼·앱 재실행을 구현하고 검증한다.
현재 커밋을 `personal/preview`의 연결 기능 완료로 통합하지 않는다.


## 원격 CI와 다음 인증 도구

원격 `b40ea3cac09abbba56f11c423552858875e3b916`의
[Build Quickgui](https://github.com/kimdongup/quickgui/actions/runs/34563590157)와
[Public Quickemu smoke tests](https://github.com/kimdongup/quickgui/actions/runs/34563590153)는 모두 success다.

`tool/check_windows_ssh.py`를 추가했다. 사전에 검증한 host key가 들어 있는
`--known-hosts`, 저장된 `--port`, 결과 저장 `--output`을 지정한다.
`--user`를 생략하면 로컬 터미널에서 로그인 이름을 묻는다. 암호는 SSH의 터미널
프롬프트에서만 입력한다. 각 SSH 프로세스의 connection multiplexing을 끄고 별도로
인증·게스트 명령을 실행한다. PowerShell에서 Windows OS와 Win32_Processor의 ARM64
코드 12를 확인하며 개인정보를 제외한 JSON을 기록한다. 현재 CLI help 실행만
확인했으며 실제 인증 검증은 사용자 OpenSSH 설정 이후에 수행해야 한다.

## OpenSSH 설정 후 확인 (2026-09-11 UTC)

사용자가 OpenSSH 설치·자동 시작을 완료했다. 도구로 Windows PowerShell의
`Installed`와 `sshd Running`을 직접 확인했다. 최초에는 SSH 배너가 오지 않았다.
조회 결과 게스트 네트워크는 `Public`, OpenSSH 방화벽 규칙은 `Private`였다.
사용자의 실행 직전 승인을 받은 뒤 다음 명령을 실행했다.

```powershell
Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Profile Any -RemoteAddress 10.0.2.2
```

그 직후 기존 loopback 전달 주소에서 `SSH-2.0-OpenSSH_for_Windows_9.5` 배너를
수신했다. 게스트의 ED25519 공개키 지문과 맥의 해당 포트에서 받은 키 지문이
일치함을 직접 대조했다. 기존 암호·인증 키는 변경하지 않았다.

컴퓨터 사용 도구가 `com.apple.Terminal` 접근을 안전 제한으로 거부했다.
사용자가 로컬 `windows-connections-private-20260910/verify-ssh.command`를 직접
실행하고 두 번 암호를 입력하도록 요청했다. 이 시점에는 인증 결과 JSON이 아직
생성되지 않았으므로 SSH 로그인·재접속은 여전히 BLOCKED다. SPICE 구축·게스트
입력·앱 연동은 SSH 실인증 이후에 진행한다. VM은 Windows 바탕화면 상태로 실행 중이다.

소스 `4e9b8de9f91f0bfe8b6e6f7c4207d1b6fa146a6c`의
[빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34564212677)와
[smoke CI](https://github.com/kimdongup/quickgui/actions/runs/34564212440)는 모두 success다.


## SSH 실제 인증·재접속 PASS (2026-09-11 07:37 UTC)

사용자가 지정한 별도 로컬 SSH 계정으로 인증했다. 계정 이름과 암호는 공개 증거에
포함하지 않는다. 처음 검증기는 WMI 조회에서 `CimException`을 만나 exit 1로
끝났으므로 인증 실패와 구분했다. WMI 실패의 세부 원인은 확정하지 않았다.
계정 권한이나 인증 설정을 변경하지 않고 .NET `RuntimeInformation`으로 OS 및
OS/프로세스 아키텍처를 읽도록 검증기를 수정했다.

`7ab5a34`의 검증기로 07:37:09와 07:37:26 UTC에 별도 SSH 프로세스를 시작했다.
각 세션은 새로 암호 인증했고 각각 원격 명령 exit 0을 반환했다. 양쪽 모두
`Microsoft Windows 10.0.26200`, `10.0.26200.0`, OS `Arm64`, 프로세스 `Arm64`다.
Windows 11의 커널 버전 문자열을 그대로 기록하며 제품명이 Windows 10이라는 뜻으로
해석하지 않는다. connection multiplexing은 비활성화되어 기존 세션을 재사용하지 않았다.
호스트의 검증기 전체 exit도 0이다. 이 결과가 앞선 BLOCKED/FAIL 시점 기록을 대체한다.
