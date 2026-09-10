# Windows ARM64 VM 생성·설치

2026-09-09, `personal/apple-silicon`의 개인 기능이다. macOS Apple Silicon의 IPSW 경로와
Windows ARM64의 ISO 경로는 OS 선택 화면과 Manager에서 구분된다.

## 이 M1에서 사용하기

최종 빌드는 `/Users/mac/quickemu/quickgui/dist/arm-vms/quickgui.app`이다.
기존 Quickgui의 VM을 중지하고 앱을 종료한 뒤 이 빌드를 실행한다.
네이티브 코드가 추가되어 기존 `flutter run`의 hot reload만으로는 반영되지 않는다.
파일 선택 시 `Either the Read-Only or Read-Write entitlement is required for this action.`이
표시되는 이전 빌드는 `1942c4e` 이상으로 다시 빌드하고 완전히 재실행한다. 위 최종 앱에는 수정이 포함되어 있다.

1. Manager의 **Windows — ARM64 → Create Windows ARM64 VM**을 선택한다.
2. **Choose ARM64 ISO**에서 `/Users/mac/Downloads/Win11_25H2_Korean_Arm64_v2.iso`를 선택한다.
   다운로더의 Windows ARM64 화면에서도 기존 ISO 사용 또는 다운로드 완료 후 생성으로 이동할 수 있다.
3. 이름과 자원을 정하고 **Create and install**을 누른다. 이 8GiB M1의 기본값은 CPU 2개,
   RAM 4GiB, 가상 디스크 64GiB다. 작업 폴더에 `<이름>.quickgui-winarm`이 생긴다.
4. VM 창에서 설치 미디어 부팅을 위한 키 입력 요청이 나오면 키를 누르고 Windows 설치를 진행한다.
   제품 키·에디션·계정은 사용자가 선택한다. 원본 ISO는 읽기 전용으로 연결한다.
   **네트워크에 연결** 화면에서 어댑터가 없으면 아래 네트워크 드라이버 설치 절차를 따른다.
5. Windows 바탕화면까지 설치한 뒤 게스트를 종료한다. Manager의 **Installation completed**에서
   완료를 확인하면 다음 Run부터 ISO를 제외하고 디스크로 부팅한다. 설치 중에는 **Resume installation**을 쓴다.

가상 디스크는 사용량에 따라 커지며, 새 설치 시작에는 호스트 여유 공간 32GiB 이상을 요구한다.
실사용과 업데이트에는 더 많은 공간이 필요하다. 2026-09-09 최초 검사에서는 여유 공간이
약 22–26GiB여서 전체 설치를 시작하지 않았다. 이후 사용자가 초기 설정·바탕화면·입력·HTTPS와
정상 종료·설치 완료 후 부팅을 직접 검토해 정상이라고 확인했다. 2026-09-10 후속 검사에서는
Quickgui를 완전히 종료·재실행한 뒤 같은 VM의 설치 ISO 없는 실행과 외부 TCP 연결도 확인했다.
새 VM을 만들 때는 그 시점의 여유 공간을 다시 확인한다.

**Show display**, 정상 종료 요청, 확인 후 강제 중지를 제공한다. Windows VM의 QEMU 창을 닫으면
VM이 종료된다. Apple VM의 창 닫기 동작과 다르다. 같은 앱에서는 Apple/Windows ARM VM을 하나씩 실행한다.
Quickgui를 종료하기 전에 게스트를 종료한다. 앱이 비정상 종료된 경우 기존 QEMU 창을 먼저 닫아야 한다.

## 다른 M1/M2/M3/M4 호스트의 준비

Flutter 3.47.2와 기존 lockfile을 유지한다. VM 실행에는 ARM Homebrew의 QEMU와 swtpm이 필요하다.
이미 설치했다면 다시 설치하거나 임의로 업그레이드하지 않는다.

```sh
/opt/homebrew/bin/brew install qemu swtpm
python3 tool/prepare_windows_arm_firmware.py
python3 tool/prepare_windows_arm_network.py
```

펌웨어 준비 도구는 [UTM의 QEMU 저장소](https://github.com/utmapp/qemu/tree/b44153a4b6aabf86edebf92199b14aec26e15d59/pc-bios)의
ARM64 Secure Boot 펌웨어를 고정 커밋과 SHA256으로 확인한다. UTM 앱은 설치하지 않는다.
코드와 Microsoft 키가 등록된 변수 템플릿, 저작권 안내만 다음 사용자 폴더에 준비한다.

```text
~/Library/Application Support/Quickgui/Firmware/utm-b44153a4/
```

변수 템플릿의 QCOW2 포맷을 raw로 변환하며 등록된 키와 내용을 유지한다.
앱은 준비된 파일의 SHA256도 확인한다. 각 VM은 펌웨어·NVRAM·TPM을 독립적으로 복사하고
이후 해당 복사본을 유지한다. 준비 도구를 다시 실행해도 기존 VM의 NVRAM이나 디스크를 바꾸지 않는다.

## 네트워크 어댑터가 없을 때

2026-09-10 후속에서 기존 `usb-net`을 ARM64 NetKVM 드라이버가 지원하는
`virtio-net-pci`로 변경했다. 호스트의 연결을 이용하는 NAT 방식이며 기존 VM의 MAC 주소는 유지한다.
Windows에서는 **Ethernet**으로 표시된다. Wi-Fi 목록에서 호스트의 공유기를 선택하는 방식이 아니다.

1. 위 네트워크 준비 도구를 이 Mac에서 한 번 실행한다. 이 M1에는 이미 준비했다.
2. 이전 앱으로 실행한 VM은 정상 종료하고 수정한 Quickgui를 실행한 뒤 **Resume installation**을 누른다.
   기존 VM 폴더와 디스크를 그대로 사용한다. Windows 설치 미디어로 다시 부팅하라는 키 요청에는 입력하지 않는다.
3. Windows **네트워크에 연결 → 드라이버 설치**를 누른다.
4. **QGNET** CD의 **NetKVM** 폴더를 선택하고 드라이버를 설치한다.
   드라이브 문자는 시스템마다 다르다. 설치 후 Ethernet 연결을 확인하고 다음으로 진행한다.
5. 이미 바탕화면에 도달했다면 장치 관리자에서 Ethernet Controller의 드라이버 업데이트에 같은 폴더를 지정한다.

명령줄이 필요한 경우 Windows의 관리자 명령 프롬프트에서 아래처럼 실행한다.
`D:`는 실제 QGNET 드라이브 문자로 바꾼다. 드라이버 서명 검사나 Secure Boot를 끄지 않는다.

```bat
pnputil /add-driver D:\NetKVM\netkvm.inf /install
```

Manager와 VM 생성 화면의 **Network setup**에서도 설치 방법을 볼 수 있다.
준비된 드라이버 CD는 설치 후 일반 부팅에도 별도 읽기 전용 광학 드라이브로 연결한다.
이미 드라이버가 설치된 VM은 호스트의 드라이버 CD가 없어도 부팅할 수 있다.

준비 도구는 [UTM 공식 Windows 게스트 지원 안내](https://docs.getutm.app/guest-support/windows/)가
제공하는 [0.1.271 배포 ISO](https://github.com/utmapp/qemu/releases/tag/v10.0.2-utm)의 SHA256
`65b6a69b392ee01dd314c10f3dad9ebbf9c4160be43f5f0dd6bb715944d9095b`를 확인한다.
Windows 11 ARM64용 NetKVM의 INF/CAT/SYS 및 INF가 참조하는 실행 파일, 라이선스만 CD로 만든다.
Windows 자동 설치 응답 파일이나 GPU/SPICE 설치 프로그램은 포함하지 않는다.
저장 위치는 `~/Library/Application Support/Quickgui/Drivers/netkvm-0.1.271-arm64/`이며,
앱은 생성 이미지의 manifest·체크섬을 검사하고 VM이 사용할 때 삭제 잠금을 유지한다.

## 구현·검증 범위

QEMU/HVF의 ARM `virt-9.2`, host CPU, ARM TPM 2.0, NVMe 저장소, USB 광학 드라이브와
Cocoa 화면을 사용한다. 이 호스트의 검증에서 RAMFB 단독과 VirtIO GPU 단독 부팅은 실패했고,
두 장치를 함께 연결한 구성에서 설치 화면에 도달했다. 기본 창은 RAMFB 화면이다.
설치 ISO는 ARM64 EFI 프로그램과 Windows 설치 파일을 확인한다.
공백·쉼표·한국어 경로는 shell 평가 없이 인자로 전달한다. Quickemu의 x64 옵션이나 Intel 호스트 도구를 가져오지 않는다.

중복 실행은 파일 잠금과 실행 중 프로세스 기록으로 방지한다. 앱이 직접 시작한 프로세스만 종료한다.
VM 폴더의 `last-run.log`에 QEMU/TPM 오류와 펌웨어 콘솔을 기록한다.

Manager의 **Delete VM**, **Installation files**에서 VM과 설치 ISO를 각각 삭제할 수 있다.
설치 중이거나 다른 VM이 필요한 파일은 보호한다. 확인 절차와 범위는
[STORAGE_MANAGEMENT.ko.md](STORAGE_MANAGEMENT.ko.md)를 따른다.

실제 통과한 범위와 실패 후 수정 내역은 [M1_VALIDATION.ko.md](M1_VALIDATION.ko.md)를 따른다.
2026-09-10 후속에서 초기 설정·바탕화면·입력·HTTPS와 정상 종료·설치 완료 후 부팅은
사용자 확인 완료로 기록했다. 앱 재실행 후 같은 VM의 설치 ISO 없는 실행과 외부 TCP 통신은
직접 확인했다. 오디오·전체 게스트 도구·SSH/SPICE는 아직 완료로 표시하지 않는다.
