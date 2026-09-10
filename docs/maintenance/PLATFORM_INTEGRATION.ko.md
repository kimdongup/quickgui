# Intel/M1 개인 후보 통합 검토

2026-09-10, Intel Mac에서 `personal/platform-integration`을 검토한다.

## 기준과 완료된 게스트 검증

| 기준 | 내용 |
| --- | --- |
| Intel `personal/preview` | `64cfd5991b889d7ff268a41362bed498229ccc7c`: macOS x64 설치·구동 사용자 확인 |
| M1 `personal/apple-silicon` | `f3f5c2bd807f0dbb7dc0e250e7c1996a68340586`: Windows ARM64 설치 후 앱 재실행 검증 |
| 공통 조상 | `fcee3f121bb61ea7c0114b0362b6d64632a1e1cf` |
| 마지막 M1 앱 코드 | `0517cf2`: Windows ARM64 네트워크 드라이버 수정 |

Windows ARM64의 초기 설정·바탕화면·입력·HTTPS·정상 종료/부팅은 사용자 확인 완료다. M1 실행 기록은 설치 완료 표시 저장, Quickgui 완전 종료·재실행, 같은 VM의 설치 ISO 없는 실행과 외부 TCP 연결을 확인했다. 이번 사용자는 macOS ARM의 바탕화면·재부팅·SSH도 직접 검증했다고 확인했다. 확인 주체와 상세 근거는 [M1 검증 기록](M1_VALIDATION.ko.md)을 따른다.

양쪽 브랜치의 이력을 merge로 보존하며 충돌은 `STATUS.ko.md`, `GUEST_VALIDATION.ko.md`의 검증 상태에만 발생했다. 각 호스트의 최신 사실을 유지하고 macOS ARM의 추가 사용자 확인을 기록했다. 이 통합에서 앱·의존성 코드를 새로 변경하지 않는다.

## Intel 검사

별도 worktree `/private/tmp/quickgui-platform-integration-20260910`에서 커밋된 lockfile로 검사한다. 기존 Intel 작업 폴더의 사용자 변경, M1의 미커밋 lockfile, 실행 중인 VM과 설치 이미지는 건드리지 않는다.

검사 결과는 실행 완료 후 여기에 기록한다. 사용자 보고와 이전 M1 CI 성공을 이번 Intel 검사 성공으로 대신하지 않는다.

## 공통 PR 경계와 다음 단계

- 공통 PATH `dc51dd0`의 [CI](https://github.com/kimdongup/quickgui/actions/runs/34506027934)와 파일 선택 `c59d53b`의 [CI](https://github.com/kimdongup/quickgui/actions/runs/34506028056)는 분석·테스트·Linux·Nix·macOS 성공, fork의 PPA 단계는 skipped다.
- M1 `f3f5c2b`의 [Build](https://github.com/kimdongup/quickgui/actions/runs/34519762183)와 [실제 Quickemu smoke](https://github.com/kimdongup/quickgui/actions/runs/34519762199)도 성공했다. 통합 후보의 새 CI 결과와 구분한다.
- 두 공통 브랜치는 `integration/stabilization` / `ae57d7d`에서 각각 분기했다. upstream `74949e0`에 그대로 제출하면 PATH는 14커밋·62파일, 파일 선택은 14커밋·63파일이다. [기존 제출 순서](UPSTREAM_PRS.md)에 맞춰 선행 변경이 수용된 뒤 범위를 다시 정리하거나 upstream 기준으로 개별 수정을 이식해야 한다.
- Intel 통합 검사를 통과한 개인 후보는 `personal/preview`로 반영한다. `main` 안정판 승격·공개 릴리스·upstream PR 제출은 별도 단계다.
- Intel macOS의 설치 후 재부팅·SSH·SPICE·앱 재접속, Windows ARM64의 SSH/SPICE·오디오·전체 게스트 도구, macOS ARM의 추가 공유·오디오 기능은 별도 검증 범위다. 이번 설치·기본 실사용 완료를 전체 수용 항목의 통과로 확대하지 않는다.
