# Windows 11 x64 미디어 준비 경로 수정

2026-09-11 HST TPM/UEFI 후속: 이전 Nehalem/HVF 프로필의 TPM·Secure Boot 비활성화 문제를 수정했다. Intel의 Windows 11 새 VM은 TPM 2.0과 SMM 보호 Secure Boot를 사용하는 TCG 프로필로 생성한다. 실제 설치 VM 보존·backend 수정·성능 영향은 [TPM/UEFI 수정 기록](WINDOWS_X64_TPM_UEFI.ko.md)을 따른다. 아래 최초 구현 기록보다 이 후속을 우선한다.

2026-09-11. 기준 `personal/preview` / `ceaf70c`.

## 원인

이전 Windows Intel 수정은 실행 환경의 `WINDOWS11_INSTALL` 제거, 설치 완료 표시
보존·확인, 선택형 Intel 하드웨어 프로필이었다. Windows x64 다운로드 버튼은 여전히
외부 Quickget을 호출했으므로 앱을 다시 빌드해도 다운로드 처리는 바뀌지 않았다.

로컬 `/Users/mac/quickemu/quickget`의 `get_windows`는 Windows ISO 다운로드 실패 후에도
VirtIO 다운로드·unattended ISO 생성·설정 생성을 계속할 수 있다. 앱의 DownloadSession은
프로세스 exit 0을 성공으로 사용했다. `--disable-unattended`의 설명만 보고 해당
경로에서 무인 설치 생성이 차단된다고 가정할 수 없다.

확인 당시 `/Users/mac/quickemu/windows-11-Korean/virtio-win.iso`는 **4,463바이트 HTML**이었다.
같은 폴더의 `unattended.iso`는 14,845,952바이트였으며 Windows 설치 ISO는 찾지 못했다.
무인 설치 ISO는 OS 설치 이미지가 아니라 응답 파일·보조 설치 프로그램으로 구성되므로
용량이 작은 사실만으로 손상을 판정하지 않는다. 기존 파일과 VM은 이번 수정에서 변경하지 않는다.

## 변경

- 기존 Windows → 11 → Download 선택에서 전용 x64 미디어 준비 화면으로 이동한다.
  Windows ARM64, macOS, Windows 10/Server의 메뉴 경로는 유지한다.
- [Microsoft 공식 x64 다운로드](https://www.microsoft.com/software-download/windows11) 페이지에서
  언어를 선택해 ISO를 받거나, 임시 직접 다운로드 링크를 앱에 붙여 넣는다.
  자동 링크 발급을 우회하지 않으며, 이미 받은 ISO를 선택할 수도 있다.
- HTTPS 공식 호스트·리디렉션, HTTP 상태, HTML 응답, 전송 길이, ISO/UDF 서명과
  최소 크기를 검사한다. x64 ISO는 최소 1 GiB, VirtIO는 최소 32 MiB를 요구한다.
  이 하한은 정상 파일의 고정 용량이 아니며 게시자의 해시 검증을 대체하지 않는다.
  로컬 ISO의 실제 아키텍처까지 판별하지는 않으므로 x64 이미지를 선택해야 한다.
- VirtIO는 선택 항목이다. [프로젝트가 안내하는 배포처](https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md)의
  ISO 링크를 사용하며 HTML이나 실패 응답은 성공으로 저장하지 않는다. 브라우저로
  받은 완전한 드라이버 ISO도 선택할 수 있다. 서버의 자동 요청 제한을 우회하지 않는다.
- Intel Mac에서는 기존 Nehalem/HVF·HPET·SATA·Intel NIC 프로필을 선택할 수 있다.
  이전 설치 경험을 따라 기본 선택하되 TPM/Secure Boot가 꺼지는 실험 설정임을 표시한다.
- 일반 수동 설치를 기본으로 한다. unattended ISO·응답 파일·설치 전용 실행기를
  자동 생성하거나 호출하지 않는다. 기존 무인 설치 파일도 삭제하지 않는다.
- 검증된 미디어를 참조하는 고유한 `windows-11-x64-*` VM 설정만 생성한다.
  디스크 생성·파티션 작업·부팅은 이 화면에서 하지 않는다. 기존 VM/ISO 이름을 재사용하지 않는다.
- 다운로드는 별도 미디어 폴더의 `.part`에 저장하고 성공한 파일만 최종 이름으로 바꾼다.

## 사용 순서

1. Windows — x64 / 11을 선택하고 Download를 누른다.
2. 공식 페이지에서 **x64와 원하는 언어**를 선택한다. ISO 직접 링크를 붙여 넣어
   다운로드하거나, 브라우저로 받은 ISO를 `Choose existing ISO`로 선택한다.
3. 필요할 때만 VirtIO ISO를 추가한다. Intel 프로필 설정을 확인하고 `Create VM`을 누른다.
4. VM 관리 화면으로 돌아가 새 VM을 실행하고 일반 Windows 설치 화면에서 진행한다.
   기존 설치가 끝난 VM을 사용하려면 새 설치 대신 원래 VM을 선택한다.

## 검증 범위

- 집중 검사 18개 통과: 가짜 HTML ISO·작은 불완전 파일 거부, ARM 링크 거부,
  기존 VM/이미지 보존, 고유한 새 설정 생성, Intel 프로필, 화면 버튼 상태,
  기존 ARM 미디어 다운로드·설치 완료 처리.
- 전체 Flutter 회귀: 92 PASS, 선택적 실제 환경 검사 4 skipped. `flutter analyze` 문제 0.
- macOS 릴리스 빌드 PASS (48.4 MB), deep/strict 서명 확인 PASS. 기존 window_size SPM 및 Run Script 경고는 유지된다.
- 빌드 위치: `/private/tmp/quickgui-windows-x64-media/build/macos/Build/Products/Release/quickgui.app`.
  기존 `/Applications/quickgui.app`이 실행 중이므로 이 작업에서는 교체하지 않았다. 종료 후 새 빌드로 교체해야 수정된 다운로드 화면을 사용할 수 있다.
- 새 Windows 11 전체 ISO 다운로드, 게스트 재설치·부팅 검증은 수행하지 않는다.
  사용자 요청에 따라 이번 수정에 필요한 코드 검사와 앱 빌드만 수행한다.
