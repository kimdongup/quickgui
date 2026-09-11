# 첫 공통 PR: Flutter desktop 호환성

2026-09-11 UTC 최종 진행: 사용자 요청에 따라 PR #325의 Draft를 해제했다. 현재 **Open / Ready for review**, head `448e7e4`이며 코드 변경이나 merge는 하지 않았다. 아래 최초 제출 시점의 Draft·검증 기록은 이력으로 보존한다. 후속 공통 PR은 이 PR의 리뷰·수용 결과를 반영해 기존 순서대로 분리한다.

2026-09-10 HST / 2026-09-11 UTC. 사용자의 다음 PR 단계 요청에 따라 [upstream Draft PR #325](https://github.com/quickemu-project/quickgui/pull/325)를 제출했다.

| 항목 | 결과 |
| --- | --- |
| 제목 | `build!: update Flutter desktop compatibility` |
| 대상 | `quickemu-project/quickgui:main` |
| upstream 기준 | `74949e086154f3f2d555f9268778545c78ff2b51` |
| fork 브랜치 | `kimdongup/quickgui:pr/upstream-desktop-compatibility` |
| 제출 커밋 | `448e7e4922ec804578908f41ef07778deacf4dd2` |
| 변경 범위 | upstream 기준 단일 커밋, 40개 파일, +1279 / -925 |
| 상태 | Open / Ready for review. 사용자 요청으로 Draft 해제, merge하지 않음 |
| 작업 폴더 | `/private/tmp/quickgui-upstream-desktop-compatibility` |

기존 `pr/desktop-build`에는 SDK·의존성·네이티브 프로젝트·CI 기반이 있지만, 새 Flutter가 생성하지 않는 `AssetManifest.json`을 계속 읽고 새 file picker가 요구하는 권한도 빠져 있었다. 이 브랜치를 그대로 제출하지 않고 필요한 호환성 수정을 함께 포함했다. 기존 브랜치는 보존하고 새 PR 브랜치만 단일 커밋으로 정리했다.

## 포함한 변경과 영향

- Flutter 3.47.2 / Dart 3.13, Dart·Nix 의존성 lockfile, macOS 프로젝트와 CocoaPods fallback을 정렬했다. Dart API 갱신·분석·형식 검사에 따른 소스 정리를 포함한다.
- `getIcons()`가 Flutter의 binary AssetManifest API를 사용하고, 시작 시 아이콘 로드를 기다린다. 실제 테스트 bundle에서 기존 JSON 로더의 실패를 재현했다.
- 새 file picker의 호출 API와 Debug/Profile·Release의 user-selected read/write entitlement를 반영했다. 기존 주요 화면 구성을 유지한다.
- Nix의 Flutter input을 Quickemu runtime input과 분리하고 fastforge 0.6.12를 사용하도록 패키징 명령을 맞췄다.
- CI는 main 대상 PR/push와 수동 실행을 지원하며 분석·테스트·Linux·Nix·macOS 빌드를 검사한다. 개인 브랜치 패턴은 제외하고 upstream 전용 PPA/FlakeHub 배포 조건을 유지한다.

**호환성 영향:** macOS 최소 버전은 10.14에서 **12.0**으로 올라간다. 소스 빌드에는 Flutter 3.47.2 / Dart 3.13이 필요하다. PR 제목의 `!`, 본문과 커밋의 BREAKING CHANGE에 명시했다.

PR에는 개인 Toolchain/VM/ARM/SPICE 서비스, 설치 프로필·드라이버·VM 데이터·운영 문서를 넣지 않았다. 기존 PATH 후속 수정은 Toolchain 기반이 필요한 다음 startup/workspace PR로 남겼다.

## 검증

| 검사 | 결과 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | PASS, 커밋된 lockfile 유지 |
| 전체 Dart 형식 검사 | PASS, 32개 파일 변경 없음 |
| `flutter analyze --no-pub` | PASS, No issues found |
| 전체 공통 테스트 | PASS, 2개: locale 처리와 실제 bundle의 OS 아이콘 로드 |
| 새 asset 테스트의 수정 전 재현 | FAIL 재현, `getIcons()`에서 `AssetManifest.json` 로드 오류 / exit 1 |
| Intel macOS 15.7.9 Release 빌드 | PASS, 47.2 MB |
| deep/strict 앱 서명 검사 | PASS, ad-hoc 서명. notarization은 수행하지 않음 |
| 서명된 앱의 file picker 권한 | PASS, user-selected read/write=true |
| runner / App.framework | 각각 x86_64·arm64 slice 확인 |
| 실제 Release assets | AssetManifest.bin 존재, JSON manifest 없음 |
| YAML/JSON 의존성 lockfile | 내용 일치 |
| entitlement plist·diff 공백 검사 | PASS |
| 제출 커밋 fork CI | [실행 #34558437055](https://github.com/kimdongup/quickgui/actions/runs/34558437055) **전체 success**. 분석·테스트·Linux·Nix·macOS 성공, PPA는 조건에 따라 skipped |
| upstream PR 제목 검사 | PASS |
| upstream 빌드 CI | [실행 #34558542663](https://github.com/quickemu-project/quickgui/actions/runs/34558542663) `action_required`. fork의 실행 성공과 구분하여 upstream 실행 승인 대기로 기록 |

macOS 빌드는 `window_size`의 Swift Package Manager 미지원 안내와 기존 Run Script 출력 경고를 남겼고 CocoaPods fallback으로 exit 0이었다. 기존 설치 앱을 교체하거나 사용자 VM을 이 후보로 다시 실행하지 않았다. 이 PR의 설치 게스트 GUI 전체 흐름, Linux/macOS 수동 화면 조작, release 패키징 형식별 실행·배포는 완료로 표시하지 않는다. 개인 브랜치에서 수행한 82개 테스트나 게스트 검증을 이 PR 커밋의 결과로 옮겨 적지 않았다.

로컬 빌드 로그는 `/private/tmp/quickgui-upstream-desktop-release.log`에 있다. 제출 소스와 PR의 head SHA·Draft 상태·단일 커밋·40개 파일 범위를 GitHub에서 다시 확인했다. 기존 개인 작업 폴더의 사용자 변경은 보존했다.

## 관련 PR과 다음 순서

- [#303](https://github.com/quickemu-project/quickgui/pull/303): startup/manifest 문제와 관련된다. 이번 변경은 공식 binary manifest API를 사용하며 해당 PR 전체를 복사하지 않았다.
- [#322](https://github.com/quickemu-project/quickgui/pull/322): packaging dependency 업데이트와 겹치며 이번 fastforge 전환을 본문에 설명했다.
- [#317](https://github.com/quickemu-project/quickgui/pull/317): 같은 flake.lock의 다른 input 갱신이므로 병합 전 함께 조정한다.

첫 PR의 CI·리뷰 결과를 반영한 뒤 accepted upstream 기준에서 startup/workspace/PATH → download lifecycle → VM actions/SPICE → selection usability 순서로 다음 PR 범위를 다시 만든다. 기존 종속 브랜치를 그대로 연속 제출하지 않는다. 큐는 [UPSTREAM_PRS.md](UPSTREAM_PRS.md)를 따른다.

개인 Windows ARM64 SSH/SPICE 구현·실사용은 [맥미니 인계 문서](M1_WINDOWS_CONNECTION_HANDOFF.ko.md)에 따라 별도 worktree에서 이어간다. Intel 실제 spicy 창의 직접 입력과 앱 GUI 전체 접속 흐름도 [기존 검증 기록](MACOS_SPICE_BACKEND.ko.md)의 미확인 범위를 유지한다. 첫 공통 PR 제출이 이 항목들의 완료를 뜻하지 않는다.
