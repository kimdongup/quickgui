# M1 Windows ARM64 SSH/SPICE 검증 인계

2026-09-10. 사용자는 Windows ARM64의 후속 작업을 **맥미니의 기존 Codex 세션에서 이어서 검증**하기로 했다. 이 문서는 이미 설치된 Windows VM의 연결 기능 구현·검증을 위한 인계이며, 새 VM 설치 절차가 아니다.

## 시작 기준과 완료 기록

| 항목 | 현재 기준 |
| --- | --- |
| 사용자 fork | `https://github.com/kimdongup/quickgui.git` |
| 통합 개인 후보 | `personal/preview`, 인계 작성 시 원격 `381b59f`. 앱 코드 기준은 `f48009b`; 이후 문서 갱신 커밋을 포함한 최신 원격을 작업 시작 시 확인한다 |
| 기존 M1 브랜치 | `personal/apple-silicon`, 마지막 확인 `f3f5c2b`. M1 작업 폴더의 미커밋 `pubspec.lock`은 사용자 변경으로 보존한다 |
| 기존 설치 앱 | 마지막 M1 검증은 앱 코드 `0517cf2`의 `/Applications/quickgui.app` 기준이다. 통합 후보를 push했다는 사실만으로 설치 앱이 교체된 것은 아니다 |
| 기존 Windows VM | `/Users/mac/quickemu/Windows 11 ARM64.quickgui-winarm` |
| M1 macOS ARM | 바탕화면·재부팅·SSH를 사용자가 완료 확인했다. 이번 Windows 검증에서 반복하지 않는다 |
| Intel macOS SSH | 이번 Intel 작업에서 실제 SSH 인증·게스트 명령·재접속을 통과했다. SSH에서 macOS `15.7.9`, build `24G830`, `x86_64`를 확인했고, 앱의 `detectSsh`도 성공했다. Remote Login UI 활성화와 임시 제한 키 인증을 사용했다 |
| Intel macOS SPICE | 설치 게스트의 1920×1080 화면·프로토콜 키 입력·포인터 클릭·재접속, 실제 spicy 프로세스 교체 후 채널·화면 데이터 수신을 확인했다. 호스트 화면 잠금으로 실제 spicy 창의 직접 입력은 미확인이다. 앱 조회·접속 인자 서비스 검사는 통과했으며 일반 Run의 SPICE 자동 설정은 미연동이다. [Intel 상세 기록](MACOS_SPICE_BACKEND.ko.md)과 [JSON](evidence/intel-macos-connections.json)을 따른다 |

Intel 세션에서 발견한 `cokacremote` 연결은 `x86_64` 호스트 `workmachine`이며 M1 맥미니가 아니었다. 이번 ARM 검증은 맥미니의 기존 세션과 로컬 도구로 진행한다.

Windows ARM64의 초기 설정·바탕화면·키보드/마우스 입력·HTTPS·정상 종료·설치 후 부팅은 사용자 확인 완료다. 같은 VM의 Quickgui 재실행, 설치 ISO 없는 실행, 설치 완료 표시 저장과 외부 TCP 통신도 [M1 실행 기록](M1_VALIDATION.ko.md)에 있다. 이 완료 항목들을 다시 설치하거나 처음부터 검증하지 않는다. 연결 구현으로 영향을 받는 재실행·기본 화면 동작만 회귀 확인한다.

기존 Windows 화면은 **QEMU Cocoa**다. 기준 코드의 [WindowsVMTools.swift](../../macos/Runner/WindowsVMTools.swift)는 `-display cocoa`와 `-netdev user,id=net0`를 사용하며, SSH용 `hostfwd`와 SPICE 서버를 설정하지 않는다. 사용자는 기존 검증에 SSH 로그인과 spicy/remote-viewer 연결이 포함되지 않았다고 확인했다. 따라서 Windows SSH/SPICE는 **미검증이며 앱 접속 구성도 필요한 상태**다. 외부 HTTPS 성공은 게스트로 들어오는 SSH 접속 성공을 뜻하지 않는다.

## 기존 작업과 VM 보존

1. 맥미니에서 호스트 아키텍처·OS, 저장소 branch/HEAD/status, 설치 앱 버전과 실행 중인 Quickgui/QEMU/swtpm을 먼저 확인한다. 이전 기록의 PID가 지금도 유효하다고 가정하지 않는다.
2. 기존 VM의 실행 상태, `installationPending`, 연결된 미디어와 디스크, VM UUID/MAC, TPM/NVRAM 경로를 읽어 기준을 잡는다. 개인정보가 포함될 수 있는 게스트 화면·사용자 파일은 공개 기록에 싣지 않는다.
3. 실행 중인 Windows의 작업을 보존한 뒤 필요할 때 게스트의 정상 종료를 사용한다. 앱 종료나 Cocoa 창 닫기가 VM 종료를 유발할 수 있으므로 먼저 VM 수명 주기 동작을 확인한다. 강제 종료를 정상 종료로 기록하지 않는다.
4. 원본 Windows ISO, VM 디스크, `vm.json`, TPM 상태, UEFI/NVRAM, UUID/MAC, NetKVM 드라이버 미디어를 보존한다. VM 재설치·삭제·초기화, 실행 중 디스크의 다른 QEMU 동시 사용을 하지 않는다. 백업이 필요하면 게스트를 정상 종료한 뒤 디스크와 관련 상태를 함께 보존한다.
5. 기존 작업 폴더의 미커밋 lockfile이나 다른 사용자 변경을 되돌리거나 새 커밋에 섞지 않는다. 작업 시작 상태와 종료 상태를 비교한다.

## 개인 연결 기능 브랜치 준비

기존 M1 작업 폴더를 전환하는 대신 최신 통합 후보에서 별도 worktree를 만든다. 아래 경로·브랜치가 이미 있다면 먼저 용도를 확인하고, 덮어쓰지 않고 새 이름을 선택한다.

```sh
git -C /Users/mac/quickemu/quickgui status --short --branch
git -C /Users/mac/quickemu/quickgui remote -v
git -C /Users/mac/quickemu/quickgui worktree list
git -C /Users/mac/quickemu/quickgui fetch origin
git -C /Users/mac/quickemu/quickgui log -5 --oneline origin/personal/preview
git -C /Users/mac/quickemu/quickgui worktree add -b personal/windows-arm-connections /Users/mac/quickemu/quickgui-windows-connections origin/personal/preview
```

작업 worktree에서는 커밋된 의존성으로 준비·분석·관련 테스트·macOS 빌드를 수행한다. 설치 앱을 바꾸기 전에 새 앱의 경로·소스 SHA·서명과 실제 ARM64 실행을 확인한다. 기존 앱을 보존하고, 같은 VM에 두 앱이 동시에 접근하지 않게 한다.

이 단계는 개인 기능 브랜치에서 진행한다. `main`, `personal/apple-silicon`, 공통 PR 브랜치를 임의로 갱신하거나 upstream PR을 제출하지 않는다. 완료한 변경과 검증 기록은 사용자 fork에 commit/push하고, `personal/preview`로 통합할 범위를 정리한다.

## 구현과 검증 순서

### 1. Windows SSH

- 게스트의 OpenSSH Server 설치·서비스·방화벽 상태를 확인하고 필요한 설정을 마련한다. 이미 사용 중인 인증 설정이나 키를 덮어쓰지 않는다. 인증은 로컬 세션의 안전한 방법을 사용하며 암호·개인 키·토큰을 대화나 문서에 남기지 않는다.
- ARM 네이티브 QEMU 경로에 `127.0.0.1:<사용 가능한 포트> → guest:22` 전달을 구성한다. 호스트의 22번 포트나 Intel의 검증 포트를 그대로 가정하지 않는다. 충돌 시 무관한 프로세스를 종료하지 않고 오류 처리 또는 다른 포트 선택을 제공한다. 모든 인터페이스 바인딩을 기본값으로 삼지 않는다.
- 포트 선택·저장·재실행 후 복원, VM 상태와 실제 전달 주소의 일치, 앱 재실행 후 접속 정보 표시를 연결한다. 현재 Windows 네이티브 bundle은 Quickemu `.pid/.ports` 기반 `VmRepository`와 별도 경로이므로, 파일만 만들어 지원되는 것으로 간주하지 않는다. [WindowsArmVirtualMachine.swift](../../macos/Runner/WindowsArmVirtualMachine.swift), 플랫폼 채널, [native_vm_controls.dart](../../lib/src/widgets/native_vm_controls.dart)의 실제 흐름에 반영한다.
- 설치된 Windows에 실제 SSH로 로그인하고 OS/아키텍처를 확인하는 짧은 명령을 실행한다. 연결을 닫고 다시 인증·명령 실행이 되는지 확인한다. 열린 TCP 포트나 SSH 배너만으로 로그인 PASS를 기록하지 않는다.
- 앱의 접속 버튼이 올바른 VM·포트를 사용하고, VM 종료·재시작 또는 포트 변경 시 오래된 정보로 연결하지 않는지 확인한다. 임시 런타임 전달만 사용했다면 영속 구현과 구분하여 기록한다.

### 2. ARM용 SPICE backend

- 맥미니에서 **실제로 사용할** `qemu-system-aarch64`의 경로·버전·아키텍처·HVF와 SPICE 서버 지원을 확인한다. Intel용 전용 QEMU 실행 파일을 복사해서 ARM backend로 사용하지 않는다.
- `-spice help`의 출력에 옵션 목록이 나오는 경우 exit 1도 가능하다. 종료 코드 하나만으로 미지원이라고 판정하지 않고, 출력 내용과 실제 SPICE listener 생성·클라이언트 연결로 확인한다.
- 미지원이면 ARM용 QEMU/SPICE backend를 별도 경로에 준비한다. 기존에 설치·부팅을 검증한 UEFI Secure Boot, TPM, 머신·CPU, 디스크, ramfb/virtio GPU 및 입력 장치를 유지하면서 호환성을 점검한다. SPICE를 위해 임의의 x64 GPU 드라이버나 전체 게스트 도구를 설치하지 않는다.
- 기존 Cocoa 화면 경로와 UI를 유지한다. SPICE 지원 여부를 감지해 선택한 연결 방식의 실제 상태를 표시하고, backend를 사용할 수 없을 때 Cocoa로 실행할 수 있는 호환 경로를 제공한다. Cocoa 창이 보인 사실을 SPICE 성공으로 처리하지 않는다.
- SPICE는 로컬 Unix 소켓 또는 loopback TCP를 사용한다. 소켓 권한·경로 길이·공백, stale endpoint, 재시작 후 갱신, viewer 종료 후 VM 유지와 재접속을 처리한다. 현재 코드가 UI에서 `spicy`만 찾는지와 사용할 ARM 클라이언트의 실제 인자 지원도 확인한다.

### 3. 설치된 Windows에서 실제 연결 확인

SSH 검증을 먼저 마친 뒤 같은 설치 VM의 SPICE를 확인한다. 변경한 QEMU 인자가 필요하면 게스트를 정상 종료하고 같은 디스크·TPM/NVRAM으로 다시 실행한다.

| 순서 | PASS에 필요한 근거 |
| --- | --- |
| SSH 로그인 | 설치된 Windows의 SSH 인증과 게스트 명령 exit 0, OS/ARM64 확인 |
| SSH 재접속 | 첫 세션 종료 후 새 세션에서 다시 인증·명령 성공 |
| SPICE 화면 | spicy/remote-viewer가 실제 SPICE 채널에 연결되어 설치된 Windows 바탕화면을 수신 |
| SPICE 입력 | 해당 viewer를 통해 안전한 임시 입력 영역에서 키보드와 포인터 동작 확인 |
| SPICE 재접속 | viewer만 종료해 VM이 유지됨을 확인한 뒤 새 viewer로 같은 VM에 재접속·입력 성공 |
| 앱 연동 | Quickgui의 상태·포트/소켓·접속 버튼과 실제 실행 상태 일치, 앱 재실행 후 같은 VM으로 연결 |
| 기존 동작 보존 | 설치 ISO 없이 부팅, 기존 Cocoa 경로와 네트워크, VM identity·TPM/NVRAM·원본 미디어 보존 |

오디오·클립보드·파일 전송·USB·전체 게스트 도구는 이번 SSH/SPICE 화면·입력 통과로 자동 완료 처리하지 않는다. 해당 기능을 추가로 시험하면 별도 결과로 남긴다.

## 결과 기록과 push

구현 전 관찰, 코드 수정, 실제 접속 결과를 구분하여 [M1 실행 기록](M1_VALIDATION.ko.md), [게스트 검증 표](GUEST_VALIDATION.ko.md), 필요하면 이 문서를 갱신한다. 문서에는 사용자가 확인한 결과인지, 도구로 직접 확인한 결과인지 명시한다.

반복 확인이 필요한 결과는 JSON으로도 남긴다. 다음은 **기록 형식 예시이며 실제 성공 결과가 아니다**.

```json
{
  "schema": 1,
  "sourceCommit": "<검증한 전체 SHA>",
  "hostArchitecture": "arm64",
  "guest": "Windows ARM64",
  "sshLogin": {"status": "pending", "evidence": null},
  "sshReconnect": {"status": "pending", "evidence": null},
  "spiceDisplay": {"status": "pending", "evidence": null},
  "spiceInput": {"status": "pending", "evidence": null},
  "spiceReconnect": {"status": "pending", "evidence": null},
  "appReconnect": {"status": "pending", "evidence": null},
  "preservation": {
    "vmIdentityUnchanged": null,
    "existingLockfileUnchanged": null,
    "originalInstallationMediaUnchanged": null
  }
}
```

실제 기록에서는 `status`를 `pass`·`fail`·`blocked` 중 하나로 갱신하고, 확인 시각·backend/client 버전·종료 코드와 근거 로그 참조를 추가한다. 공개할 로그는 필요한 기술 정보로 한정하며 사용자명, 개인 화면 내용, 실제 UUID/MAC, 인증 정보를 포함하지 않는다. UUID/MAC은 로컬 비교의 일치·불일치만 기록한다.

기능별 수정과 검증 문서를 검토 가능한 커밋으로 나누고, 사용자 변경을 제외하여 `origin personal/windows-arm-connections`에 push한다. 원격 SHA와 CI 결과를 확인한 뒤 완료·미완료 및 VM의 최종 실행 상태를 보고한다. 서버 옵션 인식, 단위 테스트, TCP 연결 성공만으로 실사용 검증 전체를 완료 처리하지 않는다.

## 맥미니의 기존 Codex 세션에 붙여넣기

```text
Intel에서 이어온 Quickgui 작업입니다. 사용자 fork의 최신 personal/preview를 fetch하고 docs/maintenance/M1_WINDOWS_CONNECTION_HANDOFF.ko.md와 최신 Intel 검증 결과를 읽어 주세요. 기존 M1 작업 폴더의 미커밋 pubspec.lock과 실행 중인 Windows VM의 작업을 보존하고, 별도 worktree의 personal/windows-arm-connections에서 Windows ARM64 SSH 구성·실제 로그인·재접속 → ARM SPICE backend 구성·설치된 Windows 화면·입력·viewer 재접속 → 앱 연동 순서로 구현하고 검증해 주세요. 기존 Cocoa UI·VM 디스크·TPM/NVRAM·UUID/MAC·원본 ISO를 유지하고 재설치·삭제하지 마세요. Windows 기본 실사용과 M1 macOS ARM 바탕화면·재부팅·SSH는 완료했으므로 반복하지 마세요. 검증 근거를 Markdown/JSON으로 기록하고 kimdongup/quickgui의 개인 작업 브랜치에 commit/push까지 진행해 주세요.
```
