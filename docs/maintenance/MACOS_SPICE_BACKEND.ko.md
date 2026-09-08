# Intel Mac의 SPICE backend 검증

2026-09-08. Homebrew QEMU 11.1.1에는 SPICE 서버가 포함되지 않아 공식 소스로
별도 backend를 만들었다. Quickgui 공통 수정과 개인 호스트의 backend 준비를 구분한다.

## 앱 수정

- 공통 `pr/spice-unix`, `integration/stabilization`, `pr/functional-regressions`: `ae57d7d`.
- 개인 `personal/preview`: `09fce12`.
- Quickemu 4.9.9의 기본 로컬 SPICE는 `.ports`에 `unix,<socket path>`를 기록한다.
  앱은 TCP `spice,<port>`만 읽어 연결 버튼을 활성화하지 못했다.
- 실제 Unix 소켓을 확인하고 상대 경로를 config 폴더 기준으로 해석한다. 공백,
  쉼표, `%`, 한글 경로를 보존한다. spice-gtk는 `spice+unix://` 뒤를 원문 경로로
  읽으므로 일반 URI percent encoding을 적용하지 않는다.
- 기존 Manager 연결 행과 버튼을 사용한다. 클릭 직전에 config, PID와 실행 상태를
  다시 조회하며 없어진 소켓에는 접속하지 않는다. 기존 TCP 연결은 유지한다.
- 공통 30 tests, 개인 43 tests와 양쪽 정적 분석 PASS. 개인 macOS release 앱
  46.8 MB, runner/App.framework의 x86_64·arm64 slice 확인.
- [공통 빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34262907080),
  [공통 실제 backend CI](https://github.com/kimdongup/quickgui/actions/runs/34262907061),
  [개인 빌드 CI](https://github.com/kimdongup/quickgui/actions/runs/34263261231),
  [개인 실제 backend CI](https://github.com/kimdongup/quickgui/actions/runs/34263261290): 모두 PASS.

## 서버와 QEMU

공식 [SPICE 다운로드](https://www.spice-space.org/download.html)의 0.16.0과
[QEMU 11.1.1](https://download.qemu.org/qemu-11.1.1.tar.xz)을 사용했다. 기록한 SHA256:

| 소스 | SHA256 |
| --- | --- |
| spice-0.16.0.tar.bz2 | `0a6ec9528f05371261bbb2d46ff35e7b5c45ff89bb975a99af95a5f20ff4717d` |
| qemu-11.1.1.tar.xz | `079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482` |

SPICE는 공식 HTTPS 파일의 로컬 체크섬을 기록했고, QEMU는 Homebrew 공식 formula의
체크섬과도 일치했다. 별도 서명 검증을 수행했다는 뜻은 아니다.

소스 변경 없이 SPICE의 autotools `configure`를 사용했다. Meson 경로는 Darwin에
없는 `librt`를 필수로 요구하지만 autotools는 선택적으로 검사한다. 임시 Python
venv에 pyparsing 3.3.2를 설치했다. 두 소스 모두 별도의 build 폴더에서 실행했다.

```sh
# SPICE 소스 안의 build 폴더. prefix는 전용 경로를 지정한다.
PYTHON=/private/tmp/quickgui-spice-build/venv/bin/python ../configure \
  --prefix=/private/tmp/quickgui-spice-build/prefix \
  --enable-gstreamer=no --with-sasl=no --enable-smartcard=no \
  --enable-manual=no --disable-static
make -j2
make -j2 check
make install

# QEMU 소스와 형제 관계인 qemu-build 폴더
PKG_CONFIG_PATH=/private/tmp/quickgui-spice-build/prefix/lib/pkgconfig \
  ../qemu-11.1.1/configure --target-list=x86_64-softmmu \
  --prefix=/private/tmp/quickgui-spice-build/qemu-prefix \
  --enable-spice --enable-slirp --enable-hvf --enable-cocoa --enable-coreaudio \
  --disable-docs --disable-werror --disable-gtk --disable-sdl \
  --disable-opengl --disable-virglrenderer --disable-guest-agent
ninja -j2 qemu-system-x86_64
```

SPICE 제공 테스트는 common 7 + server 18, 총 25 PASS. QEMU에서 SPICE server
0.16.0, HVF, Cocoa, slirp 지원과 `-spice help`, 코드 서명을 확인했다.

보존 경로는 `/Users/mac/quickemu/validation/spice-backend`다. `bin/quickemu`는 CPU
감지 패치가 적용된 검증 사본을 사용하고 이 폴더의 QEMU만 선택한다. QEMU와 SPICE
dylib 사본의 연결 경로를 상대 경로로 바꾸고 QEMU를 hypervisor entitlement로
ad-hoc 재서명했다. 실행기 두 개는 ShellCheck 경고 0이며 `manifest.json`에 체크섬을
보관했다. 시스템 `/usr/local/bin/qemu-system-x86_64`는 교체하지 않았다.

이 파일 묶음은 현재 Intel 호스트용이다. 기존 Homebrew 공유 라이브러리와
`/usr/local/share/qemu` 펌웨어를 사용하므로 다른 Mac에 그대로 배포할 수 있는
독립 패키지가 아니다. 바이너리는 Git 저장소에 포함하지 않는다.

## 실접속 증거와 범위

[재현 도구](../../tool/spice/README.md)는 256 MiB RAM, 새 16 MiB 검사 디스크와
vmware-svga를 사용한다. SPICE가 받은 720×400 화면을 저장하고 연결을 끊은 뒤 다시
접속했다. K 입력 후 게스트 메모리 `0x500`이 0에서 1로 바뀌었으며 수신 화면에
`KEYBOARD PASS`가 표시됐다. 실제 spicy의 main/display/inputs/cursor 채널도 확인했다.

![SPICE로 받은 키 입력 성공 화면](screenshots/spice-keyboard.png)

초기에는 spice-gtk 0.42/GStreamer 1.28.6의 플러그인 검색 때문에 짧은 접속 검사
시간을 초과했다. 프로세스 샘플과 플러그인 로그에서 검색이 진행 중임을 확인했다.
275개 플러그인의 별도 전체 캐시 생성은 약 166초 뒤 exit 0으로 완료됐다.
검색을 끈 진단 환경에 이어 **전체 캐시와 보존한 QEMU**에서도 화면·키 입력·재접속·
실제 spicy 채널 검사가 통과했다. 앱이 코덱 검색을 끄도록 변경하지 않았다.
[GStreamer의 캐시/검색 환경 변수](https://gstreamer.freedesktop.org/documentation/gstreamer/running.html)를
검증 프로세스에만 사용했다.

이후 기본 캐시 초기화도 16.7초에 exit 0으로 완료됐으며 `--registry`나
`--display-only` 없이 **기본 환경**에서 동일 검사가 통과했다. 검색 로그에는 일부
Python GI/GTK 플러그인 경고도 있으므로 모든 멀티미디어 플러그인의 정상 동작까지
검증했다는 뜻은 아니다.

실행 중 검사 VM을 앱의 실제 `VmRepository.inspect/list` 및 SPICE 인자 생성으로
읽는 검사도 PASS. config bytes는 변하지 않았다. 이는 설치된 macOS/Windows의
바탕화면·SSH·클립보드·파일 전송·오디오·USB 실사용 검증을 대신하지 않는다.

macOS 설치가 끝나고 게스트를 정상 종료한 뒤 전용 backend와 `display="spice"`로
재부팅하여 게스트 검증을 이어간다. 설치 중인 Cocoa VM의 디스크를 다른 QEMU로
동시에 열지 않는다. Windows ARM64 검증은 macOS Intel 단계의 결과 확정 후 진행한다.
