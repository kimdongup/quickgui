# Apple Silicon macOS VM 생성·설치

2026-09-09. `personal/apple-silicon`의 개인 기능이다. 기존 Quickemu `.conf` VM과 분리해
Apple Virtualization.framework로 IPSW를 설치한다. Flutter 3.47.2와 기존 lockfile을 유지한다.

1. Manager의 **Create Apple Silicon VM**을 누른다. 또는 macOS ARM 다운로드 화면에서
   **Use an existing IPSW**, 다운로드 완료 후 **Create Apple Silicon VM**을 누른다.
2. **Choose IPSW**에서 내려받은 파일을 선택한다. Apple API가 호환성과 최소 CPU·메모리를 검사한다.
3. 새 이름과 자원을 확인하고 **Create and install**을 누른다. 기본값은 CPU 2개, 메모리 4GiB,
   디스크 64GiB이며 이미지 최소값에 맞춘다. 호스트 메모리 2GiB를 남긴다.
4. 설치 진행률은 생성 화면과 Manager에서 확인할 수 있다. 설치 중 Quickgui를 종료하지 않는다.
5. 완료되면 **Run**을 눌러 별도 VM 화면에서 macOS 최초 설정을 진행한다.
   이후 Manager의 **Run**은 저장된 디스크로 부팅하며 IPSW를 요구하지 않는다.

검증 VM은 `/Users/mac/quickemu/macOS-Apple-Silicon.quickgui-macvm`이다.
Manager 작업 폴더를 `/Users/mac/quickemu`로 선택하면 나타난다. 최초 언어 선택 화면까지 직접 확인했으며,
2026-09-10 사용자가 바탕화면·재부팅·SSH 검증도 완료했다고 확인했다. 사용자 계정·Apple ID·암호는 기록하지 않는다.

VM 화면을 닫아도 VM은 계속 실행된다. **Open VM display**로 다시 연다.
**Shut down**은 게스트에 종료를 요청한다. 응답하지 않으면 확인 후 **Force stop**을 사용할 수 있다.
실행·설치 중 앱 종료는 차단하며 Manager에서 먼저 중지하도록 안내한다.

`<workspace>/<name>.quickgui-macvm`에는 `vm.json`, `disk.img`, `hardware-model`,
`machine-identifier`, `auxiliary-storage`, `vm.lock`이 들어간다. 식별 정보와 네트워크 MAC을
다시 생성하지 않으며, IPSW 원본을 변경하거나 복사하지 않는다. 디스크는 사용량에 따라 커지는
sparse 파일이다. 설치 시작에는 실제 여유 공간 32GiB 이상이 필요하고 게스트 사용량에 따라 추가 공간이 필요하다.

기존 폴더는 비어 있어도 덮어쓰지 않는다. 다른 프로세스의 같은 VM 실행을 파일 잠금으로 막는다.
실패·취소·앱 비정상 종료로 중단된 설치는 Run을 허용하지 않는다. 해당 폴더를 보존하고 새 이름으로
VM을 만들어 다시 설치한다. 실패·취소·중단된 VM은 Manager에서 삭제할 수 있다.
VM과 설치 파일 삭제 방법은 [STORAGE_MANAGEMENT.ko.md](STORAGE_MANAGEMENT.ko.md)를 따른다.
기존 VM 재설치·스냅샷·저장 상태 복원은 이번 기능에 포함하지 않는다.
한 Quickgui 프로세스에서 Apple VM은 한 대씩 실행한다.

참조: [Apple macOS VM 예제](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon),
설치된 Xcode SDK의 `VZMacOSInstaller`, `VZMacPlatformConfiguration`, `VZVirtualMachineView` 헤더.
실제 결과와 재현 도구는 [M1 검증 기록](M1_VALIDATION.ko.md)을 따른다.
