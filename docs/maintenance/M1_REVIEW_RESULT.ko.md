# M1 Quickgui 검토 완료 결과

검토일: 2026-09-10 (Pacific/Honolulu). 작업 브랜치: `personal/apple-silicon`.
검토 기준은 `aecabf86770735d43392402ec1a1ebe892aba4fe`이며, 마지막 앱 코드 변경은
Windows 네트워크 수정 `0517cf2`다. 이 문서와 함께 반영하는 변경은 검토·상태 문서 정리다.

## 결론과 검토 범위

요청한 M1 기능 구현과 Windows ARM64 네트워크 수정의 완료 기록을 정리했다.
기존 변경·테스트·실행 로그를 대조하고, 원격에 올릴 커밋과 lockfile만 별도 worktree에
체크아웃해 분석·전체 Flutter 회귀·macOS release 빌드를 검사했다.
게스트의 전체 설치와 실사용까지 검증 완료로 확대하지 않는다.

| 요청 항목 | 완료 결과 | 근거 커밋 |
| --- | --- | --- |
| Homebrew Bash 선택 오류 | 시스템 PATH가 앞인 환경에서도 자식 프로세스가 Homebrew Bash를 선택. 사용자 지정 경로와 Linux 동작 유지 | 공통 `dc51dd0`, 개인 `fb94a51` |
| ARM OS 구분·다운로드 | macOS Apple Silicon과 Windows ARM64 선택·설치 이미지 경로 구분. 공식 IPSW 조회 및 Windows ARM64 ISO 다운로드/기존 파일 사용 연결 | `bdd47d0` |
| Apple Silicon VM | IPSW 기반 생성·설치·Manager 실행 연결. M1에서 설치와 최초 언어 선택 화면, 새 프로세스 재실행 확인 | `6abf33b` |
| Windows ARM64 VM | QEMU/HVF, ARM64 UEFI Secure Boot, TPM, ISO·NVMe 연결. 실제 설치 화면 및 저장소 인식 확인 | `5e73b3d` |
| 파일 선택 오류 | Debug/Release에 사용자 선택 파일 read-write entitlement 적용. 실제 ISO 선택 창·자원 설정 화면 확인 | 공통 `c59d53b`, 개인 `1942c4e` |
| VM·설치 파일 삭제 | 이름 입력 확인, 실행·설치·참조·파일 변경·잠금 검사. 별도 시험 파일의 실제 삭제와 사용자 파일 유지 확인 | `f15e53b` |
| Windows 네트워크 | VirtIO Ethernet과 검증한 ARM64 NetKVM CD `QGNET`, 설치 안내 연결. 기존 VM 디스크·MAC 유지 | `0517cf2` |
| 실제 외부 통신 | 게스트 `10.0.2.15`의 공인 목적지 TCP 36개가 ESTABLISHED, 그중 목적지 포트 443이 25개 | 기록 `aecabf8` |

기존 Flutter 화면 구조를 유지하며 ARM VM·설치 파일 관리·네트워크 안내를 추가했다.
공통 수정 2개는 개인 VM 기능과 독립된 브랜치로 유지한다.

## 이번 원격 반영 전 재현 검사

기존 작업 폴더의 사용자 변경을 포함하지 않은 `/tmp/quickgui-push-review-20260910`에서 실행했다.
Flutter 3.47.2 / 번들 Dart 3.13.2를 사용했다.

| 검사 | 실제 결과 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | PASS: 커밋된 버전 그대로 준비, lockfile 변경 없음 |
| `flutter analyze --no-pub` | PASS: No issues found |
| `flutter test --no-pub --reporter expanded` | PASS: 82 passed / 4 external opt-in skipped |
| `flutter build macos --release --no-pub` | PASS: 48.1MB |
| `codesign --verify --deep --strict` | PASS: 새 release 앱 검증 |
| 실행 파일·App.framework 아키텍처 | PASS: 각각 x86_64 / arm64 |
| 검사 후 별도 worktree | PASS: 추적 파일 변경 없음, 커밋된 lockfile SHA256 유지 |

4개 skip은 외부 catalog/backend/download/VM opt-in 검사다. 이번 재현 검사에서
추가 실제 VM이나 다운로드를 시작하지 않았다. 실행 로그는
`/tmp/quickgui-push-review-logs-20260910/{pub-get,analyze,test,build}.log`에 있다.

빌드에는 기존 `window_size`의 Swift Package Manager 미지원 안내와 출력 파일이 없는
Run Script 단계 경고가 남아 있다. CocoaPods를 사용한 이번 macOS 빌드는 정상 종료했다.

이전 네트워크 수정 시에는 Windows 네이티브 22 checks, 네트워크 준비 도구 5 tests,
Windows·삭제 위젯 9 tests와 실제 QEMU/HVF/TPM 시작·중지 및 미디어 잠금 검사를 통과했다.
삭제 기능 단계의 실제 파일시스템 회귀 26 checks와 macOS 저장소 회귀 22 checks도 기록되어 있다.
이 수치는 단계별 기존 결과이며 이번에 모두 다시 실행했다는 뜻은 아니다.
자세한 실제 성공·실패 내역은 [M1 검증 기록](M1_VALIDATION.ko.md)을 따른다.

## 의존성과 로컬 데이터

`pubspec.yaml`, Flutter 버전 및 커밋된 lockfile을 변경하지 않았다.
시작부터 있던 작업 폴더의 `pubspec.lock` 변경은 이번 커밋·push에 포함하지 않고 보존한다.

| lockfile | SHA256 |
| --- | --- |
| 원격에 올리는 커밋·이번 별도 재현 검사 | `57d412434d34228eb7cb1901e92e697621ba8329504fd2f1d2a01231d424aeb6` |
| 기존 개인 작업 폴더·앞선 설치 앱 검증 | `c62192090c5902173f7919fc303041eb037019d52763bee97eb5292cae36187a` |

기존 미커밋 차이는 dio 5.11.0 → 5.11.1, dio_web_adapter 2.2.1 → 2.2.2,
platform 3.1.6 → 3.2.0이다. 이번에 의존성을 업그레이드하거나 되돌리지 않았다.

실행 중 앱과 사용자 VM은 이번 문서·원격 반영 작업에서 교체·재시작하지 않았다.
VM 디스크, ISO/IPSW, 호스트에 준비된 펌웨어·드라이버 CD, 앱 설정과 빌드 산출물은 Git으로 이전되지 않는다.
다른 Apple Silicon 호스트의 준비 절차는 [Windows ARM64 VM 안내](WINDOWS_ARM_VM.ko.md)와
[Apple Silicon VM 안내](APPLE_SILICON_VM.ko.md)를 따른다.

## 남아 있는 확인

- Windows: OOBE 완료, 바탕화면, 설치 완료 후 재부팅·종료, 게스트 브라우저의 HTTPS 응답, 오디오·전체 게스트 도구.
- macOS ARM: 사용자 계정 설정 후 바탕화면과 설치 완료 후 실사용·SSH 등.
- Intel MacBook으로 M1 원격 화면 연결을 실제 사용한 결과는 미검증이다. ARM VM 실행 호스트는 M1이다.
- `main` 승격, upstream PR 제출, 공개 릴리스·notarization은 이번 범위에 포함하지 않는다.

## 원격 반영

대상은 사용자 fork `https://github.com/kimdongup/quickgui.git`의 다음 브랜치다.
최초 `git push --atomic -u origin personal/apple-silicon pr/macos-homebrew-path
pr/macos-file-picker-entitlements`는 로컬 HTTPS 인증 정보가 없어 exit 128로 실패했다.
오류는 `could not read Username for 'https://github.com': Device not configured`다.
SSH agent에도 등록된 키가 없어 GitHub 로그인 후 push와 원격 SHA 확인이 남아 있다.
이 상태를 원격 반영 완료로 표시하지 않는다.

| 브랜치 | 역할 | 원격 코드 기준 |
| --- | --- | --- |
| `personal/apple-silicon` | M1 개인 기능·검증 문서 통합 | `aecabf8` + 이번 검토 문서 |
| `pr/macos-homebrew-path` | 공통 PATH 수정 | `dc51dd0` |
| `pr/macos-file-picker-entitlements` | 공통 파일 선택 entitlement 수정 | `c59d53b` |
