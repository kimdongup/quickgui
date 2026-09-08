# 개인 패키지와 승격

개인 후보에는 기존 UI와 저작자 표시를 유지하며 설정 drawer에 `(kimdongup)`을 표시한다. 앱 ID와 설정 저장소는 기존 앱과 같다. 동시에 별도 설치하는 제품으로 포장하지 않는다.

`Fork release archives` workflow는 Linux `.tar.gz`와 macOS `.zip` 앱 번들을 생성한다. 두 산출물이 모두 있어야 수집을 통과하며 `SHA256SUMS`, `BUILD.json`에 checksum/소스 SHA/backend 검증 버전을 기록한다. 서명된 설치 프로그램이나 notarized 앱은 아니다.

- `personal/release-ops` push: build-only. GitHub Actions artifact로 후보 패키지 생성.
- 수동 실행, `publish=false`: build-only. `tag`를 비우면 선택한 브랜치 SHA를 사용.
- 기존 `fork-vX.Y.Z.N` 태그에 `publish=true` 또는 태그 push: pubspec `X.Y.Z+N`과 tag/SHA가 일치해야 **draft prerelease** 생성. 자동 정식 공개는 하지 않는다.
- `tool/fork_release.py` 한 곳에서 버전 매핑과 정확한 태그 검증을 관리한다. `git describe`의 가장 가까운 태그를 사용하지 않는다.
- fork에서는 기존 upstream PPA/FlakeHub publish와 자동 flake PR 작업을 실행하지 않는다.

현재 `1.2.10+1`의 후보 태그 이름은 `fork-v1.2.10.1`이다. 이번 구현에서 그 태그나 공개 릴리스를 생성하지 않았다. 같은 버전의 재배포를 피하려면 이후 소스 변경에 맞춰 build 번호와 lock 메타데이터를 함께 갱신한다.

첫 build-only 검증은 [34241482709](https://github.com/kimdongup/quickgui/actions/runs/34241482709)에서 통과했다. `fork-release-candidate` artifact에는 코드 `2f0d9fd`의 Linux x64/macOS ARM64 번들과 checksum/manifest가 있다. Actions artifact의 보관 기간이 지나면 같은 코드를 지정해 다시 생성할 수 있다.

정식 릴리스 전에는 [검증 기록](STATUS.ko.md)의 미완료 실사용 항목을 채우고, 해당 코드가 포함된 검증된 후보를 `main`에 merge한다. 앱 번들에서 실제 게스트 다운로드·시작·연결·중지·재접속을 확인한 후 draft를 검토한다. 문서만 추가된 SHA와 실제 빌드 SHA는 구분하여 기록한다.

Upstream 동기화는 별도 `sync/<date>` 브랜치에서 `upstream/main`을 통합하고 검사한다. `upstream-sync`는 fast-forward로만 갱신한다. 공유한 main·릴리스 이력에 force push하지 않는다. upstream에서 거절된 기능은 개인 브랜치에서 유지하되, 공통 결함 수정은 새로운 `pr/*` topic에서 만들어 양쪽에 반영한다.
