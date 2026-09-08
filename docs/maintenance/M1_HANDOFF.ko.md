# M1 맥미니 소스 이전과 검토

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

게스트 검증 순서는 [GUEST_VALIDATION.ko.md](GUEST_VALIDATION.ko.md)의 **Intel에서 macOS x64 → Intel에서 Windows ARM64 실험 → M1에서 macOS ARM**을 유지한다. 맥미니 개발 환경·소스·UI 준비는 지금 할 수 있지만, 3단계 게스트 설치·실행은 앞 단계 결과를 확정한 뒤 진행한다. Intel macOS 설치 완료는 사용자 보고를 기다리는 상태다.

M1 단계에서는 [Apple의 macOS 가상 머신 예제](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)를 기준으로 Virtualization.framework와 Apple restore image(`.ipsw`)를 사용하는 backend부터 검증한다. 호스트에서 지원하는 이미지를 확인하고 별도 ARM VM을 만든다. 설치·바탕화면·재부팅·SSH를 각각 기록한다. 이 backend의 화면 연결 방식은 QEMU/SPICE와 별도로 설계·검증한다.

Intel에서 만든 macOS/Windows x64 VM 디스크는 ARM 게스트 설치를 대신하지 않는다. `/Users/mac/quickemu/validation/spice-backend`의 QEMU/SPICE 바이너리와 `tool/spice`의 x86 부팅 검사는 Intel에서 검증한 것으로 M1용 실행 절차가 아니다. 빌드 기록은 [MACOS_SPICE_BACKEND.ko.md](MACOS_SPICE_BACKEND.ko.md)에 보존되어 있다.

## 작업 이어받기와 push

맥미니에서 새 작업을 시작할 때 다음 내용을 전달하면 된다.

> `docs/maintenance/M1_HANDOFF.ko.md`, `STATUS.ko.md`, `GUEST_VALIDATION.ko.md`, `UPSTREAM_PRS.md`를 읽고 현재 브랜치와 M1 환경부터 확인해 주세요. 개인 기능과 공통 PR 수정을 분리하고 기존 UI를 유지합니다. 지금은 환경·빌드·UI 검토를 진행하고, macOS ARM 게스트 검증은 Intel macOS와 Windows ARM64 실험 결과를 확정한 뒤 시작합니다. Intel 게스트 설치 완료 및 M1 실사용 성공을 추정하지 말고 실제 결과를 기록해 주세요.

소스의 검증 문서가 다른 컴퓨터에서 작업을 이어받는 기준이다. 로컬 VM 디스크·미추적 파일·앱 설정은 clone으로 이전되지 않는다. 최초 설계 문서와 실행 상태가 다르면 [STATUS.ko.md](STATUS.ko.md)의 기록을 기준으로 한다.

맥미니의 변경은 파일별 diff를 검토하고 해당 검증을 마친 뒤 Conventional Commit으로 커밋한다. 자신의 GitHub 계정에 push 인증이 준비되어 있으면 다음 명령으로 M1 작업 브랜치를 fork에 올린다.

```sh
git push -u origin personal/apple-silicon
```

그 뒤 Intel 작업 폴더에서는 브랜치를 바꾸지 않고 `git fetch origin`으로 M1 커밋을 확인할 수 있다. 양쪽 변경을 검토한 뒤 개인 통합 후보에 반영한다. 검증 전 `main` 승격이나 upstream PR 제출은 하지 않는다.
