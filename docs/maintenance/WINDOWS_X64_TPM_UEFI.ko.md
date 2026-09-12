# Intel Windows 11: TPM 2.0와 Secure Boot 구성 수정

2026-09-11 HST / 2026-09-12 UTC. 기준 `efd57b9`.

## 원인과 최종 구성

기존 Intel 프로필은 Nehalem/HVF와 함께 TPM·Secure Boot를 끄고 있었다. 이전
설치 경험의 무인 설치 의존성을 제거한 뒤에도 이 프로필을 기본으로 사용한 것은
잘못이었다. 현재 설치 화면에서 TPM 2.0과 Secure Boot 지원 부족을 모두 확인했다.

또한 Quickemu 4.9.9는 `vm_boot`에서 `EFI_CODE`를 비우므로 설정 파일에 저장한
UEFI 경로가 무시됐다. 재현 도구는 알려진 초기화 문맥 한 곳만 수정하고 원본을
해시 이름의 백업으로 남긴다. 알 수 없는 구현에는 수정을 적용하지 않는다.
앱도 알려진 미수정 backend에서는 해당 Windows VM 생성·시작을 차단한다.

최종 Intel Windows 11 프로필:

- `boot="efi"`, `tpm="on"`, `secureboot="on"`.
- `swtpm --tpm2`, QEMU `tpm-tis` 장치. 기존 TPM 상태를 재생성하지 않는다.
- SMM 보호를 요구하는 `OVMF_CODE_4M.secboot.fd`와 Microsoft 키가 등록된
  `OVMF_VARS_4M.ms.fd`를 사용한다. 쓰기 가능한 변수 파일은 VM별 복사본이다.
- `-machine accel=tcg,smm=on,hpet=on -cpu max -smp 2,sockets=1,cores=2,threads=1`.
  **Intel HVF는 이 펌웨어에 필요한 SMM을 제공하지 못하므로 TCG로 실행한다.**
  하드웨어 가속보다 느리며 설치 시간·성능의 손해가 있다.
- 4 GB RAM, 2 vCPU, SATA, Intel NIC, Cocoa, audio off. 디스크·ISO 경로는 유지한다.
- Intel의 Windows 11 새 VM 화면에서 이 설정을 기본으로 사용하며, TPM을 끄는
  이전 프로필로 되돌리는 체크박스는 제거했다. 기존 홈 화면 선택 구조는 유지한다.

SMM 비필수 펌웨어와 HVF도 검토했지만 초기화가 진행되지 않았다. 플래시 보호를
`secure=off`로 끄는 시도는 자동 승인 검토에서 거부되어 **실행하지 않았다**.
최종 구성은 플래시 보호와 SMM을 유지한다. 설치 요구사항 우회 레지스트리,
응답 파일 또는 unattended ISO를 생성하지 않는다.

## 재현 가능한 backend 준비

```sh
python3 tool/prepare_windows_x64_firmware.py --quickemu /실제로/사용하는/quickemu
```

이 도구는 Debian의 `ovmf_2025.02-8+deb13u1_all.deb`를 공식 HTTPS 경로에서 받고
패키지와 두 펌웨어 파일의 고정 SHA-256을 검사한다. 펌웨어는 기본적으로
`~/.local/share/quickgui/firmware/windows-x64`에 설치된다. 다른 내용의 기존 파일을
덮어쓰지 않는다. `ar`와 Python 3가 필요하며, `swtpm`은 별도로 설치되어 있어야 한다.

Quickemu 초기화 수정은 `EFI_CODE=""`를 `EFI_CODE="${EFI_CODE:-}"`로 바꾸는 한 줄이다.
이 사용자의 `/Users/mac/quickemu/quickemu`와 앱의 기본 `/usr/local/bin/quickemu`
실제 파일에 각각 원본 백업 후 적용했다. 나머지 사용자 backend 수정은 보존했다.
Homebrew 재설치·업데이트가 해당 변경을 덮어쓰면 새 backend를 검토하고 다시 적용한다.
이 도구와 앱 수정은 개인 저장소에 포함하며 upstream PR #325에는 포함하지 않는다.

펌웨어 출처와 요구사항:

- [Debian OVMF 패키지](https://packages.debian.org/trixie/ovmf)
- [QEMU UEFI 변수 보호와 SMM](https://www.qemu.org/docs/master/devel/uefi-vars.html)
- [Microsoft Windows 11 요구사항](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements)

## 기존 VM 보존

대상은 `windows-11-x64-HiIuJ5`다. Windows PE에서 정상 종료한 뒤 기존 config,
NVRAM, 초기 384 KiB qcow2를 VM 폴더의 `before-tpm-20260912T065633Z`에 복사했다.
백업에는 SHA-256 목록도 있다. CPU·펌웨어 초기화 단계의 재시도마다 디스크 해시가
초기 값과 같음을 확인했다. Windows ISO와 VirtIO ISO는 기존 다운로드를 계속 참조한다.
이미 설치된 디스크를 재분할하거나 새 Windows VM을 만들지 않았다.

처음 TPM이 없던 초기 설치 VM이라 Microsoft 키가 들어 있는 새 변수 템플릿을
적용했다. 이 조치는 이미 설치·암호화된 다른 VM에 자동 적용하지 않는다. 앱의
새 VM 생성은 기존 VM의 NVRAM이나 TPM 상태를 교체하지 않는다.

## 검사 결과

- 전체 Flutter 94 PASS, 선택적 실제 환경 4 skipped. 정적 분석 문제 0.
- Python 도구 3 PASS: 기존 backend 백업·재실행 불변, 알 수 없는 구현 거부,
  변조 패키지 설치 차단.
- 수정된 두 Quickemu 파일은 Bash 구문 검사 통과. 이 Mac에 `shellcheck`가 없어
  ShellCheck는 실행하지 못했다.
- 최종 macOS release 빌드 48.4 MB 및 deep/strict 서명 검사 통과.
- 실제 VM에서 swtpm 프로세스·tpm-tis 장치·지정한 Secure Boot 코드/변수 파일·TCG/SMM 실행 인자를 확인했다. Windows 설치 ISO의 로딩 화면까지 진입했다.
- 설치 요구사항 화면의 통과 여부는 아래 후속 실사용 결과로 구분한다.
