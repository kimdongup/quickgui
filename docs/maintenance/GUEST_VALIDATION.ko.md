# 게스트 설치 경험과 순차 검증

2026-09-08. 개인 후보 `personal/windows-installation`에서 관리한다. 기존 Windows 디스크·설정·설치 중 표시 파일은 읽기만 했으며, 이 작업에서 재설치하거나 표시를 해제하지 않았다.

## Windows 11 x64 경험을 앱에 반영

사용자가 `/Users/mac/quickemu`의 Windows 11 x64 설치 진행 성공을 확인했다. 9월 6일 설치 기록은 첫 설치 단계와 두 번째 단계 진행까지 기록하고 있다. 바탕화면·재부팅·SSH 로그인은 별도 확인 대상으로 남긴다. 오래된 `installation-in-progress` 파일만으로 사용자가 보고한 진행 상황을 부정하거나, 설치가 끝났다고 자동 판정하지 않는다.

| 관찰 | 앱에 반영한 동작 |
| --- | --- |
| Intel Mac에서 HVF + host CPU 설치가 중단됐고 Nehalem + HPET 조합으로 진행 | 중지된 Windows x64 VM의 편집 화면에 선택형 **Windows x64 on Intel Mac** 프로필. 변경 내용을 먼저 표시하고 **Use in editor → Save**로 저장 |
| SATA/Intel NIC 구성으로 설치 | `guest_os="windows-server"`는 Quickemu의 하드웨어 선택이며 Windows 11 Pro라는 설치 제품과 구분해 설명 |
| HVF + TPM 사용 시 EFI 정체 관찰 | 프로필은 TPM·Secure Boot를 끄는 실험 설정임을 표시. 전체 Windows 기본값으로 적용하지 않음. 요구사항 우회·인증 키·무인 응답 파일은 생성하거나 포함하지 않음 |
| 디스크 크기로 설치 완료를 추정하여 설치 중 ISO가 빠짐 | GUI는 디스크 크기·QEMU 실행 성공을 설치 완료로 취급하지 않음. 기존 `installation-in-progress`가 있으면 일반 Run을 차단하고 설치 완료 확인 절차 표시 |
| 설치 전용 실행기는 무인 설치 ISO를 연결하고 디스크를 다시 분할 | 일반 VM 명령에서 상속된 `WINDOWS11_INSTALL`을 제거. 설치 실행기를 자동 호출하거나 무인 설치 ISO를 다시 연결하지 않음 |
| 복잡한 Bash config에 설치 전용 조건문 포함 | 프로필 자동 적용은 단순한 리터럴 설정에만 허용. 조건문·중복 할당·사용자 `extra_args`는 자동 변환 거부. 기존 설정은 일반 편집으로 유지 |

프로필: x86_64, EFI, 4 GB RAM, 2 vCPU, Cocoa, GL off, audio off, TPM/Secure Boot off, `extra_args="-machine accel=hvf,hpet=on -cpu Nehalem -smp 2,sockets=1,cores=2,threads=1"`. 설치 ISO 경로, 드라이버 ISO 경로, 디스크 경로·크기와 주석을 보존한다. ARM 호스트·게스트에는 제공하지 않는다.

설치 중인 VM에서 Run을 누르면 설치 완료 확인 대화상자가 열린다. 게스트 바탕화면 도달, 게스트 종료, 설치 디스크로 부팅할 설정을 확인한 뒤 **Installation completed**를 선택하면 표시 파일만 `.quickgui-installation-completed-*` 폴더로 보관한다. 자동 부팅하지 않으며 이후 Run을 다시 누른다. 실행 중/불명 상태, symlink 표시 파일, 다른 VM과 공유하는 상태 디렉터리의 확인 처리는 거부한다.

아직 설치 중이면 Cancel로 닫고 해당 VM의 기존 설치 실행 절차를 사용한다. 현재 Windows의 설치 실행기는 재분할을 수행하므로, 설치가 진행된 디스크에 재실행하기 전에 반드시 해당 설치 기록을 확인해야 한다. 앱이 모든 Quickemu 버전의 설치 재개와 ISO 연결을 자동 관리하는 단계는 아니다.

## 검증 순서와 통과 기준

| 순서 | 대상 | 진행 조건 및 통과 기준 | 현재 상태 |
| --- | --- | --- | --- |
| 기준 사례 | Intel macOS → Windows 11 x64 | 사용자 설치 경험을 보존하고 설정·설치 모드 처리에 반영 | 설치 진행 성공: 사용자 보고. 바탕화면/재부팅/SSH/SPICE는 별도 확인 |
| 1 | Intel macOS → macOS Intel x64 | Apple 이미지 검증 → 복구 부팅 → 전용 가상 디스크 설치 → 바탕화면 → 재부팅 → Remote Login/SSH → 앱 재접속 | Sequoia 다운로드와 chunklist 검사 통과. CPU 감지 오류 수정 사본으로 OpenCore와 macOS 커널 부팅 확인. 설치 완료는 미확인 |
| 2 | Intel macOS → Windows ARM64 실험 | 1단계 결과를 확정한 뒤 진행. ARM64 UEFI/설치 ISO/드라이버를 분리하고 TCG 부팅·설치·재부팅·SSH 검증. 성능 한계 기록 | 대기. 다운로드·VM 실행 미착수 |
| 3 | Apple Silicon 호스트 → macOS ARM | 2단계 결과 확정 후 실제 Apple Silicon 장비 확보. Apple Virtualization/IPSW backend로 설치·재부팅·SSH 검증 | 대기. ARM Mac과 별도 backend 필요 |

설치 완료와 연결 기능은 각각 기록한다. 현재 Homebrew QEMU 11.1.1은 `-spice`를 지원하지 않아 이 Intel Mac의 SPICE 서버 검증은 **환경상 차단**이다. `spicy` 클라이언트가 설치돼 있어도 서버 지원을 대체하지 않는다. Cocoa 화면을 SPICE 통과로 기록하지 않는다. 이 제약은 설치·SSH 결과와 분리하며, SPICE 지원 QEMU를 준비한 뒤 별도 검증한다.

기존 macOS/Windows 항목은 x64를 기준으로 유지한다. ARM 메뉴는 실제 backend와 함께 확장한다. Quickget 4.9.9는 Windows/macOS용 ARM 다운로드 경로를 제공하지 않으므로 메뉴 이름과 `--arch arm64` 인자만 추가해 지원을 표시하지 않는다. Windows ARM은 실험 항목, macOS ARM은 Apple Silicon 호스트와 Apple Virtualization backend가 필요한 항목으로 설계한다.

## macOS Intel 첫 검증 기록

- 전용 경로: `/Users/mac/quickemu/validation/macos-intel-sequoia`. 기존 Windows 경로와 분리.
- 원본 backend: Homebrew Quickemu/Quickget 4.9.9, QEMU 11.1.1, macOS 15.7.9, Intel i9-9880H.
- `quickget --arch amd64 --check macos sequoia`: PASS.
- `quickget --arch amd64 macos sequoia`: exit 0. Apple RecoveryImage 다운로드, OpenCore/UEFI 다운로드, config 생성.
- Homebrew에 `chunkcheck`가 없어 Quickget에서 검증 경고 발생. 변환 중 원본 DMG/chunklist가 남아 있을 때 부모 저장소의 `python3 chunkcheck <VM directory>`를 별도로 실행해 exit 0. 검사 파일 Git blob `9895340727d50f2d448eb311c3855c49a18187a3`; 로그 `verification.txt` 보관.
- 첫 부팅은 CPU vendor/AVX2 오인식으로 실패. 실제 `sysctl`에서 GenuineIntel, SSE4.2, leaf7의 AVX2 확인. [backend 패치](../../tool/backend-patches/quickemu-4.9.9-macos-cpu.patch)를 **검증 폴더의 사본**에만 적용. Homebrew/부모 Quickemu는 변경하지 않음.
- 수정 사본은 OpenCore의 **macOS Base System** 항목과 복구 커널 부팅까지 도달. 오디오 입력 오류를 피하기 위해 앱의 기본값과 동일한 `--sound-duplex hda-output` 사용. 호스트 폴더 공유는 `--public-dir none`으로 차단.
- backend 패치 검사: Bash 구문 검사 PASS, ShellCheck 0.11.0 원본/패치 모두 경고 0, CPU vendor 및 두 feature 목록/정확한 토큰 매칭 회귀 테스트 3개 PASS.
- Quickgui: `flutter analyze` 오류·info 0, 최종 `flutter test` 36 PASS / 외부 실행 opt-in 3 skipped. 테스트는 표시 파일 보관과 디스크/설정/매체 보존, 설치 환경 변수 제거, 공유·symlink 거부, 프로필의 ARM/조건문/중복·사용자 인자 거부를 포함. Manager 확인 창의 Cancel은 작업을 실행하지 않고, 완료 확인 뒤에도 별도의 Run을 눌러야 시작되는 것을 692×580 화면에서 검증.
- `flutter build macos --release`: PASS, 46.8 MB. 실행 파일과 App.framework에 x86_64/arm64 slice가 포함됨을 확인. 현재 Intel 호스트에서 빌드한 결과이며 ARM 호스트의 게스트 실행 검증을 뜻하지 않음.
- 릴리스 도구와 적용된 CPU 패치의 Python 테스트: 총 6 PASS. CPU 패치 테스트는 `QUICKGUI_PATCHED_QUICKEMU`와 Bash 4 이상 경로를 지정하여 실행.
- 실제 Windows config를 새 `VmRepository`로 읽는 별도 검사: PASS. 중지 상태, Windows x64, 설치 중 표시 인식 및 조건문 config의 자동 프로필 변환 거부 확인. 검사 전후 config bytes 동일. 이 검사는 Windows를 부팅하지 않음.
- macOS 복구 부팅은 서비스 초기화까지 진행했으나 여러 `vm_shared_region_start_address() failed` 메시지와 긴 지연을 관찰. 명시적 `+invtsc` 비교도 진행하며, 이것만으로 해결됐다고 주장하지 않음. 이 추가 인자는 검증 VM의 config에만 적용하고 범용 CPU 감지 패치에는 포함하지 않음.

추가 부팅/설치 결과는 이 문서에 이어서 기록하며, 위 중간 결과를 전체 macOS 설치 성공으로 승격하지 않는다.

## upstream과 개인용 경계

이번 프로필과 외부 설치 실행기 연동은 개인 후보에만 포함한다. 기존 `pr/*` 및 `integration/stabilization`의 공통 PR 후보와 `main`은 유지한다. CPU 감지 수정은 Quickgui가 아닌 **Quickemu** 변경 후보이며 별도 패치와 재현 테스트로 보관한다. 범용 설치 상태 모델은 명시적 설치/재개/설치 완료 계약이 backend에 마련된 뒤 공통 PR로 추출한다.

공식 자료: [Apple macOS 다운로드](https://support.apple.com/en-us/102662), [Apple Silicon macOS 가상 머신](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon), [Windows ARM64 ISO](https://www.microsoft.com/ko-kr/software-download/windows11arm64), [QEMU vmapple 지원 조건](https://www.qemu.org/docs/master/system/arm/vmapple.html).
