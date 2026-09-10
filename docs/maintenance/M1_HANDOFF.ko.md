# M1 맥미니 소스 이전과 검토

2026-09-10 후속: 아래는 이전 당시의 절차와 상태를 보존한 기록이다. 현재 M1의
Apple Silicon/Windows ARM64 VM 구현과 Windows 네트워크 수정은 `personal/apple-silicon`에 있다.
새로 이어받을 때는 [검토 완료 결과](M1_REVIEW_RESULT.ko.md), [현재 상태](STATUS.ko.md),
[실제 검증 기록](M1_VALIDATION.ko.md)을 먼저 확인한다.

2026-09-08. 사용자가 보유한 M1 맥미니를 Apple Silicon 검증 호스트로 사용한다. 이 문서는 이전 절차이며, M1에서 실행한 결과를 의미하지 않는다.

## 가져올 소스와 브랜치

수정본은 `kimdongup/quickgui`의 **`personal/preview`**에 있다. `main`은 아직 upstream 기준이므로 브랜치를 지정해서 받는다. 문서 작성 기준 앱 코드는 `09fce12`, SPICE 재현 도구와 기록은 `db54e35`에 포함되어 있다. 이후 문서 커밋도 함께 가져온다.

맥미니의 Terminal에서 실행한다. 아래는 `~/Developer/quickgui`가 아직 없는 경우의 명령이다. 기존 폴더가 있으면 덮어쓰지 말고 먼저 그 폴더의 `git status`와 remote를 확인한다.

```sh
mkdir -p ~/Developer
cd ~/Developer
git clone --branch personal/preview https://github.com/kimdongup/quickgui.git
cd quickgui
git switch -c personal/apple-silicon
git remote add upstream https://github.com/quickemu-project/quickgui.git
git status --short --branch
git log -1 --oneline
```

`personal/apple-silicon`은 위 명령으로 맥미니에서 새로 만드는 작업 브랜치다. 이 문서를 작성한 Intel 호스트에서는 만들거나 push하지 않았다. Git으로 받은 소스·테스트·검증 기록을 기준으로 이어서 작업한다.

| 브랜치 | 역할 |
| --- | --- |
| `personal/preview` | 현재 개인 기능 통합 후보와 Intel 검증 기록 |
| `personal/apple-silicon` | M1 환경 확인, Apple Silicon 관련 개인 구현·검증 |
| `integration/stabilization` | 개인 기능을 제외한 공통 PR 후보, 현재 `ae57d7d` |
| `pr/*` | upstream 제출 단위별 수정 |

공통 코드에서도 재현되는 M1 오류는 해당 공통 기준에서 작은 `pr/*` 수정으로 분리한 뒤 개인 브랜치에 반영한다. 개인 브랜치 전체를 upstream PR에 넣지 않는다. 공통 후보를 별도로 검토할 때는 다음 worktree를 사용할 수 있다.

```sh
git worktree add -b review/m1-common ../quickgui-pr origin/integration/stabilization
```

## 맥미니 개발 환경

먼저 호스트 정보를 확인한다.

```sh
uname -m
sw_vers
sysctl -n hw.memsize
df -h "$HOME"
xcodebuild -version
```

`uname -m`은 `arm64`여야 한다. M1인데 `x86_64`가 나오면 Terminal의 Rosetta 실행 설정부터 확인하고 ARM 환경에서 다시 시작한다. RAM·저장 공간과 설치 가능한 macOS/Xcode 버전을 확인한 뒤 게스트 자원을 정한다.

필요한 개발 도구는 다음과 같다.

- **Flutter 3.47.2 macOS ARM64 SDK**: [공식 SDK archive](https://docs.flutter.dev/install/archive)에서 버전과 아키텍처를 선택하고 [수동 설치 안내](https://docs.flutter.dev/install/manual)에 따라 PATH에 추가한다. 저장소의 `pubspec.yaml` 및 lockfile과 맞춘다.
- **Xcode와 CocoaPods**: [Flutter macOS 설정 안내](https://docs.flutter.dev/platform-integration/macos/setup)를 따른다. Command Line Tools만 설치한 상태로는 macOS 앱 빌드 준비가 끝나지 않는다. 현재 프로젝트의 native plugin에는 CocoaPods가 필요하다.
- **ARM Homebrew**: backend 설치 시 사용한다. [공식 설치 안내](https://docs.brew.sh/Installation)의 Apple Silicon 기본 prefix는 `/opt/homebrew`다. Intel 호스트의 `/usr/local` 도구를 복사하지 않는다.

설치 후 확인한다. Flutter가 제공하는 Dart를 사용하며 의존성을 임의로 업그레이드하지 않는다.

```sh
flutter --version
flutter doctor -v
pod --version
flutter devices
```

macOS 개발에 필요한 Xcode·device 오류를 먼저 해결한다. Android/iOS 등 다른 플랫폼의 개발 준비는 이번 macOS 앱 검토와 별개다.

## 앱 빌드와 첫 UI 검토

`~/Developer/quickgui`에서 아래 명령을 하나씩 실행하고 실패한 단계가 있으면 먼저 해결한다.

```sh
flutter config --enable-macos-desktop
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d macos
```

마지막 명령은 앱을 실행한다. Terminal의 `q`로 종료할 수 있다. 새 환경에서 backend가 없을 때 복구 안내가 표시되는 것도 확인 대상이다. backend 미설치 상태를 정상 VM 기능 전체의 검증으로 기록하지 않는다.

release 앱이 필요하면 다음을 실행한다.

```sh
flutter build macos --release
open build/macos/Build/Products/Release/quickgui.app
```

`build/`, `.dart_tool/`, `macos/Pods/`는 맥미니에서 다시 생성한다. Intel 컴퓨터의 빌드 캐시나 Flutter SDK를 폴더째 옮길 필요가 없다. 앱 설정은 Git에 포함되지 않으므로 backend 경로와 VM 작업 폴더는 맥미니에서 지정한다. 공통 후보와 개인 후보는 현재 앱 ID/설정을 공유하므로 번갈아 검토할 때 저장된 설정을 함께 확인한다.

일반 Quickemu/Quickget 탐색과 목록까지 확인하려면 ARM Homebrew를 준비한 뒤 [Quickemu 공식 tap](https://github.com/quickemu-project/homebrew-quickemu)의 설치 명령을 사용한다.

```sh
brew tap quickemu-project/quickemu
brew install quickemu
command -v quickemu quickget
quickemu --version
quickget --version
```

설치 시점의 backend 버전은 Intel에서 확인한 4.9.9와 다를 수 있으므로 기록한다. 현재 앱은 `/opt/homebrew/bin`을 탐색하며 개인 설정에서 executable 경로도 지정할 수 있다. VM 작업 폴더는 소스 밖의 새 폴더(예: `~/Quickemu-ARM`)로 정한다. 기본 앱 테스트만 실행하며 실제 VM/다운로드 opt-in 검사는 아래 순서에 맞춰 별도로 시작한다.

첫 검토에서는 홈·다운로더·Manager·설정, 도구 탐색과 오류 복구, 창 크기와 키보드/트랙패드 조작, 종료 후 재실행을 확인한다. 기존 UI 구성을 유지한다. 결과에 호스트 macOS/RAM, `git rev-parse HEAD`, Flutter/backend 버전과 실제 실행한 명령을 남긴다.

## ARM 게스트 검증의 경계와 순서

**소스를 받거나 ARM64 앱을 빌드했다고 macOS ARM 게스트 지원이 완성되는 것은 아니다.** 현재 앱에는 Apple Virtualization/IPSW backend가 구현되어 있지 않다. ARM 메뉴도 실제 backend 동작을 확인한 뒤 연결한다.

게스트 검증은 [GUEST_VALIDATION.ko.md](GUEST_VALIDATION.ko.md)의 **Intel에서 macOS x64 → M1에서 Windows ARM64 실험 → M1에서 macOS ARM** 순서로 진행하는 것을 권장한다. M1 장비를 보유한 것이 확인되어 Windows ARM64도 하드웨어 가속이 가능한 M1을 주 검증 호스트로 제안한다. Intel에서의 ARM64 TCG 실행은 추가 호환성 실험으로 남긴다. 맥미니 개발 환경·소스·UI 준비는 지금 할 수 있지만, 각 게스트 설치·실행은 앞 단계 결과를 확정한 뒤 진행한다. Intel macOS의 최신 진행 상태는 위 검증 문서에서 확인한다.

Windows ARM64는 QEMU/HVF, ARM64 UEFI와 공식 ISO·게스트 드라이버를 준비하는 경로다. macOS ARM용 Apple Virtualization backend가 완성될 때까지 Windows ARM 검증을 기다릴 필요는 없다. 다만 현재 앱의 ARM 설치 흐름과 M1의 QEMU/SPICE 구성은 아직 검증되지 않았다.

macOS ARM 단계에서는 [Apple의 macOS 가상 머신 예제](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)를 기준으로 Virtualization.framework와 Apple restore image(`.ipsw`)를 사용하는 backend부터 검증한다. 호스트에서 지원하는 이미지를 확인하고 별도 ARM VM을 만든다. 설치·바탕화면·재부팅·SSH를 각각 기록한다. 이 backend의 화면 연결 방식은 QEMU/SPICE와 별도로 설계·검증한다.

Intel에서 만든 macOS/Windows x64 VM 디스크는 ARM 게스트 설치를 대신하지 않는다. `/Users/mac/quickemu/validation/spice-backend`의 QEMU/SPICE 바이너리와 `tool/spice`의 x86 부팅 검사는 Intel에서 검증한 것으로 M1용 실행 절차가 아니다. 빌드 기록은 [MACOS_SPICE_BACKEND.ko.md](MACOS_SPICE_BACKEND.ko.md)에 보존되어 있다.

## 대화 기록과 실행 호스트

**Git clone은 소스·커밋·검증 문서를 전달하지만 Codex 대화 자체를 전달하지 않는다.** 맥미니에서 새 대화를 시작할 때 이전 대화를 모두 알고 있다고 가정하지 않는다. 같은 저장소의 미래 대화에 전달할 지침을 문서로 보존하는 방식은 [OpenAI 공식 프로젝트 안내](https://learn.chatgpt.com/docs/projects)에서도 설명한다.

기존 대화를 이어서 옮기려면 [OpenAI 공식 원격 연결 안내의 Hand off](https://learn.chatgpt.com/docs/remote-connections#hand-off-a-chat-between-hosts)를 확인한다. 맥미니를 연결하고 양쪽에 같은 Git 저장소의 프로젝트를 등록한 뒤, 대화 하단 실행 위치에서 대상 호스트를 선택하고 목적지·브랜치를 검토하여 **Hand off**한다. 공식 문서에 따르면 목적지 worktree로 대화와 Git 상태가 전달된다. 실제 앱에서 해당 연결·메뉴를 사용할 수 있는지는 확인이 필요하며, 이 문서 작성 시에는 설정하거나 이전하지 않았다.

기존 Intel 컴퓨터에 원격 접속하여 대화를 조작하는 것과, 실행 호스트를 M1으로 옮기는 것을 구분한다. M1 검증 전에 실행 위치·`uname -m`·작업 폴더·브랜치를 확인한다. Hand off는 실행 중 응답을 중단할 수 있으므로 현재 Intel 설치 관련 작업의 상태를 먼저 정리한다. 게스트 디스크·실행 중 VM·Terminal 프로세스가 함께 이전된다고 가정하지 않는다.

## 새 대화로 작업 이어받기와 push

맥미니에서 새 작업을 시작할 때 다음 내용을 전달하면 된다.

> `docs/maintenance/M1_HANDOFF.ko.md`, `STATUS.ko.md`, `GUEST_VALIDATION.ko.md`, `UPSTREAM_PRS.md`를 읽고 현재 브랜치와 M1 환경부터 확인해 주세요. 개인 기능과 공통 PR 수정을 분리하고 기존 UI를 유지합니다. 지금은 환경·빌드·UI 검토를 진행합니다. 게스트 검증의 권장 순서는 Intel macOS x64 → M1 Windows ARM64 → M1 macOS ARM이며 앞 단계 결과 확정 후 다음 단계로 넘어갑니다. Intel의 Windows ARM64 TCG 실행은 추가 실험입니다. Intel 게스트 설치 완료 및 M1 실사용 성공을 추정하지 말고 실제 결과를 기록해 주세요.

소스의 검증 문서가 다른 컴퓨터에서 작업을 이어받는 기준이다. 로컬 VM 디스크·미추적 파일·앱 설정은 clone으로 이전되지 않는다. 최초 설계 문서와 실행 상태가 다르면 [STATUS.ko.md](STATUS.ko.md)의 기록을 기준으로 한다.

양쪽 대화 사이에 이후 메시지가 자동 전달된다고 가정하지 않는다. Intel 설치 결과처럼 다른 호스트의 새 결과가 필요할 때는 그 호스트에서 기록·push한 커밋을 가져온다. M1 작업 브랜치를 유지한 채 다음처럼 Intel 측 최신 기록을 읽을 수 있다.

```sh
git fetch origin
git show origin/personal/preview:docs/maintenance/GUEST_VALIDATION.ko.md
```

M1 대화는 시작할 때 문서에서 확인한 완료 범위·미검증 항목·다음 작업을 짧게 정리하고 환경을 확인한다. M1 결과는 `docs/maintenance/M1_VALIDATION.ko.md`에 실행 호스트·검증 SHA·명령·성공/실패·남은 작업과 함께 기록하는 것을 권장한다. 이 파일은 실제 검토를 시작할 때 만들며, 현재 M1 검증을 수행한 기록은 없다. 결과와 관련 코드를 같은 M1 작업 브랜치에 커밋·push한 뒤 커밋 SHA를 Intel 측 대화에 전달하면, 그 변경을 fetch하여 검토하고 통합할 수 있다.

맥미니의 변경은 파일별 diff를 검토하고 해당 검증을 마친 뒤 Conventional Commit으로 커밋한다. 자신의 GitHub 계정에 push 인증이 준비되어 있으면 다음 명령으로 M1 작업 브랜치를 fork에 올린다.

```sh
git push -u origin personal/apple-silicon
```

그 뒤 Intel 작업 폴더에서는 브랜치를 바꾸지 않고 `git fetch origin`으로 M1 커밋을 확인할 수 있다. 양쪽 변경을 검토한 뒤 개인 통합 후보에 반영한다. 검증 전 `main` 승격이나 upstream PR 제출은 하지 않는다.
