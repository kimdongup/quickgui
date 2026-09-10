# ARM 설치 이미지 다운로드

후속 갱신: macOS Apple Silicon은 다운로드 완료 후 또는 기존 IPSW 선택으로 VM 생성·설치와
Manager 실행까지 연결했다. 아래 최초 다운로드 전용 설명보다 [Apple VM 안내](APPLE_SILICON_VM.ko.md)를 우선한다.

2026-09-09. `personal/apple-silicon`의 개인 기능이다. 기존 OS → VERSION → DOWNLOAD
구성을 유지하면서 x64/ARM64를 첫 선택에서 구분한다.

| OS 선택 | VERSION | 다운로드 경로 |
| --- | --- | --- |
| macOS — Intel x64 | 기존 Quickget 릴리스 | Quickget에 `--arch amd64` 전달 |
| Windows — x64 | 기존 Windows 버전·언어 | Quickget에 `--arch amd64` 전달 |
| macOS — Apple Silicon ARM64 | Latest compatible | Apple API가 이 Mac에 맞는 최신 IPSW를 조회하고 앱이 저장 |
| Windows — ARM64 | 11 | Microsoft에서 발급받은 ARM64 ISO 링크를 앱이 저장 |

VERSION 화면 제목과 선택 후 OS 버튼에도 아키텍처를 유지한다. 기존 Windows Server도 x64로
표시한다. ARM 항목은 설치 이미지 전용이며 VM 생성·설치는 별도임을 선택 목록과 다운로드 화면에 표시한다.
기존 Quickget catalog 로딩·실패 재시도 흐름은 유지한다.

## Windows ARM64

1. OS에서 `Windows — ARM64`를 선택한다. 단일 VERSION `11`은 기존 동작대로 자동 선택된다.
2. DOWNLOAD에서 **Open Microsoft ARM64 downloads**를 누른다.
3. [Microsoft 공식 ARM64 ISO 페이지](https://www.microsoft.com/en-us/software-download/windows11arm64)에서
   제품과 언어를 선택하고, 생성된 ISO 다운로드 링크의 주소를 복사한다.
4. 앱의 **ARM64 ISO download link**에 붙여 넣고 **Download ISO**를 누른다.
5. 완료 화면의 실제 저장 경로를 확인하거나 **Open download folder**로 폴더를 연다.

Microsoft는 언어별 다운로드 링크를 발급하며 링크는 생성 후 24시간 유효하다고 안내한다.
만료되면 공식 페이지에서 새 링크를 발급받아 재시도한다. 링크 발급·언어 선택은 브라우저에서
사용자가 수행한다. 앱이 고정 ISO 주소를 저장하거나 비공개 Microsoft 링크 발급 API를 흉내 내지 않는다.
웹 페이지 주소나 x64 ISO 링크를 붙여 넣으면 다운로드 전에 오류를 표시한다.

## macOS Apple Silicon

1. OS에서 `macOS — Apple Silicon ARM64`를 선택한다.
2. DOWNLOAD를 열면 `VZMacOSRestoreImage.fetchLatestSupported`로 호환 이미지를 조회한다.
3. 실제 macOS 버전·build가 표시되면 **Download IPSW**를 누른다.
4. 완료 화면에서 저장된 IPSW 경로를 확인한다.

Apple Silicon Mac과 macOS 12 이상이 필요하다. Intel Mac/Linux 또는 조회 실패 시 다운로드를
시작하지 않고 설명과 재시도를 제공한다. macOS runner에는 Apple 이미지 조회에 필요한
`com.apple.security.virtualization` entitlement를 추가했다.
[Apple API 문서](https://developer.apple.com/documentation/virtualization/vzmacosrestoreimage/fetchlatestsupported(completionhandler:))와
설치된 Xcode SDK의 `VZMacOSRestoreImage.h`를 기준으로 구현했다.

## 파일 저장과 취소

선택한 VM 작업 폴더의 다음 위치에 저장한다. `<unique>`는 다운로드마다 생성하는 고유 이름이다.

```text
<workspace>/Install Media/windows-arm64-<unique>/Windows-11-ARM64.iso
<workspace>/Install Media/macos-arm64-<unique>/macOS-Apple-Silicon.ipsw
```

진행률과 수신 크기를 표시하며 서버가 크기를 제공하지 않으면 불확정 진행률을 사용한다.
메모리에 전체 이미지를 올리지 않고 파일로 스트리밍한다. 기존 이미지를 덮어쓰지 않으며,
전송 중에는 `.part` 파일을 사용하고 성공했을 때만 최종 파일명으로 바꾼다.
취소·실패 시 이번 전송의 임시 파일을 정리하며, 새 시도는 처음부터 다운로드한다. 이어받기는 구현하지 않았다.

공식 HTTPS 호스트와 리다이렉트 호스트를 검사한다. 성공 응답, 전송 길이(서버가 제공한 경우),
ISO/IPSW의 기본 파일 헤더를 확인한다. 이 검사는 전체 이미지의 SHA256 검증이나 게스트 부팅 검증을 대신하지 않는다.
Windows 파일의 ARM64 구분은 공식 링크의 파일명에 근거하며 ISO 내부 실행 파일을 분석한 판정은 아니다.
필요한 전체 SHA256 검증은 Microsoft 공식 페이지 등의 게시 값과 별도로 대조한다.
임시 인증 토큰이 들어갈 수 있는 다운로드 URL은 오류 로그나 별도 파일에 기록하지 않는다.

`.conf`나 가상 디스크를 만들지 않고 Manager 실행 버튼도 연결하지 않는다.
Windows ARM용 QEMU/HVF·UEFI·드라이버 구성과 macOS용 Virtualization 설치 흐름은 후속 작업이다.
다운로드 기능의 검증 결과는 [M1_VALIDATION.ko.md](M1_VALIDATION.ko.md)의 ARM 후속 기록을 따른다.
